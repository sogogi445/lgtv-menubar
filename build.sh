#!/bin/sh
# Build "LG TV.app" (a menu bar app) into ./build
#
#   ./build.sh                      # universal (Apple silicon + Intel)
#   ARCHS="arm64" ./build.sh        # a single architecture
#
# Requires the Xcode command line tools (xcode-select --install). No Xcode project needed.
set -e
cd "$(dirname "$0")"

ARCHS="${ARCHS:-arm64 x86_64}"
APP="build/LG TV.app"
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for A in $ARCHS; do
  swiftc -O -swift-version 5 -target "$A-apple-macos13.0" src/main.swift \
    -o "build/obj/LGTVBar-$A" -framework Cocoa -framework ServiceManagement
done

if [ "$(echo $ARCHS | wc -w)" -gt 1 ]; then
  lipo -create build/obj/LGTVBar-* -output "$APP/Contents/MacOS/LGTVBar"
else
  cp "build/obj/LGTVBar-$ARCHS" "$APP/Contents/MacOS/LGTVBar"
fi

cp Info.plist "$APP/Contents/Info.plist"
cp res/registration.json "$APP/Contents/Resources/registration.json"
cp -R res/en.lproj res/ko.lproj "$APP/Contents/Resources/"
rm -rf build/obj

# Ad-hoc signature (no developer account needed). Gatekeeper will still ask on first launch.
codesign --force --deep -s - "$APP"
echo "built: $APP"
