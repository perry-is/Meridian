#!/bin/zsh
# Building animation sheets: for each faction, every building (rows) through 6 frames of its idle/working
# animation (columns), captured from the running game. Usage: tools/building_frames.sh <out-dir> [factions...]
OUT=${1:?out}; shift; [[ "$OUT" = /* ]] || OUT="$PWD/$OUT"; mkdir -p "$OUT"
FACTIONS=($@); (( ${#FACTIONS} )) || FACTIONS=(humans machines aliens); D=${SHOT_DEVICE:-60C5DB9D-0CBF-4604-84D7-856AA7A60930}
xcrun simctl install $D build/dd/Build/Products/Release-iphonesimulator/Meridian.app
for F in $FACTIONS; do
  E=machines; [ "$F" = machines ] && E=aliens
  rows=()
  ZOOMS=(0.62 0.42 0.5 0.5 0.5 0.5 0.42 0.42)   # HQ, depot, 4 x 3-tile, tower, forward
  for k in 0 1 2 3 4 5 6 7; do
    xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
    xcrun simctl launch $D dev.meridian.rts -autostart -nosave -seed 42 -map crossroads -faction $F -enemy $E -buildlab $k -zoom ${ZOOMS[$((k+1))]} -tod 0.35 >/dev/null
    sleep 7
    T=$(mktemp -d); xcrun simctl io $D recordVideo --codec h264 --force "$T/v.mp4" >/dev/null 2>&1 &
    REC=$!; sleep 4.4; kill -INT $REC; wait $REC 2>/dev/null
    ffmpeg -loglevel error -y -i "$T/v.mp4" -vf "fps=1.5,crop=iw*0.84:iw*0.84:iw*0.08:ih*0.48-iw*0.42,scale=260:260,tile=6x1" -frames:v 1 "$OUT/${F}_$k.png"
    rows+=("$OUT/${F}_$k.png")
    rm -rf "$T"
  done
  inputs=(); for r in $rows; do inputs+=(-i "$r"); done
  ffmpeg -loglevel error -y $inputs -filter_complex "vstack=inputs=${#rows}" "$OUT/buildings_${F}_frames.png"
  rm -f $rows
  echo "$OUT/buildings_${F}_frames.png"
done
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
