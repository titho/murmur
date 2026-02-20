#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▶ Generating project..."
cd "$PROJECT_DIR"
xcodegen generate --quiet

echo "▶ Building..."
xcodebuild \
  -scheme Murmur \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  -quiet 2>&1 | grep -v "^ld: warning"

echo "▶ Relaunching..."
pkill -x "Murmur" 2>/dev/null || true
sleep 0.3
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Murmur-* -name "Murmur.app" -type d 2>/dev/null | grep "/Debug/" | head -1)
open "$APP_PATH"
echo "✓ Done"
