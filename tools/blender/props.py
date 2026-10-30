# Realistic environment props for Meridian, rendered into the same canvases as EnvironmentArt.
#
# Usage: Blender -b -P tools/blender/props.py -- [name ...]      (default: all)
#        PREVIEW=<dir> ... renders into <dir>.
# Writes Meridian/Props3D/e3d_<name>.png for cliff0-5, tree0-2, iron0-2, gold0-2, flora<k>_<v> (k 0-4, v 0-1).
# Canvas sizes (points) and ground anchors match EnvironmentArt and the sprites that use them.
import bpy, sys, os, math, random
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import buildings as K
from buildings import mat, sph, cyl, strut, horn, finish, MATS

ROOT = K.ROOT
OUT = os.environ.get("PREVIEW") or os.path.join(ROOT, "Meridian/Props3D")
os.makedirs(OUT, exist_ok=True)
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

# Shadowed props get a margin so their shadows are not clipped: the canvas grows by MX each side and MB below /
# MT above (fractions of the original size); PropModels.anchorY in the game applies the same arithmetic.
MX, MB, MT = 0.3, 0.25, 0.05
# name: (canvas w, h in points, ground anchor y fraction, shadow)
SPECS = {}
for v in range(6): SPECS[f"cliff{v}"] = (104, 140 if v >= 3 else 100, 0.2, True)
for v in range(3): SPECS[f"tree{v}"] = (64, 104, 0.08, True)
for v in range(3): SPECS[f"iron{v}"] = (72, 60, 0.22, True)
for v in range(3): SPECS[f"gold{v}"] = (68, 72, 0.16, True)
for k in range(5):
    for v in range(2): SPECS[f"flora{k}_{v}"] = (36, 40, 0.15, False)

def materials():
    K.make_materials()
    mat("rock", (0.13, 0.115, 0.13), rough=0.8, organic=True, scale=2.5)
    mat("rock2", (0.16, 0.12, 0.1), rough=0.8, organic=True, scale=2.5)
    mat("rock3", (0.11, 0.11, 0.15), rough=0.8, organic=True, scale=2.5)
    mat("lichen", (0.16, 0.26, 0.08), rough=0.9, organic=True, scale=6)
    mat("bark", (0.09, 0.055, 0.035), rough=0.85, organic=True, scale=7)
    mat("pine", (0.02, 0.12, 0.1), rough=0.7, organic=True, scale=6)
    mat("amberleaf", (0.42, 0.18, 0.03), rough=0.7, organic=True, scale=6)
    mat("lanternleaf", (0.05, 0.14, 0.09), rough=0.7, organic=True, scale=6)
    mat("lantern", (1.0, 0.75, 0.3), emit=3)
    mat("ore", (0.06, 0.055, 0.06), metal=0.6, rough=0.45, organic=True, scale=4)
    mat("rust", (0.35, 0.11, 0.03), rough=0.7, organic=True, scale=8)
    mat("vein", (0.3, 0.55, 1.0), emit=1.2)
    mat("goldxtal", (0.55, 0.2, 0.0), metal=0.4, rough=0.2, panel=0, wear=0, coat=1.0)
    m = MATS["goldxtal"]; b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Transmission Weight"].default_value = 0.05
    b.inputs["Emission Color"].default_value = (1.0, 0.45, 0.05, 1); b.inputs["Emission Strength"].default_value = 0.35
    mat("grassgold", (0.36, 0.33, 0.08), rough=0.7, panel=0, wear=0)
    mat("grassteal", (0.05, 0.25, 0.18), rough=0.7, panel=0, wear=0)
    mat("reed", (0.18, 0.22, 0.08), rough=0.7, panel=0, wear=0)
    mat("cattail", (0.18, 0.08, 0.03), rough=0.8, organic=True, scale=10)
    mat("capglow", (0.3, 0.95, 1.0), emit=2.5)
    mat("stem", (0.6, 0.6, 0.55), rough=0.6, organic=True, scale=10)
    mat("violet", (0.45, 0.25, 1.0), metal=0.1, rough=0.1, panel=0, wear=0, coat=1.0)
    MATS["violet"].node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (0.5, 0.3, 1.0, 1)
    MATS["violet"].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.8

