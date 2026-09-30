#!/bin/sh
# Builds Steerpin.app (universal, ad-hoc signed) into macos/app/build/ and zips it for release.
set -e
cd "$(dirname "$0")"
rm -rf build && mkdir -p build/Steerpin.app/Contents/MacOS
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/*.swift -o "build/Steerpin-$arch"
done
lipo -create build/Steerpin-arm64 build/Steerpin-x86_64 -output build/Steerpin.app/Contents/MacOS/Steerpin
rm build/Steerpin-arm64 build/Steerpin-x86_64
cp Info.plist build/Steerpin.app/Contents/Info.plist
codesign --force --sign - --identifier com.gregkozakiewicz.steerpin build/Steerpin.app
ditto -c -k --keepParent build/Steerpin.app build/Steerpin.zip
echo "Built $(pwd)/build/Steerpin.app"
