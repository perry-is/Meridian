#!/bin/zsh
# Reproducible screenshot set for visual comparison.
# Usage: tools/capture.sh <out-dir> [device-udid]
set -e
OUT=${1:?out dir}; [[ "$OUT" = /* ]] || OUT="$PWD/$OUT"; D=${2:-60C5DB9D-0CBF-4604-84D7-856AA7A60930}
APP=build/dd/Build/Products/Release-iphonesimulator/Meridian.app
mkdir -p "$OUT"
xcrun simctl install $D "$APP"
shoot() { # name wait args...
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate $D dev.meridian.rts 2>/dev/null || true
  xcrun simctl launch $D dev.meridian.rts "$@" >/dev/null
  sleep $wait
  xcrun simctl io $D screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "captured $name"
}
shoot 01_menu 4
shoot 02_base_start 7 -autostart -seed 42 -faction humans -enemy machines
shoot 03_base_aliens 9 -autostart -seed 42 -faction aliens -enemy humans -warp 200
shoot 04_battle 14 -autostart -spectate -seed 11 -enemy aliens -warp 380
shoot 05_battle_machines 14 -autostart -spectate -seed 7 -faction machines -enemy humans -warp 520
shoot 06_stress 16 -autostart -spectate -stress 200 -faction humans -enemy aliens
xcrun simctl terminate $D dev.meridian.rts 2>/dev/null || true
xcrun simctl launch $D dev.meridian.rts >/dev/null
