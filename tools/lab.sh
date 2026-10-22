#!/bin/zsh
# Unit animation lab capture. Usage: tools/lab.sh <out-prefix> <faction> [zoom] [seconds]
OUT=${1:?out}; F=${2:-humans}; Z=${3:-0.8}; SECS=${4:-6}; D=${LAB_DEVICE:-60C5DB9D-0CBF-4604-84D7-856AA7A60930}
E=machines; [ "$F" = machines ] && E=aliens
xcrun simctl install $D build/dd/Build/Products/Release-iphonesimulator/Meridian.app
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
xcrun simctl launch $D dev.meridian.rts -autostart -seed 42 -map crossroads -faction $F -enemy $E -lab -zoom $Z -tod 0.1 >/dev/null
sleep 4
xcrun simctl io $D recordVideo --codec h264 --force "$OUT.mp4" >/dev/null 2>&1 &
REC=$!; sleep $SECS; kill -INT $REC; wait $REC 2>/dev/null
ffmpeg -loglevel error -y -i "$OUT.mp4" -frames:v 1 -vf "fps=4,crop=iw:ih*0.42:0:ih*0.29,scale=400:-1,tile=5x4" "$OUT.jpg"
echo "$OUT.jpg"
