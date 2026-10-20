#!/bin/zsh
# Stage the reproducible battle and capture it mid-combat.
# Usage: tools/battle_capture.sh <out-dir> <units-per-side> [device-udid] [seconds-of-video]
OUT=${1:?out}; N=${2:-50}; D=${3:-60C5DB9D-0CBF-4604-84D7-856AA7A60930}; SECS=${4:-0}
mkdir -p "$OUT"
xcrun simctl install $D build/dd/Build/Products/Release-iphonesimulator/Meridian.app
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
xcrun simctl launch --console-pty $D dev.meridian.rts -battle $N "${@:5}" > "$OUT/battle$N.log" 2>&1 &
if [ "$SECS" -gt 0 ]; then
  sleep 2
  xcrun simctl io $D recordVideo --codec h264 --force "$OUT/battle$N.mp4" >/dev/null 2>&1 &
  REC=$!
fi
start=$(date +%s)
for t in 5 8 11 14 18; do
  while [ $(( $(date +%s) - start )) -lt $t ]; do sleep 0.2; done
  xcrun simctl io $D screenshot "$OUT/battle${N}_t$t.png" >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 72 -Z 1100 "$OUT/battle${N}_t$t.png" --out "$OUT/battle${N}_t$t.jpg" >/dev/null && rm "$OUT/battle${N}_t$t.png"
done
if [ "$SECS" -gt 0 ]; then
  while [ $(( $(date +%s) - start )) -lt $(( SECS + 2 )) ]; do sleep 0.5; done
  kill -INT $REC; wait $REC 2>/dev/null
fi
sleep 1
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
grep PERF "$OUT/battle$N.log" | head -8
