#!/bin/zsh
# Render Tripo models into game sprites, one Blender process per unit (2M-triangle models exhaust memory in batches).
# Usage: tools/render_units.sh h_ranger a_mantis ...
cd "${0:A:h}/.."
B=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
for u in "$@"; do
  $B -b -P tools/blender/unit_render.py -- $u 2>&1 | grep -E "^UNIT|Error|Traceback" || echo "FAILED $u"
done
