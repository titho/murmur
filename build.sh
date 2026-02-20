#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building Murmur..."
xcodebuild -scheme Murmur -configuration Release CODE_SIGNING_ALLOWED=NO ARCHS=arm64 | tail -5

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Murmur-* -name "Murmur.app" -maxdepth 5 | head -1)
echo "Built: $APP_PATH"
echo "Copying to /Applications..."
cp -R "$APP_PATH" /Applications/Murmur.app

echo "Done. Launch with: open /Applications/Murmur.app"
