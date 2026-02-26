#!/bin/bash
set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Skip xcodegen if project.yml hasn't changed since .xcodeproj was last generated
PROJ_YML="$PROJECT_DIR/project.yml"
XCODEPROJ="$PROJECT_DIR/Murmur.xcodeproj"
if [ ! -d "$XCODEPROJ" ] || [ "$PROJ_YML" -nt "$XCODEPROJ" ]; then
  echo "▶ Generating project (project.yml changed)..."
  cd "$PROJECT_DIR"
  xcodegen generate --quiet
else
  echo "▶ Skipping xcodegen (project.yml unchanged)"
fi

echo "▶ Building..."
xcodebuild \
  -scheme Murmur \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  -quiet 2>&1 | grep -v "^ld: warning"

echo "▶ Installing to ~/Applications..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Murmur-* -name "Murmur.app" -type d 2>/dev/null | grep "/Debug/" | head -1)
mkdir -p ~/Applications
rm -rf ~/Applications/Murmur.app
cp -r "$APP_PATH" ~/Applications/Murmur.app

echo "▶ Signing..."
# Use a dedicated keychain so cert creation is fully non-interactive (CI-style).
# The keychain is owned by this script — no Keychain Access GUI needed, ever.
CERT_NAME="Murmur Dev"
SIGNING_KC="$HOME/Library/Keychains/murmur-dev-signing.keychain-db"
SIGNING_KC_PASS="murmur-dev-build-key"

# Create keychain on first run
if [ ! -f "$SIGNING_KC" ]; then
  echo "  ▸ Creating dedicated signing keychain (first-time, one-off)..."
  security create-keychain -p "$SIGNING_KC_PASS" "$SIGNING_KC"
  security set-keychain-settings "$SIGNING_KC"   # disable auto-lock
fi
security unlock-keychain -p "$SIGNING_KC_PASS" "$SIGNING_KC" 2>/dev/null || true

# Add to the keychain search list so codesign can find the identity
# (trust settings added via add-trusted-cert only take effect when keychain is in the list)
if ! security list-keychains -d user | grep -q "murmur-dev-signing"; then
  CURRENT_KC=$(security list-keychains -d user | tr -d '"' | tr -d ' ' | tr '\n' ' ')
  security list-keychains -d user -s "$SIGNING_KC" $CURRENT_KC
fi

# Generate and import a self-signed code-signing cert on first run
if ! security find-certificate -c "$CERT_NAME" "$SIGNING_KC" > /dev/null 2>&1; then
  echo "  ▸ Generating code-signing certificate (first-time, one-off)..."
  _TMP=$(mktemp -d)
  # OpenSSL config: codeSigning EKU is required for codesign to accept the cert
  cat > "$_TMP/cert.conf" << 'CERTEOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req
[dn]
CN = Murmur Dev
[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
CERTEOF
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$_TMP/key.pem" -out "$_TMP/cert.pem" \
    -days 3650 -config "$_TMP/cert.conf" 2>/dev/null
  # Import cert and key separately (avoids PKCS12 MAC compatibility issues)
  security import "$_TMP/cert.pem" -k "$SIGNING_KC" -A > /dev/null
  security import "$_TMP/key.pem"  -k "$SIGNING_KC" -A -T /usr/bin/codesign > /dev/null
  # Trust the cert for code signing in our keychain (required for codesign to use it)
  security add-trusted-cert -k "$SIGNING_KC" "$_TMP/cert.pem"
  # Pre-authorise Apple tools so codesign never shows an interactive prompt
  security set-key-partition-list \
    -S "apple-tool:,apple:" -s -k "$SIGNING_KC_PASS" "$SIGNING_KC" 2>/dev/null
  rm -rf "$_TMP"
  echo "  ✓ Certificate created"
fi

codesign --sign "$CERT_NAME" --force --deep ~/Applications/Murmur.app
echo "  ✓ Signed with '$CERT_NAME' — accessibility permission persists across rebuilds"

echo "▶ Relaunching..."
pkill -x "Murmur" 2>/dev/null || true
sleep 0.3
open ~/Applications/Murmur.app
echo "✓ Done — app installed at ~/Applications/Murmur.app"
