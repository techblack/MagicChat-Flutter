#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_svg="$repo_root/linux/runner/resources/magicchat.svg"

if ! command -v convert >/dev/null 2>&1; then
  echo "需要 ImageMagick convert 才能生成应用图标" >&2
  exit 1
fi

render_transparent() {
  local size="$1"
  local output="$2"
  convert -background none -density 768 "$source_svg" \
    -resize "${size}x${size}!" -strip "PNG32:$output"
}

render_opaque() {
  local size="$1"
  local output="$2"
  convert -background '#3a76f0' -density 768 "$source_svg" \
    -resize "${size}x${size}!" -alpha remove -alpha off -strip "PNG24:$output"
}

render_transparent 48 \
  "$repo_root/android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
render_transparent 72 \
  "$repo_root/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
render_transparent 96 \
  "$repo_root/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
render_transparent 144 \
  "$repo_root/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
render_transparent 192 \
  "$repo_root/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

for size in 16 32 64 128 256 512 1024; do
  render_transparent "$size" \
    "$repo_root/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${size}.png"
done

declare -a ios_icons=(
  'Icon-App-20x20@1x.png:20'
  'Icon-App-20x20@2x.png:40'
  'Icon-App-20x20@3x.png:60'
  'Icon-App-29x29@1x.png:29'
  'Icon-App-29x29@2x.png:58'
  'Icon-App-29x29@3x.png:87'
  'Icon-App-40x40@1x.png:40'
  'Icon-App-40x40@2x.png:80'
  'Icon-App-40x40@3x.png:120'
  'Icon-App-60x60@2x.png:120'
  'Icon-App-60x60@3x.png:180'
  'Icon-App-76x76@1x.png:76'
  'Icon-App-76x76@2x.png:152'
  'Icon-App-83.5x83.5@2x.png:167'
  'Icon-App-1024x1024@1x.png:1024'
)
for icon in "${ios_icons[@]}"; do
  filename="${icon%%:*}"
  size="${icon##*:}"
  render_opaque "$size" \
    "$repo_root/ios/Runner/Assets.xcassets/AppIcon.appiconset/$filename"
done

render_transparent 32 "$repo_root/web/favicon.png"
render_transparent 192 "$repo_root/web/icons/Icon-192.png"
render_transparent 512 "$repo_root/web/icons/Icon-512.png"
render_opaque 192 "$repo_root/web/icons/Icon-maskable-192.png"
render_opaque 512 "$repo_root/web/icons/Icon-maskable-512.png"

temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "$temporary_dir"' EXIT
windows_sizes=(16 20 24 32 40 48 64 128 256)
windows_frames=()
for size in "${windows_sizes[@]}"; do
  frame="$temporary_dir/windows-${size}.png"
  render_transparent "$size" "$frame"
  windows_frames+=("$frame")
done
convert "${windows_frames[@]}" \
  "$repo_root/windows/runner/resources/app_icon.ico"

echo "已从 linux/runner/resources/magicchat.svg 生成全平台品牌图标"