def boulder(loc, size, m, seed, rough=0.5, flat=0.75):
    """A faceted boulder: an icosphere with layered displacement, flattened and sunk into the ground."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1, location=loc)
    o = bpy.context.object; o.scale = size; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for i, (kind, sc, st) in enumerate((("VORONOI", 0.6, rough), ("CLOUDS", 0.3, rough * 0.4))):
        t = bpy.data.textures.new(f"r{i}", kind); t.noise_scale = sc * max(size)
        if kind == "VORONOI": t.distance_metric = "DISTANCE"
        d = o.modifiers.new(f"d{i}", "DISPLACE"); d.texture = t; d.strength = st * max(size); d.texture_coords = "GLOBAL"
        d.mid_level = 0.5 + seed * 0.013
    o.modifiers.new("dec", "DECIMATE").ratio = 0.18        # facets
    o.data.materials.append(MATS[m])
    return o

def blades(cx, cy, n, h, m, spread=0.12, lean=0.5, w=0.012, seed=0):
    rnd = random.Random(seed)
    for i in range(n):
        a = rnd.random() * 6.28; r = rnd.random() * spread
        b = Vector((cx + math.cos(a) * r, cy + math.sin(a) * r, 0))
        t = b + Vector((math.cos(a) * h * lean * rnd.random(), math.sin(a) * h * lean * rnd.random(), h * (0.6 + rnd.random() * 0.4)))
        horn(b, t, w, m, bend=(0, 0, 0), segs=4)

def build(name):
    rnd = random.Random(hash(name) % 1000)
    if name.startswith("cliff"):
        v = int(name[5:]); m = ("rock", "rock2", "rock3")[v % 3]
        chunks = [(-0.45, 0.15, 0.55, 0.62), (0.4, 0.2, 0.5, 0.5), (0.0, -0.3, 0.6, 0.42)]
        if v >= 3: chunks = [(0.0, 0.25, 0.45, 1.5), (-0.3, 0.05, 0.4, 0.95)] + chunks
        for i, (x, y, r, h) in enumerate(chunks):
            boulder((x, y, h * 0.45), (r, r * 0.9, h * 0.6), m, v * 7 + i)
        if v % 3 == 1:
            for k in range(3): horn((0.45, -0.1, 0.2), (0.55 + k * 0.08, -0.25, 0.65 - k * 0.1), 0.06, "violet", segs=3)
        return 2.3
    if name.startswith("tree"):
        v = int(name[4:])
        if v == 0:      # teal spire pine
            horn((0, 0, 0), (0, 0, 2.2), 0.09, "bark", segs=6)
            for i in range(6):
                z = 0.5 + i * 0.3; r = 0.55 - i * 0.08
                cyl((0, 0, z), r, 0.4, "pine", verts=14, r2=0.03)
                o = bpy.context.object; t = bpy.data.textures.new("n", "CLOUDS"); t.noise_scale = 0.1
                d = o.modifiers.new("d", "DISPLACE"); d.texture = t; d.strength = 0.08
        else:           # amber broadleaf / lantern tree
            horn((0, 0, 0), (0.05, 0.02, 1.3), 0.11, "bark", bend=(0.08, 0, 0), segs=6)
            for k in range(3):
                a = k * 2.1; strut((0.03, 0.01, 0.9), (math.cos(a) * 0.4, math.sin(a) * 0.4, 1.3), 0.035, "bark")
            leaf = "amberleaf" if v == 1 else "lanternleaf"
            K.blob([((0, 0, 1.55), 0.55, (1.1, 1.0, 0.75)), ((0.35, 0.1, 1.4), 0.4, None), ((-0.3, -0.15, 1.45), 0.42, None),
                    ((0.05, -0.3, 1.75), 0.35, None)], leaf, resolution=0.04, displace=0.18, sub=0)
            if v == 2:
                for k in range(7):
                    a = k * 0.9; sph((math.cos(a) * 0.5, math.sin(a) * 0.45, 1.25 + (k % 3) * 0.12), 0.06, "lantern")
        return 1.45
    if name.startswith("iron"):
        v = int(name[4:])
        for i in range(3 + v % 2):
            x, y = (rnd.random() - 0.5) * 0.8, (rnd.random() - 0.5) * 0.5
            boulder((x, y, 0.15), (0.32, 0.28, 0.3), "ore", v * 5 + i, rough=0.6)
            boulder((x + 0.05, y - 0.1, 0.24), (0.12, 0.08, 0.06), "rust", i)
        for k in range(3): strut((-0.2 + k * 0.18, -0.2, 0.25), (-0.05 + k * 0.18, -0.25, 0.42), 0.012, "vein")
        return 1.35
    if name.startswith("gold"):
        v = int(name[4:])
        boulder((0, 0, 0.05), (0.45, 0.35, 0.12), "rock", v)
        for i in range(9 + v * 2):
            a = rnd.random() * 6.28; r = rnd.random() * 0.25; h = 0.35 + rnd.random() * 0.55
            b = Vector((math.cos(a) * r, math.sin(a) * r, 0.05))
            t = b + Vector((math.cos(a) * 0.25 * rnd.random(), math.sin(a) * 0.25 * rnd.random(), h))
            v_ = t - b
            bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.08 + rnd.random() * 0.06, radius2=0.0, depth=v_.length, location=(b + t) / 2)
            o = bpy.context.object; o.rotation_mode = "QUATERNION"; o.rotation_quaternion = v_.to_track_quat("Z", "Y")
            finish(o, "goldxtal", bevel=0, smooth=False)
        return 1.2
    if name.startswith("flora"):
        k, v = int(name[5]), int(name[7])
        if k in (0, 1): blades(0, 0, 12, 0.28, "grassgold" if k == 0 else "grassteal", seed=v * 11 + k)
        elif k == 2:
            blades(0, 0, 7, 0.55, "reed", spread=0.06, lean=0.15, w=0.01, seed=v)
            for i in range(2 + v): cyl(((i - 0.5) * 0.06, 0.02 * i, 0.48 + i * 0.04), 0.022, 0.12, "cattail", verts=10)
        elif k == 3:
            for i in range(3 + v):
                x, y = (rnd.random() - 0.5) * 0.25, (rnd.random() - 0.5) * 0.2; h = 0.08 + rnd.random() * 0.12
                strut((x, y, 0), (x, y, h), 0.012, "stem")
                sph((x, y, h), (0.05, 0.05, 0.025), "capglow")
        else:
            for i in range(3):
                horn(((i - 1) * 0.05, 0, 0), ((i - 1) * 0.12, 0.02, 0.3 + (i % 2) * 0.12), 0.05, "violet", segs=3)
        return 0.8
    raise KeyError(name)

def render(name):
    W, H, anchor, shadow = SPECS[name]
    W0 = W
    if shadow:
        anchor = (anchor * H + MB * H) / (H * (1 + MB + MT))
        W, H = round(W * (1 + 2 * MX)), round(H * (1 + MB + MT))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"; prefs.get_devices()
    for dv in prefs.devices: dv.use = True
    sc.cycles.device = "GPU"; sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
    materials()
    width_units = build(name)        # model size the canvas is framed for (world units across)
    if shadow:
        bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0)); bpy.context.object.is_shadow_catcher = True
    # Frame: the canvas spans width_units horizontally; the ground origin sits at `anchor` of the height.
    ortho = width_units * W / W0
    px_per_unit = W / ortho
    cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.sensor_fit = "HORIZONTAL"; cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cam_data); sc.collection.objects.link(cam); sc.camera = cam
    view = (K.U * math.cos(K.ELEV) + Vector((0, 0, -math.sin(K.ELEV)))).normalized()
    cam.rotation_euler = view.to_track_quat("-Z", "Y").to_euler()
    up = cam.rotation_euler.to_matrix() @ Vector((0, 1, 0))
    cam.location = -view * 40 + up * ((H / 2 - H * anchor) / px_per_unit)
    sc.render.resolution_x = W * 2; sc.render.resolution_y = H * 2
    def sun(direction, energy, color, angle=3):
        ld = bpy.data.lights.new("sun", "SUN"); ld.energy = energy; ld.color = color; ld.angle = math.radians(angle)
        o = bpy.data.objects.new("sun", ld); sc.collection.objects.link(o)
        o.rotation_euler = Vector(direction).normalized().to_track_quat("-Z", "Y").to_euler()
    # Higher, softer key than units/buildings so shadows stay inside these small canvases.
    sun(-(-K.R + K.U) * 0.3 + Vector((0, 0, -1)), 4.5, (1.0, 0.93, 0.82), 9)
    sun((-K.R + K.U) * 0.6 + Vector((0, 0, -0.5)), 0.9, (0.6, 0.72, 1.0), 10)
    wd = bpy.data.worlds.new("w"); sc.world = wd; wd.use_nodes = True
    bg = wd.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.45, 0.5, 0.6, 1); bg.inputs["Strength"].default_value = 0.7
    sc.view_settings.view_transform = "AgX"
    sc.cycles.samples = 64; sc.cycles.use_denoising = True
    sc.render.filepath = os.path.join(OUT, f"e3d_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("PROP", name)

if __name__ == "__main__":
    for nm in (args or list(SPECS)):
        render(nm)
