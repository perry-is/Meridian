# Renders a Tripo unit model into Meridian sprites: 8 facings, plus a team-colour mask per facing.
#
# Usage: Blender -b -P tools/blender/unit_render.py -- <unit_id> [<unit_id> ...]
# Reads  art/tripo/<unit_id>.glb and the unit's size/domain from MeridianCore's unit data.
# Writes Meridian/Units3D/u3d_<unit_id>_d<k>.png and u3d_<unit_id>_d<k>m.png (k = 0..7).
#
# Facing k points along screen angle k*45° (0 = screen right, counter-clockwise), measured on the ground
# plane, matching Iso in GameController.swift: world +x+y is screen right, world -x+y is screen up.
# Canvas and anchor match UnitArt.canvasSize and GameScene (ground anchor 12% up, air centred).
import bpy, sys, os, math, json
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
SCALE = 3                                # pixels per point (retina)
R = Vector((1, 1, 0)).normalized()       # screen right on the ground
U = Vector((-1, 1, 0)).normalized()      # screen up on the ground (away from the viewer)

def canvas(u):
    return 26 + u.get("radius", 0.4) * 68   # UnitArt.canvasSize

def blue_mask(nt, color):
    """0..1 where the albedo is the saturated blue team marker."""
    sep = nt.nodes.new("ShaderNodeSeparateColor"); sep.mode = "HSV"
    nt.links.new(color, sep.inputs[0])
    def mr(v, a, b, c, d):
        n = nt.nodes.new("ShaderNodeMapRange"); n.clamp = True
        nt.links.new(v, n.inputs["Value"])
        n.inputs["From Min"].default_value, n.inputs["From Max"].default_value = a, b
        n.inputs["To Min"].default_value, n.inputs["To Max"].default_value = c, d
        return n.outputs["Result"]
    def mul(a, b):
        n = nt.nodes.new("ShaderNodeMath"); n.operation = "MULTIPLY"
        nt.links.new(a, n.inputs[0]); nt.links.new(b, n.inputs[1]); return n.outputs[0]
    hue = sep.outputs[0]
    lo = mr(hue, 0.52, 0.56, 0, 1); hi = mr(hue, 0.72, 0.68, 0, 1)
    sat = mr(sep.outputs[1], 0.35, 0.55, 0, 1)
    val = mr(sep.outputs[2], 0.08, 0.18, 0, 1)
    return mul(mul(lo, hi), mul(sat, val))

def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"; prefs.get_devices()
    for d in prefs.devices: d.use = True
    sc.cycles.device = "GPU"
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "AgX"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    return sc

def render_unit(uid):
    u = UNITS[uid]; fix = FIX.get(uid, {})
    air = u.get("domain") == "air"
    sc = setup_scene()
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, f"art/tripo/{uid}.glb"))
    meshes = [o for o in sc.objects if o.type == "MESH"]
    # One pivot that carries the model's fix-up rotation and the facing yaw.
    bpy.ops.object.empty_add(location=(0, 0, 0)); pivot = bpy.context.object
    for o in sc.objects:
        if o is not pivot and o.parent is None: o.parent = pivot
    pivot.rotation_euler = Euler([math.radians(a) for a in fix.get("rotate", [0, 0, 0])])
    bpy.context.view_layer.update()
    lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c); lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    size = hi - lo
    # Fit: the model's largest extent fills `fill` of the canvas width.
    C = canvas(u); ortho = C / PX_PER_UNIT
    k = ortho * fix.get("fill", 0.72) / max(size)
    base = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z if not air else (lo.z + hi.z) / 2))
    holder = bpy.data.objects.new("holder", None); sc.collection.objects.link(holder)
    pivot.parent = holder
    pivot.location = -base
    holder.scale = (k, k, k)

    # Camera: 2:1 iso, looking at the ground origin, which sits 12% up the frame (ground) or centred (air).
    cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cam_data); sc.collection.objects.link(cam); sc.camera = cam
    view = (U * math.cos(ELEV) + Vector((0, 0, -math.sin(ELEV)))).normalized()   # looking away from the viewer, downwards
    cam.rotation_euler = view.to_track_quat("-Z", "Y").to_euler()
    up = cam.rotation_euler.to_matrix() @ Vector((0, 1, 0))
    cam.location = -view * 50 + up * (0 if air else (0.5 - 0.12) * ortho)
    cam_data.clip_end = 200
    sc.render.resolution_x = sc.render.resolution_y = int(round(C * SCALE))

    # Light: warm key from the upper left of the screen, cool fill from the lower right.
    def sun(direction, energy, color):
        ld = bpy.data.lights.new("sun", "SUN"); ld.energy = energy; ld.color = color; ld.angle = math.radians(4)
        lo_ = bpy.data.objects.new("sun", ld); sc.collection.objects.link(lo_)
        lo_.rotation_euler = Vector(direction).normalized().to_track_quat("-Z", "Y").to_euler()
    sun(-(-R + U) * 0.8 + Vector((0, 0, -1)), 5.0, (1.0, 0.93, 0.82))
    sun((-R + U) * 0.6 + Vector((0, 0, -0.4)), 1.0, (0.6, 0.72, 1.0))
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.45, 0.5, 0.6, 1); bg.inputs["Strength"].default_value = 0.7

    # Mask materials: emission of the blue-marker mask, swapped in for the second pass.
    originals = {}
    for o in meshes:
        originals[o.name] = list(o.data.materials)
    def make_mask(m):
        mm = m.copy(); mm.name = m.name + "_mask"; nt = mm.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        link = bsdf.inputs["Base Color"].links
        em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = 1
        if link: nt.links.new(blue_mask(nt, link[0].from_socket), em.inputs["Color"])
        else: em.inputs["Color"].default_value = (0, 0, 0, 1)
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        nt.links.new(em.outputs[0], out.inputs["Surface"])
        return mm
    masks = {m.name: make_mask(m) for o in meshes for m in o.data.materials if m}

    for d in range(8):
        a = math.radians(45 * d)
        g = R * math.cos(a) + U * math.sin(a)               # desired ground facing
        fwd = Vector(fix.get("forward", [0, -1, 0]))         # model's own forward after the fix rotation
        yaw = math.atan2(g.y, g.x) - math.atan2(fwd.y, fwd.x)
        holder.rotation_euler = (0, 0, yaw)
        # Pass 1: lit colour.
        for o in meshes:
            for i, m in enumerate(originals[o.name]): o.data.materials[i] = m
        sc.cycles.samples = 64; sc.cycles.use_denoising = True
        sc.world = w
        for ob in sc.objects:
            if ob.type == "LIGHT": ob.hide_render = False
        sc.view_settings.view_transform = "AgX"
        sc.render.filepath = os.path.join(OUT, f"u3d_{uid}_d{d}.png")
        bpy.ops.render.render(write_still=True)
        # Pass 2: team mask (unlit, raw values).
        for o in meshes:
            for i, m in enumerate(originals[o.name]):
                if m: o.data.materials[i] = masks[m.name]
        for ob in sc.objects:
            if ob.type == "LIGHT": ob.hide_render = True
        bg.inputs["Strength"].default_value = 0
        sc.cycles.samples = 16; sc.cycles.use_denoising = False
        sc.view_settings.view_transform = "Standard"
        sc.render.filepath = os.path.join(OUT, f"u3d_{uid}_d{d}m.png")
        bpy.ops.render.render(write_still=True)
        bg.inputs["Strength"].default_value = 0.7
    print("UNIT", uid, "canvas", C, "fit", round(k, 3))

for uid in ids:
    render_unit(uid)
