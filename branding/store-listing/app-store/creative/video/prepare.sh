#!/usr/bin/env bash
# Makes the assets of the two video projects from the stills next to this
# folder: the still with the time and the timeline painted over (the video
# draws them itself), and the caption font. Run from the repo root.
set -euo pipefail
c=branding/store-listing/app-store/creative
for p in header search; do mkdir -p "$c/video/$p/assets/fonts"; done
ffmpeg -y -v error -i "$c/header-3840x1646.png" \
  -vf "drawbox=x=1400:y=690:w=1040:h=450:color=black:t=fill" -pix_fmt rgb24 \
  "$c/video/header/assets/bg.png"
ffmpeg -y -v error -i "$c/search-3840x2560.png" \
  -vf "drawbox=x=1400:y=930:w=1040:h=440:color=black:t=fill" -pix_fmt rgb24 \
  "$c/video/search/assets/bg.png"
for p in header search; do
  cp assets/fonts/Montserrat-ExtraBoldItalic.ttf "$c/video/$p/assets/fonts/"
done
echo "assets ready"
