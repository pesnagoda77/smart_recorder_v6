#!/bin/bash
# Generate Android launcher icons from source image

SOURCE="assets/icons/launcher_icon.png"
BASE="android/app/src/main/res"

# Check if source exists
if [ ! -f "$SOURCE" ]; then
    echo "Error: Source image not found at $SOURCE"
    exit 1
fi

# Check if ImageMagick is available
if ! command -v convert &> /dev/null; then
    echo "Error: ImageMagick not found. Install with: apt-get install imagemagick"
    exit 1
fi

# Generate icons for each density
echo "Generating launcher icons..."

# mdpi: 48x48
convert "$SOURCE" -resize 48x48 "$BASE/mipmap-mdpi/ic_launcher.png"
convert "$SOURCE" -resize 48x48 "$BASE/mipmap-mdpi/ic_launcher_round.png"

# hdpi: 72x72
convert "$SOURCE" -resize 72x72 "$BASE/mipmap-hdpi/ic_launcher.png"
convert "$SOURCE" -resize 72x72 "$BASE/mipmap-hdpi/ic_launcher_round.png"

# xhdpi: 96x96
convert "$SOURCE" -resize 96x96 "$BASE/mipmap-xhdpi/ic_launcher.png"
convert "$SOURCE" -resize 96x96 "$BASE/mipmap-xhdpi/ic_launcher_round.png"

# xxhdpi: 144x144
convert "$SOURCE" -resize 144x144 "$BASE/mipmap-xxhdpi/ic_launcher.png"
convert "$SOURCE" -resize 144x144 "$BASE/mipmap-xxhdpi/ic_launcher_round.png"

# xxxhdpi: 192x192
convert "$SOURCE" -resize 192x192 "$BASE/mipmap-xxxhdpi/ic_launcher.png"
convert "$SOURCE" -resize 192x192 "$BASE/mipmap-xxxhdpi/ic_launcher_round.png"

# Foreground for adaptive icons (needed for API 26+)
convert "$SOURCE" -resize 108x108 "$BASE/mipmap-anydpi-v26/ic_launcher_foreground.png"

# Background (solid color from icon)
convert -size 108x108 xc:"#2C3E50" "$BASE/mipmap-anydpi-v26/ic_launcher_background.png"

echo "Done! Icons generated for all densities."
echo "Build APK to see changes."