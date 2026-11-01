# Converts a Tripo auto-rigged humanoid (VRM-style J_Bip_* skeleton) into a Mixamo-named rig, so the motion-capture
# clips in art/anims retarget onto it like every other soldier.
#
# Usage: Blender -b -P tools/blender/vrm_to_mixamo.py -- art/tripo/<id>.glb
# Writes art/rigged/<id>.fbx (mesh, skeleton and embedded textures).
import bpy, sys, os

src = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
uid = os.path.splitext(os.path.basename(src))[0]

NAMES = {"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head"}
for s, side in (("L", "Left"), ("R", "Right")):
    NAMES.update({f"{s}_Shoulder": f"{side}Shoulder", f"{s}_UpperArm": f"{side}Arm", f"{s}_LowerArm": f"{side}ForeArm",
                  f"{s}_Hand": f"{side}Hand", f"{s}_UpperLeg": f"{side}UpLeg", f"{s}_LowerLeg": f"{side}Leg",
                  f"{s}_Foot": f"{side}Foot", f"{s}_ToeBase": f"{side}ToeBase"})

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
skin = [o for o in bpy.data.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
for o in list(bpy.data.objects):
    if o.type == "MESH" and o not in skin: bpy.data.objects.remove(o)     # Tripo's helper sphere
renamed = 0
for b in arm.data.bones:
    key = b.name.removeprefix("J_Bip_C_").removeprefix("J_Bip_")
    if b.name.startswith("J_Bip_") and key in NAMES:
        b.name = "mixamorig:" + NAMES[key]; renamed += 1                # vertex groups follow the rename
assert "mixamorig:Hips" in arm.data.bones, "not a VRM humanoid skeleton"
os.makedirs(os.path.join(ROOT, "art/rigged"), exist_ok=True)
out = os.path.join(ROOT, f"art/rigged/{uid}.fbx")
bpy.ops.export_scene.fbx(filepath=out, use_selection=False, object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                         bake_anim=False, path_mode="COPY", embed_textures=True)
print("RIG", uid, "bones renamed", renamed, "->", out)
