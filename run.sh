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
CERT_NAME="Murmur Dev"
if security find-certificate -c "$CERT_NAME" > /dev/null 2>&1; then
  codesign --sign "$CERT_NAME" --force --deep ~/Applications/Murmur.app
  echo "  ✓ Signed with '$CERT_NAME' (accessibility will persist across rebuilds)"
else
  codesign --sign - --force --deep ~/Applications/Murmur.app
  echo "  ⚠ Signed ad-hoc — accessibility permission will reset each rebuild"
  echo "  Fix: Keychain Access → Certificate Assistant → Create a Certificate"
  echo "       Name: 'Murmur Dev' | Self Signed Root | Code Signing"
fi

echo "▶ Relaunching..."
pkill -x "Murmur" 2>/dev/null || true
sleep 0.3
open ~/Applications/Murmur.app
echo "✓ Done — app installed at ~/Applications/Murmur.app"
