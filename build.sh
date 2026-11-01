#!/bin/bash
# Builds build/Visualizer.app with just the Command Line Tools (no Xcode project).
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Visualizer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/Visualizer"
cp Sources/Shaders.metal "$APP/Contents/Resources/" # compiled at launch by Metal, no metal toolchain needed
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP — open it with: open $APP"
