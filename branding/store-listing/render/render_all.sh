#!/usr/bin/env bash
# Renders the real app for the store screenshots, in every app language:
# eight screens from store_shots_test.dart and the video editor from
# editor_shot_test.dart, into branding/store-listing/renders/<platform>/<lang>/.
# Run from the repo root (Git Bash on Windows):
#
#   branding/store-listing/render/render_all.sh <clip.mp4> [lang ...]
#   PLATFORM=android AT_MS=15060 ZOOM=1 \
#     branding/store-listing/render/render_all.sh <clip.mp4> [lang ...]
#
# PLATFORM is ios (the default; iPhone size, the text in Segoe UI) or android
# (Android phone size, Roboto). The clip is a range video without faces; it
# stays out of the repo. AT_MS, ZOOM and SCROLL choose the editor's moment:
# the defaults are the App Store's (a frame without a weapon).
set -euo pipefail
clip="$1"; shift
langs=("$@"); [ ${#langs[@]} -gt 0 ] || langs=(en de es fi fr pl pt ru)
platform="${PLATFORM:-ios}"
at_ms="${AT_MS:-3680}"; zoom="${ZOOM:-0.42}"; scroll="${SCROLL:-186}"
dir=branding/store-listing/render
out="$PWD/branding/store-listing/renders/$platform"
font="Segoe UI"; [ "$platform" = ios ] || font=Roboto
python "$dir/render_font.py" on "$font"
trap 'python "$dir/render_font.py" off' EXIT
for lang in "${langs[@]}"; do
  echo "== $lang"
  flutter test "$dir/store_shots_test.dart" \
    --dart-define=PLATFORM="$platform" --dart-define=LOCALE="$lang" \
    --dart-define=OUT="$out/$lang" | grep -E "passed|failed|wrote" || true
  flutter test "$dir/editor_shot_test.dart" \
    --dart-define=PLATFORM="$platform" --dart-define=CLIP="$clip" \
    --dart-define=AT_MS="$at_ms" --dart-define=ZOOM="$zoom" \
    --dart-define=SCROLL="$scroll" --dart-define=LOCALE="$lang" \
    --dart-define=OUT="$out/$lang/video.png" | grep -E "passed|failed|wrote" || true
done
