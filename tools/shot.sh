#!/bin/zsh
# Quick single screenshot during development. Usage: tools/shot.sh <name> <wait> [launch args...]
D=${SHOT_DEVICE:-60C5DB9D-0CBF-4604-84D7-856AA7A60930}
name=$1; wait=$2; shift 2
mkdir -p build/shots
xcrun simctl install $D build/dd/Build/Products/Release-iphonesimulator/Meridian.app
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null
xcrun simctl launch --console-pty $D dev.meridian.rts "$@" > build/shots/$name.log 2>&1 &
sleep $wait
xcrun simctl io $D screenshot build/shots/$name.png >/dev/null 2>&1
sips -Z 1100 build/shots/$name.png --out build/shots/${name}_s.png >/dev/null
grep -iE "shader|error:" build/shots/$name.log | head -5
echo "shot build/shots/${name}_s.png"
