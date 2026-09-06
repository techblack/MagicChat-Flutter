#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v identify >/dev/null 2>&1 || \
   ! command -v convert >/dev/null 2>&1; then
  echo "需要 ImageMagick identify 和 convert 才能校验应用图标" >&2
  exit 1
fi

check_png() {
  local path="$1"
  local size="$2"
  local opacity="$3"
  local dimensions format opaque
  dimensions="$(identify -format '%wx%h' "$repo_root/$path")"
  format="$(identify -format '%m' "$repo_root/$path")"
  opaque="$(identify -format '%[opaque]' "$repo_root/$path")"
  if [[ "$dimensions" != "${size}x${size}" || "$format" != 'PNG' ]]; then
    echo "$path 应为 ${size}x${size} PNG，实际为 $dimensions $format" >&2
    exit 1
  fi
  if [[ "$opaque" != "$opacity" ]]; then
    echo "$path 透明度不符合预期：opaque=$opaque，预期 $opacity" >&2
    exit 1
  fi
}

check_brand_palette() {
  local path="$1"
  local colors
  colors="$(convert "$repo_root/$path" -alpha off -resize 128x128! \
    -format '%[pixel:p{64,8}] %[pixel:p{64,64}]' info:)"
  if [[ "$colors" != *'58,118,240'* ||
        ( "$colors" != *'255,255,255'* && "$colors" != *'white'* ) ]]; then
    echo "$path 未检测到预期的 MagicChat 蓝色和白色区域：$colors" >&2
    exit 1
  fi
}

declare -a transparent_pngs=(
  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png:48'
  'android/app/src/main/res/mipmap-hdpi/ic_launcher.png:72'
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png:96'
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png:144'
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png:192'
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png:16'
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png:32'
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png:64'
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png:128'
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png:256'
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png:512'
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png:1024'
  'web/favicon.png:32'
  'web/icons/Icon-192.png:192'
  'web/icons/Icon-512.png:512'
)
for icon in "${transparent_pngs[@]}"; do
  path="${icon%%:*}"
  size="${icon##*:}"
  check_png "$path" "$size" false
done

declare -a opaque_pngs=(
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png:20'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png:40'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png:60'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png:29'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png:58'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png:87'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png:40'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png:80'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png:120'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png:120'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png:180'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png:76'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png:152'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png:167'
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png:1024'
  'web/icons/Icon-maskable-192.png:192'
  'web/icons/Icon-maskable-512.png:512'
)
for icon in "${opaque_pngs[@]}"; do
  path="${icon%%:*}"
  size="${icon##*:}"
  check_png "$path" "$size" true
done

expected_ico_sizes=$'16x16\n20x20\n24x24\n32x32\n40x40\n48x48\n64x64\n128x128\n256x256'
actual_ico_sizes="$(identify -format '%wx%h\n' \
  "$repo_root/windows/runner/resources/app_icon.ico")"
if [[ "$actual_ico_sizes" != "$expected_ico_sizes" ]]; then
  echo "Windows ICO 尺寸不符合预期：" >&2
  echo "$actual_ico_sizes" >&2
  exit 1
fi

check_brand_palette \
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png'
check_brand_palette \
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png'
check_brand_palette \
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png'
check_brand_palette 'web/icons/Icon-512.png'
check_brand_palette 'windows/runner/resources/app_icon.ico[7]'

echo "应用图标尺寸、格式、透明度和品牌色校验通过"
