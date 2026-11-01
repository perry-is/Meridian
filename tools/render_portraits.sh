#!/bin/zsh
# Render live 3D portraits for rigged units (art/rigged/<id>.fbx), one Blender process per unit.
# Usage: tools/render_portraits.sh h_ghost a_mantis ...      (no arguments: every rigged unit)
cd "${0:A:h}/.."
B=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
ids=("$@"); [[ ${#ids} -eq 0 ]] && ids=(art/rigged/*.fbx(:t:r))
for u in $ids; do
  $B -b -P tools/blender/portraits.py -- $u 2>&1 | grep -E "^PORTRAIT|Error|Traceback" || echo "FAILED $u"
done
