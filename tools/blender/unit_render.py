# Renders a Tripo unit model into Meridian sprites: 8 facings x 6 poses, each with a team-colour mask.
#
# Usage: Blender -b -P tools/blender/unit_render.py -- <unit_id>      (or tools/render_units.sh id ...)
# Reads  art/tripo/<unit_id>.glb, tools/blender/unit_fixes.json and the unit's size/domain from MeridianCore.
# Writes Meridian/Units3D/u3d_<id>_d<k>_<p>.png and ..._<p>m.png (mask), k = facing 0..7, p = pose 0..5.
#
# Facing k points along screen angle k*45° (0 = screen right, counter-clockwise), measured on the ground plane,
# matching Iso in GameController.swift. Canvas and anchor match UnitArt.canvasSize and GameScene.
#
# Poses: 0 idle, 1-4 walk (or wing-beat) cycle, 5 attack. Tripo models come unrigged, so poses are made by
# procedural skinning: body regions (legs, arms, wings) are found from the model's proportions and rotated about
# estimated joints with smooth weights. Rigs: biped, multiped (any number of legs), flyer (wings), hover.
#
# Soldiers with a skinned model in art/rigged/<id>.fbx (Mixamo skeleton) are posed with real motion-capture clips
# from art/anims instead, retargeted bone by bone, and also get death frames: poses 6-8.
import bpy, sys, os, math, json
import numpy as np
from mathutils import Vector, Matrix, Euler, Quaternion

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ids = sys.argv[sys.argv.index("--") + 1:]
FIX = json.load(open(os.path.join(ROOT, "tools/blender/unit_fixes.json")))
UNITS = {}
for f in ("humans", "machines", "aliens"):
    for u in json.load(open(os.path.join(ROOT, f"MeridianCore/Sources/MeridianCore/Data/units_{f}.json"))):
        UNITS[u["id"]] = u
OUT = os.path.join(ROOT, "Meridian/Units3D")
os.makedirs(OUT, exist_ok=True)

PX_PER_UNIT = 32 * math.sqrt(2)        # screen points per world unit along the ground (Iso.hw * √2)
ELEV = math.radians(30)                  # 2:1 isometric: ground depth is squashed by sin(30°) = 0.5
SCALE = 2                                # pixels per point
POSES = 6
DEATH_POSES = 3
# Which clip and point in it (0..1) each pose samples, for rigged soldiers. unit_fixes.json can override "clips".
CLIPS = {"idle": ("rifle_idle", 0.0), "walk": ("rifle_walk", 0.0), "attack": ("firing_rifle", 0.25),
         "death": ("death_front", (0.25, 0.5, 1.0))}
TARGET_TRIS = 120_000                    # plenty for a ~100px sprite, and fast to deform and render
R = Vector((1, 1, 0)).normalized()       # screen right on the ground
U = Vector((-1, 1, 0)).normalized()      # screen up on the ground (away from the viewer)

def canvas(u):
    return 26 + u.get("radius", 0.4) * 68   # UnitArt.canvasSize

def rig_of(uid, u):
    if "rig" in FIX.get(uid, {}): return FIX[uid]["rig"]
    if u["faction"] == "humans": return "biped"
    return "flyer" if u.get("domain") == "air" else "multiped"

# ---------------------------------------------------------------- procedural skinning
def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def rot_x(P, pivot, ang, w):
    """Rotate points about the lateral (X) axis through pivot, blended by weight w. +ang swings -Y (forward) up."""
    y, z = P[:, 1] - pivot[1], P[:, 2] - pivot[2]
    c, s = math.cos(ang), math.sin(ang)
    Q = P.copy(); Q[:, 1] = pivot[1] + y * c - z * s; Q[:, 2] = pivot[2] + y * s + z * c
    return P + (Q - P) * w[:, None]

def rot_y(P, pivot, ang, w):
    """Rotate points about the forward (Y) axis through pivot (for wings), blended by w."""
    x, z = P[:, 0] - pivot[0], P[:, 2] - pivot[2]
    c, s = math.cos(ang), math.sin(ang)
    Q = P.copy(); Q[:, 0] = pivot[0] + x * c - z * s; Q[:, 2] = pivot[2] + x * s + z * c
    return P + (Q - P) * w[:, None]

