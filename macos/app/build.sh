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
# Sign with the Steerpin certificate so every build keeps the same identity and macOS keeps
# the Accessibility permission across updates. Falls back to ad-hoc signing without it.
identity=$(security find-identity -p codesigning 2>/dev/null | awk '/"Steerpin Code Signing"/ {print $2; exit}')
if [ -z "$identity" ]; then
  echo "warning: 'Steerpin Code Signing' certificate not found; ad-hoc signing (users must re-allow Accessibility after updating)" >&2
  identity=-
fi
codesign --force --sign "$identity" --identifier com.gregkozakiewicz.steerpin build/Steerpin.app
ditto -c -k --keepParent build/Steerpin.app build/Steerpin.zip
echo "Built $(pwd)/build/Steerpin.app"
