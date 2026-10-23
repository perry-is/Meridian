#!/bin/zsh
# Matching scene set for environment / building / battle comparisons (Mission 5).
# Usage: tools/world_capture.sh <out-dir> [device-udid]
OUT=${1:?out dir}; [[ "$OUT" = /* ]] || OUT="$PWD/$OUT"; D=${2:-60C5DB9D-0CBF-4604-84D7-856AA7A60930}
APP=build/dd/Build/Products/Release-iphonesimulator/Meridian.app
mkdir -p "$OUT"
xcrun simctl install $D "$APP"
shoot() { # name wait args...
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate $D dev.meridian.rts 2>/dev/null || true
  xcrun simctl launch --console-pty $D dev.meridian.rts "$@" > "$OUT/$name.log" 2>&1 &
  sleep $wait
  T=$(mktemp -d); xcrun simctl io $D screenshot "$T/$name.png" >/dev/null 2>&1; mv "$T/$name.png" "$OUT/$name.png"
  sips -s format jpeg -s formatOptions 80 -Z 1200 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null && rm "$OUT/$name.png"
  echo "captured $name"
}
shoot 01_crossroads_humans 9 -autostart -seed 42 -map crossroads -faction humans -enemy machines -warp 240
shoot 02_riverbend_machines 9 -autostart -seed 42 -map riverbend -faction machines -enemy aliens -warp 240
shoot 03_highlands_aliens 9 -autostart -seed 42 -map highlands -faction aliens -enemy humans -warp 240
shoot 04_midgame_spectate 14 -autostart -spectate -seed 11 -map crossroads -enemy aliens -warp 420
shoot 05_battle50 11 -battle 50
shoot 06_battle200 13 -battle 200
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null || true