def pose_biped(P0, pose, H, knee=1.0, arms=1.0, arm_x=(0.12, 0.2)):
    """Humanoid: legs swing from the hips, knees bend on the passing step, arms counter-swing; attack aims forward.
    Forward is -Y. Positive X-rotation moves a hanging limb's end towards +Y (back)."""
    P = P0.copy(); x, z = P0[:, 0], P0[:, 2]
    hipZ, kneeZ, shZ = 0.50 * H, 0.27 * H, 0.78 * H
    right = smooth(-0.03 * H, 0.03 * H, x); left = 1 - right
    leg = 1 - smooth(0.44 * H, 0.54 * H, z)
    # Only what hangs under the hips is leg: tails and blades trailing behind or ahead stay with the body.
    feet = P0[z < 0.08 * H]
    fy = float(np.median(feet[:, 1])) if len(feet) else 0.0
    leg = leg * (1 - smooth(0.16 * H, 0.28 * H, np.abs(P0[:, 1] - fy)))
    shin = 1 - smooth(kneeZ - 0.04 * H, kneeZ + 0.04 * H, z)
    arm = smooth(arm_x[0] * H, arm_x[1] * H, np.abs(x)) * smooth(0.45 * H, 0.58 * H, z)
    if pose in (1, 2, 3, 4):
        ph = (pose - 1) / 4 * 2 * math.pi
        swing = math.radians(24) * math.cos(ph)              # right leg forward at ph=0
        bendR = math.radians(40) * knee * max(0, math.sin(ph)); bendL = math.radians(40) * knee * max(0, -math.sin(ph))
        for w, sgn, bend in ((right, 1, bendR), (left, -1, bendL)):
            # Knee first (child), then the whole leg from the hip; the arm on this side swings the other way.
            P = rot_x(P, (0, 0, kneeZ), bend, w * leg * shin)
            P = rot_x(P, (0, 0, hipZ), -swing * sgn, w * leg)
            P = rot_x(P, (0, 0, shZ), swing * sgn * 0.7 * arms, w * arm)
        P[:, 2] += 0.018 * H * abs(math.cos(ph))
    elif pose == 5:
        P = rot_x(P, (0, 0, shZ), math.radians(-15), arm)      # thrust the arms forward (strike / recoil brace)
        P = rot_x(P, (0, 0, 0), math.radians(-7), 1 - leg * 0.9)   # lean into it
    return P

def pose_multiped(P0, pose, dims):
    """Any number of legs: feet step in a trot (diagonal pairs together), lifting as they swing forward.
    Attack rears the front up and lunges."""
    W, D, H = dims
    P = P0.copy(); x, y, z = P0[:, 0], P0[:, 1], P0[:, 2]
    leg = 1 - smooth(0.12 * H, 0.5 * H, z)                     # 1 at the ground, fading into the body
    side = smooth(-0.04 * W, 0.04 * W, x) * 2 - 1              # -1 left .. +1 right
    front = smooth(-0.06 * D, 0.06 * D, -y) * 2 - 1            # +1 towards the head (-Y)
    if pose in (1, 2, 3, 4):
        ph = (pose - 1) / 4 * 2 * math.pi
        a = side * front                                       # +1 front-right/back-left, -1 the other pair
        stride, lift = 0.10 * max(D, H), 0.08 * H
        P[:, 1] += -stride * np.cos(ph) * a * leg
        P[:, 2] += lift * np.maximum(0, math.sin(ph) * a) * leg
        P[:, 2] += 0.012 * H * abs(math.cos(2 * ph))
    elif pose == 5:
        body = 1 - leg * 0.6
        P = rot_x(P, (0, D * 0.3, 0.3 * H), math.radians(-14), body * smooth(-0.2 * D, 0.3 * D, -y))
        P[:, 1] -= 0.06 * D
    return P

def pose_flyer(P0, pose, dims):
    """Wings beat about the body's long axis; attack dips the nose."""
    W, D, H = dims
    P = P0.copy(); x = P0[:, 0]
    zc = float(np.median(P0[:, 2]))
    body = 0.12 * W
    wingR = smooth(body, body * 1.8, x); wingL = smooth(body, body * 1.8, -x)
    if pose in (1, 2, 3, 4):
        c = math.cos((pose - 1) / 4 * 2 * math.pi)
        ang = math.radians(40) * c
        P = rot_y(P, (body, 0, zc), ang, wingR)
        P = rot_y(P, (-body, 0, zc), -ang, wingL)
        P[:, 2] -= 0.03 * H * c
    elif pose == 5:
        P = rot_x(P, (0, 0, zc), math.radians(14), np.ones(len(P)))
    return P

def pose_hover(P0, pose, dims):
    """Floating creature: gentle bob and dangling parts swaying; attack pulses."""
    W, D, H = dims
    P = P0.copy(); z = P0[:, 2]
    low = 1 - smooth(0.1 * H, 0.45 * H, z)
    if pose in (1, 2, 3, 4):
        ph = (pose - 1) / 4 * 2 * math.pi
        P[:, 2] += 0.04 * H * math.sin(ph)
        P[:, 1] += 0.10 * D * math.cos(ph) * low
        P[:, 2] += 0.04 * H * math.sin(ph + 1.2) * low
    elif pose == 5:
        c = P0.mean(axis=0); P = c + (P0 - c) * np.array([1.06, 1.06, 0.95])
    return P

def pose_vehicle(P0, pose, dims):
    """Wheeled/tracked: the hull bobs and pitches over the ground as it drives; firing rocks it back."""
    W, D, H = dims
    P = P0.copy(); one = np.ones(len(P))
    if pose in (1, 2, 3, 4):
        ph = (pose - 1) / 4 * 2 * math.pi
        P = rot_x(P, (0, 0, 0), math.radians(1.6) * math.sin(ph), one)
        P[:, 2] += 0.012 * H * (1 + math.cos(2 * ph))
    elif pose == 5:
        P = rot_x(P, (0, D * 0.4, 0), math.radians(3.5), one)
        P[:, 1] += 0.03 * D
    return P

