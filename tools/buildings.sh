#!/bin/zsh
# Building review sheets (macOS build). Usage: tools/buildings.sh <out-dir>
OUT=${1:?out}; mkdir -p "$OUT"
xcodebuild -project Meridian.xcodeproj -scheme Meridian -configuration Release -destination "platform=macOS" -derivedDataPath build/ddmac CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD FAILED" | sort -u
APP=$(find build/ddmac -name Meridian.app -maxdepth 5 | head -1)
for f in humans machines aliens; do "$APP/Contents/MacOS/Meridian" --buildings $f "$OUT/b_$f.png"; done
