#!/usr/bin/env bash
# Cuts the App Store preview video out of a recording made by the
# "App preview" workflow (.github/workflows/app-preview.yml):
#
#   gh run download <run id> -n app-preview-recording -D <folder>
#   branding/store-listing/app-store/preview/make-preview.sh <folder>
#
# Writes app-preview-886x1920.mp4 next to this script (or to the path given
# as the second argument) in the form App Store Connect takes: 886x1920,
# 30 fps, H.264 High 4.0, a silent stereo AAC track. Needs ffmpeg.
set -euo pipefail

dir=${1:?usage: make-preview.sh <folder of the downloaded artifact> [output.mp4]}
here=$(cd "$(dirname "$0")" && pwd)
out=${2:-$here/app-preview-886x1920.mp4}
recording=$dir/recording.mov

# Ready stays for LEAD_MS before the tap on START and for TAIL_MS after the
# tap that goes back to the Timer tab. The test holds Ready for 4 s at both
# ends, so neither may be more than about 3000.
LEAD_MS=${LEAD_MS:-1600}
TAIL_MS=${TAIL_MS:-1900}

# The time of a step: "PREVIEW_MARK <step> <ms since 1970>" in marks.txt.
mark() {
  local ms
  ms=$(awk -v step="$1" '$1 == "PREVIEW_MARK" && $2 == step { v = $3 } END { print v }' \
    "$dir/marks.txt" | tr -d '\r')
  if [ -z "$ms" ]; then
    echo "no PREVIEW_MARK $1 in $dir/marks.txt" >&2
    exit 1
  fi
  echo "$ms"
}
seconds() { printf '%d.%03d' $(($1 / 1000)) $(($1 % 1000)); }

# The marks say how long each step took but not where the story is in the
# file. The picture says it. START turns into the red STOP 190 ms after the
# tap (the finger lifts after 90 ms, then the colour changes over 200 ms),
# and the story is the last time it does: the test plays it before, as a
# rehearsal. One pixel of the button's left half per frame, at 30 fps; the
# beep's flash and the tap on STOP pale the red for a moment, which is not
# a new STOP (60 frames without red are).
read -r red_from red_to < <(ffmpeg -hide_banner -loglevel error -i "$recording" \
  -vf 'fps=30:start_time=0,crop=iw*0.15:ih*0.02:iw*0.12:ih*0.812,scale=1:1' \
  -f rawvideo -pix_fmt rgb24 - | od -An -v -tu1 -w3 | awk '
    { red = ($1 > 150 && $2 < 120 && $3 < 120) }
    red && (!seen || NR - seen > 60) { first = NR - 1 }
    red { seen = NR }
    END { print first, seen }')
if [ -z "${red_from:-}" ]; then
  echo "found no STOP button in $recording" >&2
  exit 1
fi
tap_ms=$((red_from * 1000 / 30 - 190))

# STOP is red from the tap on START to the tap on STOP. If the picture has
# it shorter or longer than the script took, the recording has lost frames
# (a simulator that is still busy does that) and is of no use.
red_ms=$(((red_to - red_from) * 1000 / 30))
run_ms=$(($(mark stop) - $(mark start) - 120))
if [ $((red_ms - run_ms)) -gt 700 ] || [ $((run_ms - red_ms)) -gt 700 ]; then
  echo "STOP shows for $(seconds "$red_ms") s, the script ran for" \
    "$(seconds "$run_ms") s: frames are missing, record again" >&2
  exit 1
fi

# From the beep to the tap on STOP the screen changes 20 times a second
# (the clock, then the level line), so the recording has a frame at least
# that often. A longer gap there is a freeze in the video.
clock_from=$((tap_ms + $(mark beep) - $(mark start) + 200))
clock_to=$((tap_ms + $(mark stop) - $(mark start)))
gap_ms=$(ffprobe -v error -select_streams v:0 -show_entries packet=pts_time \
  -of csv=p=0 "$recording" | tr -d '\r,' | sort -n | awk \
  -v from="$(seconds "$clock_from")" -v to="$(seconds "$clock_to")" '
    $1 >= from && $1 <= to { if (seen && $1 - last > gap) gap = $1 - last; last = $1; seen = 1 }
    END { printf "%d", gap * 1000 }')
if [ "$gap_ms" -gt 200 ]; then
  echo "note: the recording skips $gap_ms ms while the clock runs;" \
    "watch that part, and record again if it shows" >&2
fi

from_ms=$((tap_ms - LEAD_MS))
length_ms=$(($(mark timer) - $(mark start) + LEAD_MS + TAIL_MS))
echo "START is tapped at $(seconds "$tap_ms") s of the recording;" \
  "the preview is $(seconds "$length_ms") s from $(seconds "$from_ms") s"
if [ "$length_ms" -lt 15000 ] || [ "$length_ms" -gt 30000 ]; then
  echo "a preview is 15 to 30 s long" >&2
  exit 1
fi
stall=$(awk '$1 == "PREVIEW_WORST_STALL" { v = $2 } END { print v }' "$dir/marks.txt" | tr -d '\r')
if [ -n "$stall" ] && [ "$stall" -gt 200 ]; then
  echo "note: the app stood still for $stall ms at some point of the story;" \
    "look for a stutter, and record again if there is one" >&2
fi

# The simulator's screen is a hair narrower than 886:1920, so it is scaled
# to the width and loses a few rows top and bottom rather than being
# stretched. The recording has frames only where the screen changed, so fps
# fills in the rest before the cut: seeking in the file instead would start
# the video at the next change and lose the still Ready before it. A screen
# this still needs about 1 Mbit/s whatever the target; 10 to 12 is what
# Apple names for footage.
cut="trim=start=$(seconds "$from_ms"):duration=$(seconds "$length_ms"),setpts=PTS-STARTPTS"
ffmpeg -hide_banner -loglevel warning -y \
  -i "$recording" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -t "$(seconds "$length_ms")" \
  -map 0:v:0 -map 1:a:0 \
  -vf "fps=30:start_time=0,$cut,scale=886:-2:flags=lanczos,crop=886:1920,setsar=1,format=yuv420p" \
  -c:v libx264 -profile:v high -level:v 4.0 -preset slow \
  -b:v 10M -maxrate 12M -bufsize 24M -g 30 \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a aac -b:a 256k -ar 48000 -ac 2 \
  -movflags +faststart "$out"

ffprobe -v error -show_entries \
  format=duration,size,bit_rate:stream=codec_name,profile,level,width,height,r_frame_rate,pix_fmt,sample_rate,channels \
  -of default=noprint_wrappers=1 "$out"