def pose_aircraft(P0, pose, dims):
    """Aircraft and drones: banking sway and bob in flight; the nose dips to attack."""
    W, D, H = dims
    P = P0.copy(); one = np.ones(len(P)); zc = float(np.median(P0[:, 2]))
    if pose in (1, 2, 3, 4):
        ph = (pose - 1) / 4 * 2 * math.pi
        P = rot_y(P, (0, 0, zc), math.radians(5) * math.sin(ph), one)
        P[:, 2] += 0.03 * max(W, D) * math.sin(ph + 0.8)
    elif pose == 5:
        P = rot_x(P, (0, 0, zc), math.radians(10), one)
    return P

# ---------------------------------------------------------------- motion capture
class Retarget:
    """Plays Mixamo clips on any Mixamo-named skeleton: each bone copies the clip's world rotation, corrected for the
    difference between the two rest poses; the hips also copy translation, scaled by hip height."""
    def __init__(self, tgt):
        tgt.animation_data_clear()      # Mixamo downloads carry their own take, which would override the pose at render
        self.tgt = tgt; self.src = {}
    def clip(self, name):
        if name not in self.src:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, f"art/anims/{name}.fbx"))
            new = [o for o in bpy.data.objects if o not in before]
            src = next(o for o in new if o.type == "ARMATURE")
            for o in new:
                if o is not src: bpy.data.objects.remove(o)
            src.hide_render = True
            tgt = self.tgt
            wr = lambda o, b: (o.matrix_world @ b.matrix_local).to_quaternion()
            names = [b.name for b in tgt.data.bones if b.name in src.data.bones]   # hierarchical: parents first
            hip = "mixamorig:Hips"
            hs, ht = src.matrix_world @ src.data.bones[hip].head_local, tgt.matrix_world @ tgt.data.bones[hip].head_local
            self.src[name] = dict(arm=src, names=names, hs=hs, ht=ht, k=ht.z / max(hs.z, 1e-6),
                                  rs={n: wr(src, src.data.bones[n]) for n in names}, rt={n: wr(tgt, tgt.data.bones[n]) for n in names},
                                  range=[int(x) for x in src.animation_data.action.frame_range])
        return self.src[name]
    def apply(self, name, t, still_hips=False):
        c = self.clip(name); src, tgt = c["arm"], self.tgt
        f0, f1 = c["range"]
        bpy.context.scene.frame_set(int(round(f0 + (f1 - f0) * t)))
        for n in c["names"]:
            ps, pt = src.pose.bones[n], tgt.pose.bones[n]
            sm = src.matrix_world @ ps.matrix
            q = sm.to_quaternion() @ c["rs"][n].inverted() @ c["rt"][n]
            bpy.context.view_layer.update()
            head = (tgt.matrix_world @ pt.matrix).translation
            if n == "mixamorig:Hips":
                d = (sm.translation - c["hs"]) * c["k"]
                if still_hips: d.x = d.y = 0
                head = c["ht"] + d
            # Back into armature space without its scale (Mixamo exports are in centimetres, scaled 0.01).
            mw = tgt.matrix_world
            pt.matrix = Matrix.Translation(mw.inverted() @ head) @ (mw.to_quaternion().inverted() @ q).to_matrix().to_4x4()
        bpy.context.view_layer.update()

# ---------------------------------------------------------------- materials
def hsv_mask(nt, color, hue_lo=(0.52, 0.56)):
    """0..1 where the albedo is the saturated blue team marker. hue_lo is where the ramp up from cyan starts and ends."""
    sep = nt.nodes.new("ShaderNodeSeparateColor"); sep.mode = "HSV"
    nt.links.new(color, sep.inputs[0])
    def mr(v, a, b):
        n = nt.nodes.new("ShaderNodeMapRange"); n.clamp = True
        nt.links.new(v, n.inputs["Value"])
        n.inputs["From Min"].default_value, n.inputs["From Max"].default_value = a, b
        return n.outputs["Result"]
    def mul(a, b):
        n = nt.nodes.new("ShaderNodeMath"); n.operation = "MULTIPLY"
        nt.links.new(a, n.inputs[0]); nt.links.new(b, n.inputs[1]); return n.outputs[0]
    hue = sep.outputs[0]
    return mul(mul(mr(hue, *hue_lo), mr(hue, 0.72, 0.68)), mul(mr(sep.outputs[1], 0.35, 0.55), mr(sep.outputs[2], 0.08, 0.18)))

