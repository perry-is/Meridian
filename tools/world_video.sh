#!/bin/zsh
# Records the Mission 5 world showcase clips and joins them. Usage: tools/world_video.sh <out.mp4>
OUT=${1:?out}; D=${2:-60C5DB9D-0CBF-4604-84D7-856AA7A60930}
TMP=build/shots/vid; rm -rf $TMP; mkdir -p $TMP
xcrun simctl install $D build/dd/Build/Products/Release-iphonesimulator/Meridian.app
clip() { # name warmup seconds args...
  local name=$1 warm=$2 secs=$3; shift 3
  xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
  xcrun simctl launch $D dev.meridian.rts "$@" >/dev/null
  sleep $warm
  xcrun simctl io $D recordVideo --codec h264 --force $TMP/$name.mp4 >/dev/null 2>&1 &
  local rec=$!; sleep $secs; kill -INT $rec; wait $rec 2>/dev/null
  ffmpeg -loglevel error -y -i $TMP/$name.mp4 -vf "scale=540:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -an $TMP/n_$name.mp4
  echo "file 'n_$name.mp4'" >> $TMP/list.txt
}
clip 1_delta 3 9 -autostart -seed 42 -map riverbend -faction machines -enemy aliens -zoom 1.0
clip 2_meadow_night 12 9 -autostart -spectate -seed 5 -map crossroads -faction humans -enemy machines -warp 330 -camhq 0 -zoom 1.1 -tod 0.5
clip 3_lattice 12 7 -autostart -spectate -seed 5 -map riverbend -faction machines -enemy humans -warp 300 -camhq 0 -zoom 0.9 -tod 0.2
clip 4_brood 12 7 -autostart -spectate -seed 5 -map highlands -faction aliens -enemy humans -warp 300 -camhq 0 -zoom 0.9 -tod 0.12
clip 5_plateau 14 9 -autostart -spectate -seed 11 -map highlands -faction machines -enemy aliens -warp 600
clip 6_battle 4 14 -battle 100
(cd $TMP && ffmpeg -loglevel error -y -f concat -safe 0 -i list.txt -c copy ../world_demo.mp4)
cp build/shots/world_demo.mp4 "$OUT"
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
ls -la "$OUT"
