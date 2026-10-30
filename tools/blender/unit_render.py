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
import bpy, sys, os, math, json
import numpy as np
from mathutils import Vector, Matrix, Euler

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

# ---------------------------------------------------------------- materials
def hsv_mask(nt, color):
    """0..1 where the albedo is the saturated blue team marker."""
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
    return mul(mul(mr(hue, 0.52, 0.56), mr(hue, 0.72, 0.68)), mul(mr(sep.outputs[1], 0.35, 0.55), mr(sep.outputs[2], 0.08, 0.18)))

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
                mt.links.new(hsv_mask(mt, msrc), k.inputs[0]); mt.links.new(k.outputs[0], em.inputs["Color"])
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

def render_unit(uid, poses=range(POSES), facings=range(8), out_dir=OUT):
    u = UNITS[uid]; fix = FIX.get(uid, {})
    air = u.get("domain") == "air"
    rig = rig_of(uid, u)
    sc = setup_scene()
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
    yaw = Matrix.Rotation(math.atan2(fwd.x, -fwd.y), 4, "Z")
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
    bg = w.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.45, 0.5, 0.6, 1)
    lights = [o for o in sc.objects if o.type == "LIGHT"]

    pairs = prepare_materials([obj], fix)
    slots = [m.name if m else None for m in obj.data.materials]

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

    for p in poses:
        set_pose(p)
        for d in facings:
            a = math.radians(45 * d)
            g = R * math.cos(a) + U * math.sin(a)
            holder.rotation_euler = (0, 0, math.atan2(g.y, g.x) - math.atan2(-1, 0))
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
    print("UNIT", uid, rig, "canvas", C, "verts", n)

if os.environ.get("PREVIEW"):
    # Quick check: all poses, one facing (side view), into a scratch folder.
    for uid in ids: render_unit(uid, facings=[int(os.environ.get("FACING", "0"))], out_dir=os.environ["PREVIEW"])
else:
    for uid in ids: render_unit(uid)