def prepare_materials(meshes, fix):
    """Optionally recolour all-blue models to Brood chitin; build mask materials. Returns {name: (lit, mask)}."""
    recolor = fix.get("recolor", False)
    mask_strength = fix.get("mask", 0.35 if recolor else 1.0)
    pairs = {}
    for o in meshes:
        for m in o.data.materials:
            if not m or m.name in pairs: continue
            nt = m.node_tree
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            links = bsdf.inputs["Base Color"].links
            src = links[0].from_socket if links else None
            # The mask copy is taken before recolouring so it still sees the original blue.
            mm = m.copy(); mm.name = m.name + "_mask"; mt = mm.node_tree
            em = mt.nodes.new("ShaderNodeEmission")
            if "team" in m.keys():
                em.inputs["Color"].default_value = (1, 1, 1, 1) if m["team"] else (0, 0, 0, 1)
            elif src is not None:
                msrc = mt.nodes[src.node.name].outputs[list(src.node.outputs).index(src)]
                k = mt.nodes.new("ShaderNodeMath"); k.operation = "MULTIPLY"; k.inputs[1].default_value = mask_strength
                mt.links.new(hsv_mask(mt, msrc, fix.get("hue_lo", (0.52, 0.56))), k.inputs[0]); mt.links.new(k.outputs[0], em.inputs["Color"])
            else:
                em.inputs["Color"].default_value = (0, 0, 0, 1)
            out = next(n for n in mt.nodes if n.type == "OUTPUT_MATERIAL")
            mt.links.new(em.outputs[0], out.inputs["Surface"])
            if recolor and src is not None:
                hsv = nt.nodes.new("ShaderNodeHueSaturation")
                hsv.inputs["Hue"].default_value = 0.78; hsv.inputs["Saturation"].default_value = 0.55
                hsv.inputs["Value"].default_value = 0.4
                nt.links.new(src, hsv.inputs["Color"])
                mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
                ins = {s.identifier: s for s in mix.inputs}
                nt.links.new(hsv_mask(nt, src), ins["Factor_Float"])
                nt.links.new(src, ins["A_Color"]); nt.links.new(hsv.outputs[0], ins["B_Color"])
                nt.links.new({s.identifier: s for s in mix.outputs}["Result_Color"], bsdf.inputs["Base Color"])
            pairs[m.name] = (m, mm)
    return pairs

# ---------------------------------------------------------------- scene
def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"; prefs.get_devices()
    for d in prefs.devices: d.use = True
    sc.cycles.device = "GPU"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    return sc

def rig_path(uid):
    f = os.path.join(ROOT, f"art/rigged/{uid}.fbx")
    return f if os.path.exists(f) else None

def is_humanoid(path):
    """Mixamo-named skeletons take motion capture; FBX stores bone names as plain strings."""
    with open(path, "rb") as f: return b"mixamorig:Hips" in f.read()

def render_unit(uid, poses=None, facings=range(8), out_dir=OUT):
    u = UNITS[uid]; fix = FIX.get(uid, {})
    air = u.get("domain") == "air"
    rig = rig_of(uid, u)
    sc = setup_scene()
    rig_fbx = rig_path(uid)
    if rig_fbx and is_humanoid(rig_fbx):
        return render_rigged(uid, u, fix, sc, rig_fbx, poses or range(POSES + DEATH_POSES), facings, out_dir)
    if rig_fbx:
        return render_creature(uid, u, fix, sc, rig_fbx, poses or range(POSES), facings, out_dir)
    poses = poses or range(POSES)
    if fix.get("source") == "proc":
        sys.path.insert(0, os.path.dirname(__file__))
        import units_proc
        units_proc.build(uid)
        meshes = [o for o in sc.objects if o.type == "MESH"]
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes: o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.convert(target="MESH")          # apply bevels and subdivision
    else:
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, f"art/tripo/{uid}.glb"))
        meshes = [o for o in sc.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1: bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    mw = obj.matrix_world.copy()
    obj.parent = None
    for o in list(sc.objects):
        if o is not obj: bpy.data.objects.remove(o)
    # Bake the world transform and fix-up rotation into the mesh; forward = -Y; bottom-centre (ground) or
    # centre (air) at the origin.
    fixm = Euler([math.radians(a) for a in fix.get("rotate", [0, 0, 0])]).to_matrix().to_4x4()
    fwd = Vector(fix.get("forward", [0, -1, 0]))
    yaw = Matrix.Rotation(math.atan2(-fwd.x, -fwd.y), 4, "Z")
    obj.data.transform(yaw @ fixm @ mw); obj.matrix_world = Matrix.Identity(4)
    n = len(obj.data.vertices)
    P = np.empty(n * 3, dtype=np.float32); obj.data.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    lo, hi = P.min(axis=0), P.max(axis=0)
    base = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, float(lo[2]) if not air else (lo[2] + hi[2]) / 2)
    obj.data.transform(Matrix.Translation(-Vector(base)))
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > TARGET_TRIS * 1.3:
        dm = obj.modifiers.new("dec", "DECIMATE"); dm.ratio = TARGET_TRIS / tris
        bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.shade_smooth()
    n = len(obj.data.vertices)
    P0 = np.empty(n * 3, dtype=np.float32); obj.data.vertices.foreach_get("co", P0); P0 = P0.reshape(-1, 3).astype(np.float64)
    lo, hi = P0.min(axis=0), P0.max(axis=0); dims = tuple(float(v) for v in (hi - lo))
    W, D, H = dims
    zoff = -float(lo[2])                      # skinning heights are measured from the model's bottom

    C = canvas(u); ortho = C / PX_PER_UNIT
    k = ortho * fix.get("fill", 0.72) / max(dims)
    holder = bpy.data.objects.new("holder", None); sc.collection.objects.link(holder)
    obj.parent = holder; holder.scale = (k, k, k)
    stage(sc, C, air)

    def set_pose(p):
        Q = P0.copy(); Q[:, 2] += zoff
        if rig == "biped": Q = pose_biped(Q, p, H, fix.get("knee", 1.0), fix.get("arms", 1.0), tuple(fix.get("arm_x", (0.12, 0.2))))
        elif rig == "multiped": Q = pose_multiped(Q, p, dims)
        elif rig == "flyer": Q = pose_flyer(Q, p, dims)
        elif rig == "hover": Q = pose_hover(Q, p, dims)
        elif rig == "vehicle": Q = pose_vehicle(Q, p, dims)
        elif rig == "aircraft": Q = pose_aircraft(Q, p, dims)
        Q[:, 2] -= zoff
        obj.data.vertices.foreach_set("co", Q.astype(np.float32).ravel())
        obj.data.update()

    shoot(sc, uid, obj, holder, fix, poses, facings, set_pose, out_dir)
    print("UNIT", uid, rig, "canvas", C, "verts", n)

