#!/bin/bash
set -euo pipefail
sdk="${1:-${SNAPBEAUTY_SDK_ROOT:-}}"
out="${2:-build/macos}"
bundle_id="${SNAPBEAUTY_BUNDLE_ID:-ai.snapbeauty.samples.macos}"
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$sdk/include/snapbeauty/desktop.h" || ! -f "$sdk/lib/libSnapBeauty.dylib" ||
      ! -d "$sdk/Assets" || ! -d "$sdk/Shaders" ]]; then
    echo "Pass the extracted macOS SDK root or set SNAPBEAUTY_SDK_ROOT." >&2
    exit 2
fi
if [[ ! "$bundle_id" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    echo "Set a valid reverse-DNS SNAPBEAUTY_BUNDLE_ID." >&2
    exit 2
fi
mkdir -p "$(dirname "$out")"
mkdir "$out" || { echo "Choose a new build directory for each build." >&2; exit 2; }

app="$out/SnapBeautyCamera.app"
mkdir -p "$app/Contents/"{MacOS,Frameworks,Resources}
xcrun clang -arch arm64 -mmacosx-version-min=12.0 -O2 -Wall -Wextra -fobjc-arc \
    -I"$sdk/include" "$root/macos/main.m" -L"$sdk/lib" -lSnapBeauty \
    -Wl,-rpath,@executable_path/../Frameworks \
    -framework AppKit -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreGraphics \
    -o "$app/Contents/MacOS/SnapBeautyCamera"
xcrun clang -arch arm64 -mmacosx-version-min=12.0 -std=c11 -O2 -Wall -Wextra \
    -I"$sdk/include" "$root/examples/minimal.c" -L"$sdk/lib" -lSnapBeauty \
    -Wl,-rpath,@executable_path/SnapBeautyCamera.app/Contents/Frameworks \
    -o "$out/snapbeauty-minimal"

ditto "$sdk/lib/libSnapBeauty.dylib" "$app/Contents/Frameworks/libSnapBeauty.dylib"
ditto "$sdk/Assets" "$app/Contents/Resources/Assets"
ditto "$sdk/Shaders" "$app/Contents/Resources/Shaders"
ditto "$root/assets/makeup" "$app/Contents/Resources/Assets/makeup"
ditto "$root/assets/sample_makeup" "$app/Contents/Resources/Assets/sample_makeup"
if [[ "$bundle_id" == "ai.snapbeauty.samples.macos" && -f "$root/macos/SampleLicense/snapbeauty.license" ]]; then
    cp "$root/macos/SampleLicense/snapbeauty.license" "$app/Contents/Resources/snapbeauty.license"
fi
cp "$root/macos/Info.plist" "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
# Keep the packaged SDK dylib signature intact when signing the local host.
codesign --force --sign - "$app"
echo "Built $app and $out/snapbeauty-minimal"
