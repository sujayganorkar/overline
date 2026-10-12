#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-"$ROOT/assets/icon/app_logo.png"}"

if [[ ! -f "$SOURCE" ]]; then
    if [[ -f "$ROOT/PdfCraft Red Document Logo.png" ]]; then
        SOURCE="$ROOT/PdfCraft Red Document Logo.png"
    else
        echo "Error: Source logo file not found: $SOURCE" >&2
        exit 1
    fi
fi

if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
    echo "Error: ImageMagick (magick or convert) is required." >&2
    exit 1
fi

CONVERT_CMD="magick"
if ! command -v magick >/dev/null 2>&1; then
    CONVERT_CMD="convert"
fi

echo "Generating launcher icons from: $SOURCE"

# 1. Android Legacy Launcher Icons (ic_launcher.png)
declare -A ANDROID_LEGACY_SIZES=(
    ["mdpi"]="48"
    ["hdpi"]="72"
    ["xhdpi"]="96"
    ["xxhdpi"]="144"
    ["xxxhdpi"]="192"
)

for dpi in "${!ANDROID_LEGACY_SIZES[@]}"; do
    size="${ANDROID_LEGACY_SIZES[$dpi]}"
    target_dir="$ROOT/android/app/src/main/res/mipmap-$dpi"
    mkdir -p "$target_dir"
    "$CONVERT_CMD" "$SOURCE" \
        -resize "${size}x${size}" \
        -gravity center \
        -background none \
        -extent "${size}x${size}" \
        "$target_dir/ic_launcher.png"
    echo "Generated Android legacy: mipmap-$dpi/ic_launcher.png (${size}x${size})"
done

# 2. Android Adaptive Icons (Foreground & XML)
declare -A ANDROID_ADAPTIVE_SIZES=(
    ["mdpi"]="108:72"
    ["hdpi"]="162:108"
    ["xhdpi"]="216:144"
    ["xxhdpi"]="324:216"
    ["xxxhdpi"]="432:288"
)

for dpi in "${!ANDROID_ADAPTIVE_SIZES[@]}"; do
    spec="${ANDROID_ADAPTIVE_SIZES[$dpi]}"
    canvas_size="${spec%%:*}"
    inner_size="${spec##*:}"
    target_dir="$ROOT/android/app/src/main/res/mipmap-$dpi"
    mkdir -p "$target_dir"
    "$CONVERT_CMD" "$SOURCE" \
        -resize "${inner_size}x${inner_size}" \
        -gravity center \
        -background none \
        -extent "${canvas_size}x${canvas_size}" \
        "$target_dir/ic_launcher_foreground.png"
    echo "Generated Android adaptive: mipmap-$dpi/ic_launcher_foreground.png (${canvas_size}x${canvas_size})"
done

# Android colors.xml for adaptive icon background
mkdir -p "$ROOT/android/app/src/main/res/values"
cat <<'EOF' > "$ROOT/android/app/src/main/res/values/colors.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
EOF

# Android adaptive icon XML (API 26+)
mkdir -p "$ROOT/android/app/src/main/res/mipmap-anydpi-v26"
cat <<'EOF' > "$ROOT/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF

# 3. iOS Icons (ios/Runner/Assets.xcassets/AppIcon.appiconset)
IOS_DIR="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$IOS_DIR"

# Generate high-res base for iOS (1024x1024 with white background for App Store compliance)
TEMP_IOS_BASE="$(mktemp --suffix=.png)"
"$CONVERT_CMD" "$SOURCE" \
    -resize 820x820 \
    -gravity center \
    -background white \
    -extent 1024x1024 \
    -alpha remove \
    -alpha off \
    "$TEMP_IOS_BASE"

declare -A IOS_SIZES=(
    ["Icon-App-20x20@1x.png"]="20"
    ["Icon-App-20x20@2x.png"]="40"
    ["Icon-App-20x20@3x.png"]="60"
    ["Icon-App-29x29@1x.png"]="29"
    ["Icon-App-29x29@2x.png"]="58"
    ["Icon-App-29x29@3x.png"]="87"
    ["Icon-App-40x40@1x.png"]="40"
    ["Icon-App-40x40@2x.png"]="80"
    ["Icon-App-40x40@3x.png"]="120"
    ["Icon-App-60x60@2x.png"]="120"
    ["Icon-App-60x60@3x.png"]="180"
    ["Icon-App-76x76@1x.png"]="76"
    ["Icon-App-76x76@2x.png"]="152"
    ["Icon-App-83.5x83.5@2x.png"]="167"
    ["Icon-App-1024x1024@1x.png"]="1024"
)

for filename in "${!IOS_SIZES[@]}"; do
    size="${IOS_SIZES[$filename]}"
    "$CONVERT_CMD" "$TEMP_IOS_BASE" \
        -resize "${size}x${size}" \
        "$IOS_DIR/$filename"
    echo "Generated iOS icon: $filename (${size}x${size})"
done

rm -f "$TEMP_IOS_BASE"

echo "All launcher icons generated successfully!"