def humanoid_yaw(arm):
    """Turn (about Z) that faces a Mixamo-skeleton character along -Y, judged from which side its left hip is on:
    Tripo doesn't always export humanoids facing the same way."""
    M = arm.matrix_world
    side = M @ arm.data.bones["mixamorig:LeftUpLeg"].head_local - M @ arm.data.bones["mixamorig:RightUpLeg"].head_local
    f = side.cross(Vector((0, 0, 1)))
    return math.atan2(-f.x, -f.y) if f.length > 1e-6 else 0.0

def render_rigged(uid, u, fix, sc, path, poses, facings, out_dir):
    """A skinned Mixamo-skeleton soldier, posed from motion-capture clips."""
    bpy.ops.import_scene.fbx(filepath=path)
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    obj = next(o for o in sc.objects if o.type == "MESH")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    rt = Retarget(arm)
    clips = {**CLIPS, **{k: tuple(v) for k, v in fix.get("clips", {}).items()}}
    frames = [clips["idle"]] + [(clips["walk"][0], clips["walk"][1] + i / 4) for i in range(4)] + [clips["attack"]] + \
             [(clips["death"][0], t) for t in clips["death"][1]]
    for c, _ in frames: rt.clip(c)                   # load every clip while the rig is still at the origin

    def world_verts():
        ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        M = np.array(obj.matrix_world)
        P = np.empty(len(ev.data.vertices) * 3); ev.data.vertices.foreach_get("co", P)
        P = P.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        return P
    rt.apply(*clips["idle"])
    turn_z = humanoid_yaw(arm)
    P = world_verts(); lo, hi = P.min(axis=0), P.max(axis=0)
    dims = tuple(float(v) for v in (hi - lo))
    base = Vector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]))
    C = canvas(u); ortho = C / PX_PER_UNIT
    k = ortho * fix.get("fill", 0.72) / max(dims)
    holder = bpy.data.objects.new("holder", None); sc.collection.objects.link(holder)
    turn = bpy.data.objects.new("turn", None); sc.collection.objects.link(turn)
    off = bpy.data.objects.new("off", None); sc.collection.objects.link(off)
    turn.parent = holder; off.parent = turn; arm.parent = off
    stage(sc, C, False)

    def set_pose(p):
        # Retargeting works in world space, so pose with the rig back at the origin, then restore the framing.
        rot = holder.rotation_euler.copy()
        holder.rotation_euler = (0, 0, 0); holder.scale = (1, 1, 1); off.location = (0, 0, 0); turn.rotation_euler = (0, 0, 0)
        bpy.context.view_layer.update()
        rt.apply(*frames[p])
        if p >= POSES:
            # Fall where it stands: keep half the body's drift so the corpse stays centred on its tile.
            hips = arm.matrix_world @ arm.pose.bones["mixamorig:Hips"].head
            drift = hips - (arm.matrix_world @ arm.data.bones["mixamorig:Hips"].head_local)
            off.location = (-drift.x * 0.5, -drift.y * 0.5, 0)
        off.location = Vector(off.location) - base
        holder.rotation_euler = rot; holder.scale = (k, k, k); turn.rotation_euler = (0, 0, turn_z)
        bpy.context.view_layer.update()

    shoot(sc, uid, obj, holder, fix, poses, facings, set_pose, out_dir)
    print("UNIT", uid, "mocap", "canvas", C, "verts", len(obj.data.vertices))

# ---------------------------------------------------------------- skeletal creatures
def side_of(name):
    return 1 if name.endswith(".R") or ".R." in name else -1 if name.endswith(".L") or ".L." in name else 0

def creature_pose(arm, p, kind, F, Up, Lat, amp):
    """Poses a creature skeleton by bone name. Rotations are given about armature-space axes (F forward, Up, Lat
    lateral = F x Up) and applied in each bone's rest frame, so a knee bends about the leg's own swing axis."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
    rot = {}
    def add(name, axis, deg):
        if name in arm.pose.bones and deg:
            rot[name] = Quaternion(axis, math.radians(deg * amp)) @ rot.get(name, Quaternion())
    walking = 1 <= p <= 4
    ph = (p - 1) / 4 * 2 * math.pi if walking else 0.0
    c, s_ = math.cos(ph), math.sin(ph)
    # Swinging a limb "forward" is a rotation about the lateral axis that carries a hanging foot towards F.
    fwd = 1 if (Quaternion(Lat, 0.3) @ (-Up)).dot(F) > 0 else -1
    tails = [b.name for b in arm.pose.bones if b.name.startswith("tail") or b.name.startswith("abdomen")]
    if kind == "biped":
        if walking:
            for sd in (1, -1):
                sw = 24 * c * sd
                add(f"thigh.{'R' if sd > 0 else 'L'}", Lat, fwd * sw)
                add(f"shin.{'R' if sd > 0 else 'L'}", Lat, -fwd * 38 * max(0, s_ * sd))
                add(f"upper_arm.{'R' if sd > 0 else 'L'}", Lat, -fwd * sw * 0.8)
                add(f"forearm.{'R' if sd > 0 else 'L'}", Lat, fwd * 12)
            add("chest", Up, 6 * c)
            for i, t in enumerate(tails): add(t, Up, 10 * s_ * (i + 1) / len(tails))
        elif p == 5:
            add("chest", Lat, fwd * 14); add("spine", Lat, fwd * 6); add("head", Lat, fwd * 8)
            for sd in "LR":
                add(f"upper_arm.{sd}", Lat, fwd * 70); add(f"forearm.{sd}", Lat, fwd * 35)
            for i, t in enumerate(tails): add(t, Lat, -fwd * 12)
    elif kind == "quadruped":
        if walking:
            for nm, sd, front in (("fore", 1, 1), ("fore", -1, 1), ("hind", 1, -1), ("hind", -1, -1)):
                a = sd * front                                  # diagonal pairs move together (trot)
                sfx = "R" if sd > 0 else "L"
                add(f"{nm}_upper.{sfx}", Lat, fwd * 22 * c * a)
                add(f"{nm}_lower.{sfx}", Lat, -fwd * front * 30 * max(0, s_ * a))
                add(f"{nm}_paw.{sfx}", Lat, fwd * front * 15 * max(0, s_ * a))
            add("chest", Up, 4 * c); add("head", Up, -4 * c)
            for i, t in enumerate(tails): add(t, Up, 12 * s_ * (i + 1) / len(tails))
        elif p == 5:
            add("chest", Lat, -fwd * 16); add("neck", Lat, fwd * 10); add("head", Lat, fwd * 14)
            for sd in "LR":
                add(f"fore_upper.{sd}", Lat, fwd * 40); add(f"fore_lower.{sd}", Lat, -fwd * 30)
            for i, t in enumerate(tails): add(t, Lat, fwd * 15)
    elif kind == "hexapod":
        if walking:
            for row, rs in (("front", 1), ("middle", -1), ("rear", 1)):
                for sd in (1, -1):
                    a = rs * sd                                 # alternating tripods
                    sfx = "R" if sd > 0 else "L"
                    add(f"{row}_coxa.{sfx}", Up, 16 * c * a * sd)
                    add(f"{row}_femur.{sfx}", F, -sd * 18 * max(0, s_ * a))
            for t in ("antenna.L.01", "antenna.R.01"): add(t, Up, 8 * s_)
            add("abdomen", Up, 5 * c)
        elif p == 5:
            add("thorax", Lat, -fwd * 12); add("head", Lat, fwd * 10)
            for sd, sfx in ((1, "R"), (-1, "L")):
                add(f"front_femur.{sfx}", F, -sd * 35); add(f"front_coxa.{sfx}", Up, -14 * sd)
    elif kind == "flyer":
        wings = [b.name for b in arm.pose.bones if b.name.startswith("wing")]
        if walking:
            for w in wings:
                sd = side_of(w); deep = w.endswith(".02") or w.endswith(".03") or "rib" in w
                lag = 0.7 if deep else 0.0
                add(w, F, sd * (38 if not deep else 18) * math.cos(ph - lag))
            for i, t in enumerate(tails): add(t, Lat, 8 * math.sin(ph) * (i + 1) / max(1, len(tails)))
            for leg in [b.name for b in arm.pose.bones if b.name.startswith("leg")]: add(leg, Lat, fwd * 10 * s_)
        elif p == 5:
            add("chest", Lat, fwd * 10); add("thorax", Lat, fwd * 10); add("head", Lat, fwd * 18)
            for w in wings: add(w, F, side_of(w) * 25)
            for leg in [b.name for b in arm.pose.bones if b.name.startswith("leg")]: add(leg, Lat, fwd * 35)
    for name, q in rot.items():
        pb = arm.pose.bones[name]
        r = pb.bone.matrix_local.to_quaternion()
        pb.rotation_quaternion = r.inverted() @ q @ r
    bpy.context.view_layer.update()
    return c if walking else 0.0

def creature_kind(arm):
    names = {b.name for b in arm.data.bones}
    if any(n.startswith("wing") for n in names): return "flyer"
    if "front_coxa.L" in names: return "hexapod"
    if "fore_upper.L" in names: return "quadruped"
    if "thigh.L" in names: return "biped"
    return "auto"

class AutoGait:
    """A gait for skeletons without known bone names (Tripo's creature rigs), read from the skeleton's shape. Every
    bone chain that ends at the ground is a leg, starting below the last bone it shares with another leg. Legs step
    in alternating sets (a trot on four legs, tripods on six), swinging along their own sweep axis and lifting as they
    come forward. Other loose chains (tails, antennae, mandibles) sway. Attack raises the front legs and works the
    chains at the front."""
    def __init__(self, arm, obj, F, Up, Lat):
        self.arm, self.F, self.Up, self.Lat = arm, F, Up, Lat
        bones = arm.data.bones
        hz = lambda v: v.dot(Up)
        # How low each bone's skin reaches (vertices it dominates), in armature space: bones often stop short of
        # the toes, so the mesh decides what touches the ground.
        names = {g.index: g.name for g in obj.vertex_groups}
        m2a = arm.matrix_world.inverted() @ obj.matrix_world
        low, ground, top = {}, math.inf, -math.inf
        for v in obj.data.vertices:
            z = hz(m2a @ v.co); ground = min(ground, z); top = max(top, z)
            if v.groups:
                g = max(v.groups, key=lambda g: g.weight)
                n = names.get(g.group)
                if n: low[n] = min(low.get(n, math.inf), z)
        H = top - ground
        centre = sum((b.head_local for b in bones), Vector()) / len(bones)
        reach = lambda b: min(low.get(b.name, math.inf), low.get(b.parent.name, math.inf) if b.parent else math.inf)
        feet = [b for b in bones if not b.children and reach(b) - ground < 0.12 * H]
        shared = {}
        for f in feet:
            b = f
            while b: shared[b.name] = shared.get(b.name, 0) + 1; b = b.parent
        self.legs = []
        for f in feet:
            chain = [f]; b = f.parent
            while b and shared[b.name] == 1 and hz(b.head_local) - ground < 0.85 * H:
                chain.insert(0, b); b = b.parent
            root = chain[0]
            d = (f.tail_local - root.head_local).normalized()
            side = 1 if (root.head_local - centre).dot(Lat) > 0 else -1
            sweep = d.cross(F)
            sweep = (sweep if sweep.length > 0.2 else Lat.copy()).normalized()
            if (Quaternion(sweep, 0.2) @ d).dot(F) < d.dot(F): sweep = -sweep
            flat = d - Up * d.dot(Up)
            lift = None
            if flat.length > 0.5:
                lift = flat.cross(Up).normalized()
                if (Quaternion(lift, 0.2) @ d).dot(Up) < d.dot(Up): lift = -lift
            self.legs.append(dict(chain=[c.name for c in chain], side=side, at=root.head_local.dot(F), sweep=sweep, lift=lift))
        # Alternate along each side, and opposite sides out of step: diagonal pairs move together.
        for sd in (1, -1):
            row = sorted((l for l in self.legs if l["side"] == sd), key=lambda l: -l["at"])
            for i, l in enumerate(row): l["phase"] = sd * (1 if i % 2 == 0 else -1); l["front"] = i == 0
        legbones = {n for l in self.legs for n in l["chain"]}
        self.loose = []
        for b in bones:
            if b.children or b.name in legbones or b.name in shared: continue
            root = b
            while root.parent and root.parent.name not in shared and root.parent.name not in legbones: root = root.parent
            if root.name not in [c[0] for c in self.loose]:
                self.loose.append((root.name, (root.head_local - centre).dot(F) > 0))

    def pose(self, p, amp=1.0):
        arm = self.arm
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0)
        rot = {}
        def add(name, axis, deg):
            rot[name] = Quaternion(axis, math.radians(deg * amp)) @ rot.get(name, Quaternion())
        walking = 1 <= p <= 4
        ph = (p - 1) / 4 * 2 * math.pi if walking else 0.0
        c, s_ = math.cos(ph), math.sin(ph)
        for l in self.legs:
            root = l["chain"][0]
            if walking:
                a = l["phase"]
                add(root, l["sweep"], 20 * c * a)
                up = max(0.0, -s_ * a)                  # lift on the forward swing
                if l["lift"] is not None: add(root, l["lift"], 18 * up)
                elif len(l["chain"]) > 1: add(l["chain"][1], l["sweep"], -30 * up)
            elif p == 5 and l["front"]:
                add(root, l["sweep"], 35)
                if l["lift"] is not None: add(root, l["lift"], 25)
        for i, (name, front) in enumerate(self.loose):
            if walking: add(name, self.Up, 8 * math.sin(ph + i))
            elif p == 5 and front: add(name, self.Lat, 15 if i % 2 else -15)
        for name, q in rot.items():
            pb = arm.pose.bones[name]
            r = pb.bone.matrix_local.to_quaternion()
            pb.rotation_quaternion = r.inverted() @ q @ r
        bpy.context.view_layer.update()
        return c if walking else 0.0

def render_creature(uid, u, fix, sc, path, poses, facings, out_dir):
    """A skinned Tripo creature on its own skeleton, posed with scripted gait cycles: keyed by bone names for named
    skeletons, or read from the skeleton's shape (AutoGait)."""
    air = u.get("domain") == "air"
    bpy.ops.import_scene.fbx(filepath=path)
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    obj = next(o for o in sc.objects if o.type == "MESH")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    kind = fix.get("skeleton", creature_kind(arm))
    # The rig keeps the source model's axes: unit_fixes' rotate / forward say how to stand it up and face it.
    fixm = Euler([math.radians(a) for a in fix.get("rotate", [0, 0, 0])]).to_matrix().to_4x4()
    fwd = Vector(fix.get("forward", [0, -1, 0]))
    yaw = Matrix.Rotation(math.atan2(-fwd.x, -fwd.y), 4, "Z")
    to_arm = (fixm @ arm.matrix_world).inverted().to_3x3()   # standing frame -> armature space
    F = (to_arm @ (yaw.inverted().to_3x3() @ Vector((0, -1, 0)))).normalized()   # whatever the yaw turns to face -Y
    Up = (to_arm @ Vector((0, 0, 1))).normalized()
    Lat = F.cross(Up).normalized()
    gait = AutoGait(arm, obj, F, Up, Lat) if kind == "auto" else None
    if gait: print("GAIT", uid, len(gait.legs), "legs", len(gait.loose), "loose chains")

    def world_verts():
        ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        M = np.array(obj.matrix_world)
        P = np.empty(len(ev.data.vertices) * 3); ev.data.vertices.foreach_get("co", P)
        return P.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
    holder = bpy.data.objects.new("holder", None); sc.collection.objects.link(holder)
    orient = bpy.data.objects.new("orient", None); sc.collection.objects.link(orient)
    orient.parent = holder; arm.parent = orient
    orient.matrix_basis = yaw @ fixm
    bpy.context.view_layer.update()
    P = world_verts(); lo, hi = P.min(axis=0), P.max(axis=0)
    dims = tuple(float(v) for v in (hi - lo)); H = dims[2]
    base = Vector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2] if not air else (lo[2] + hi[2]) / 2))
    orient.matrix_basis = Matrix.Translation(-base) @ yaw @ fixm
    C = canvas(u); ortho = C / PX_PER_UNIT
    k = ortho * fix.get("fill", 0.72) / max(dims)
    holder.scale = (k, k, k)
    rest = orient.matrix_basis.copy()
    stage(sc, C, air)

    def set_pose(p):
        bob = gait.pose(p, fix.get("amp", 1.0)) if gait else creature_pose(arm, p, kind, F, Up, Lat, fix.get("amp", 1.0))
        lift = (0.018 if kind != "flyer" else -0.03) * H * (abs(bob) if kind != "flyer" else bob)
        orient.matrix_basis = Matrix.Translation((0, 0, lift)) @ rest
        bpy.context.view_layer.update()

    shoot(sc, uid, obj, holder, fix, poses, facings, set_pose, out_dir)
    print("UNIT", uid, "skeleton", kind, "canvas", C, "verts", len(obj.data.vertices))

def stage(sc, C, air):
    """Isometric camera framing a C-point canvas, key and fill suns, and a soft sky."""
    ortho = C / PX_PER_UNIT
    cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cam_data); sc.collection.objects.link(cam); sc.camera = cam
    view = (U * math.cos(ELEV) + Vector((0, 0, -math.sin(ELEV)))).normalized()
    cam.rotation_euler = view.to_track_quat("-Z", "Y").to_euler()
    up = cam.rotation_euler.to_matrix() @ Vector((0, 1, 0))
    cam.location = -view * 50 + up * (0 if air else (0.5 - 0.12) * ortho)
    cam_data.clip_end = 200
    sc.render.resolution_x = sc.render.resolution_y = int(round(C * SCALE))

    def sun(direction, energy, color):
        ld = bpy.data.lights.new("sun", "SUN"); ld.energy = energy; ld.color = color; ld.angle = math.radians(4)
        lo_ = bpy.data.objects.new("sun", ld); sc.collection.objects.link(lo_)
        lo_.rotation_euler = Vector(direction).normalized().to_track_quat("-Z", "Y").to_euler()
    sun(-(-R + U) * 0.8 + Vector((0, 0, -1)), 5.0, (1.0, 0.93, 0.82))
    sun((-R + U) * 0.6 + Vector((0, 0, -0.4)), 1.0, (0.6, 0.72, 1.0))
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.5, 0.6, 1)

def shoot(sc, uid, obj, holder, fix, poses, facings, set_pose, out_dir):
    """Renders each pose in each facing: a lit image and its team-colour mask."""
    pairs = prepare_materials([obj], fix)
    slots = [m.name if m else None for m in obj.data.materials]
    lights = [o for o in sc.objects if o.type == "LIGHT"]
    bg = sc.world.node_tree.nodes["Background"]
    for p in poses:
        for d in facings:
            a = math.radians(45 * d)
            g = R * math.cos(a) + U * math.sin(a)
            holder.rotation_euler = (0, 0, math.atan2(g.y, g.x) - math.atan2(-1, 0))
            set_pose(p)
            for i, nm in enumerate(slots):
                if nm: obj.data.materials[i] = pairs[nm][0]
            for l in lights: l.hide_render = False
            bg.inputs["Strength"].default_value = 0.7
            sc.cycles.samples = 32; sc.cycles.use_denoising = True
            sc.view_settings.view_transform = "AgX"
            sc.render.filepath = os.path.join(out_dir, f"u3d_{uid}_d{d}_{p}.png")
            bpy.ops.render.render(write_still=True)
            for i, nm in enumerate(slots):
                if nm: obj.data.materials[i] = pairs[nm][1]
            for l in lights: l.hide_render = True
            bg.inputs["Strength"].default_value = 0
            sc.cycles.samples = 4; sc.cycles.use_denoising = False
            sc.view_settings.view_transform = "Raw"         # mask values are data, not colours
            sc.render.filepath = os.path.join(out_dir, f"u3d_{uid}_d{d}_{p}m.png")
            bpy.ops.render.render(write_still=True)

if __name__ == "__main__":
    if os.environ.get("PREVIEW"):
        # Quick check: all poses, one facing (side view), into a scratch folder.
        for uid in ids: render_unit(uid, facings=[int(os.environ.get("FACING", "0"))], out_dir=os.environ["PREVIEW"])
    else:
        for uid in ids: render_unit(uid)
