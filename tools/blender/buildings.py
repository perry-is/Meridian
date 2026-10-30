# Procedural realistic buildings for Meridian, rendered into the game's building canvases.
#
# Usage: Blender -b -P tools/blender/buildings.py -- [building_id ...]      (default: all 24)
#        PREVIEW=<dir> ... renders into <dir> instead of the app bundle.
# Writes Meridian/Buildings3D/b3d_<id>.png (lit, with ground shadow), b3d_<id>m.png (team-colour mask) and
# b3d_<id>.json ({"height": points above the footprint centre, "lights": [[x, y], ...]}).
#
# Geometry is in tile units with the footprint centred on the origin. The camera matches Iso and
# WorldArt.buildingCanvas: canvas 64n x (32n + headroom) points, footprint centre 16n points above the bottom.
import bpy, bmesh, sys, os, math, json, random
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DEFS = {b["id"]: b for b in json.load(open(os.path.join(ROOT, "MeridianCore/Sources/MeridianCore/Data/buildings.json")))}
OUT = os.environ.get("PREVIEW") or os.path.join(ROOT, "Meridian/Buildings3D")
os.makedirs(OUT, exist_ok=True)
PX = 32 * math.sqrt(2)          # points per world unit (screen plane)
SCALE = 2
HEADROOM = {"hq": 150, "tower": 140, "forward": 120, "air": 112, "research": 112}   # BuildingArt.headroom
R = Vector((1, 1, 0)).normalized(); U = Vector((-1, 1, 0)).normalized()
ELEV = math.radians(30)

# ---------------------------------------------------------------- materials (realistic PBR, as in style_test.py)
def _ramp(nt, inp, lo, hi):
    r = nt.nodes.new("ShaderNodeValToRGB"); r.color_ramp.elements[0].position = lo; r.color_ramp.elements[1].position = hi
    nt.links.new(inp, r.inputs[0]); return r.outputs[0]

def _mix(nt, fac, a, b):
    m = nt.nodes.new("ShaderNodeMix"); m.data_type = "RGBA"
    ins = {s.identifier: s for s in m.inputs}
    for k, v in (("Factor_Float", fac), ("A_Color", a), ("B_Color", b)):
        if isinstance(v, bpy.types.NodeSocket): nt.links.new(v, ins[k])
        else: ins[k].default_value = v
    return {s.identifier: s for s in m.outputs}["Result_Color"]

def _math(nt, op, a, b=None, c=None):
    n = nt.nodes.new("ShaderNodeMath"); n.operation = op
    for i, v in enumerate((a, b, c)):
        if v is None: continue
        if isinstance(v, bpy.types.NodeSocket): nt.links.new(v, n.inputs[i])
        else: n.inputs[i].default_value = v
    return n.outputs[0]

def _seams(nt, tc, sc):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sp = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Object"], sp.inputs[0])
    sn = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(geo.outputs["Normal"], sn.inputs[0])
    best = None
    for i, (k, off) in enumerate(((1.0, 0.37), (0.8, 0.11), (1.6, 0.53))):
        f = _math(nt, "FRACT", _math(nt, "ADD", _math(nt, "MULTIPLY", sp.outputs[i], sc * k), off))
        d = _math(nt, "SUBTRACT", 0.5, _math(nt, "ABSOLUTE", _math(nt, "SUBTRACT", f, 0.5)))
        d = _math(nt, "ADD", d, _math(nt, "MULTIPLY", _math(nt, "ABSOLUTE", sn.outputs[i]), 2.0))
        best = d if best is None else _math(nt, "MINIMUM", best, d)
    return best

MATS = {}
def mat(name, color, metal=0.0, rough=0.5, emit=0.0, panel=1.0, scale=4.0, wear=1.0, organic=False, team=False, coat=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]; col = (*color, 1)
    m["team"] = team
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.5 * scale; nz.inputs["Detail"].default_value = 10
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.35 / scale * 4
    grime = _ramp(nt, ao.outputs["AO"], 0.15, 0.85)
    dirty = _mix(nt, grime, (color[0] * 0.25, color[1] * 0.22, color[2] * 0.2, 1), col)
    dirty = _mix(nt, _ramp(nt, nz.outputs["Fac"], 0.45, 0.75), dirty, tuple(c * 0.72 for c in color) + (1,))
    base = dirty
    if not organic and wear > 0 and not emit:
        edge = nt.nodes.new("ShaderNodeAmbientOcclusion"); edge.inside = True; edge.inputs["Distance"].default_value = 0.02
        inv = nt.nodes.new("ShaderNodeInvert"); nt.links.new(_ramp(nt, edge.outputs["AO"], 0.55, 0.75), inv.inputs["Color"])
        wm = _math(nt, "MULTIPLY", inv.outputs[0], wear * 0.8)
        base = _mix(nt, wm, dirty, (0.5, 0.5, 0.52, 1))
        mt = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(wm, mt.inputs["Value"])
        mt.inputs["To Min"].default_value = metal; mt.inputs["To Max"].default_value = 1
        nt.links.new(mt.outputs["Result"], b.inputs["Metallic"])
    else:
        b.inputs["Metallic"].default_value = metal
    nt.links.new(base, b.inputs["Base Color"])
    rr = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(nz.outputs["Fac"], rr.inputs["Value"])
    rr.inputs["To Min"].default_value = max(0.05, rough - 0.15); rr.inputs["To Max"].default_value = rough + 0.2
    nt.links.new(rr.outputs["Result"], b.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Distance"].default_value = 0.01
    if organic:
        vo = nt.nodes.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = 9 * scale / 4
        nt.links.new(tc.outputs["Object"], vo.inputs["Vector"])
        h = _math(nt, "ADD", vo.outputs["Distance"], _math(nt, "MULTIPLY", nz.outputs["Fac"], 0.5))
        bump.inputs["Strength"].default_value = 0.7; nt.links.new(h, bump.inputs["Height"])
        b.inputs["Coat Weight"].default_value = 0.6; b.inputs["Coat Roughness"].default_value = 0.15
    elif panel > 0 and not emit:
        seam = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(_seams(nt, tc, 1.25 * scale * panel), seam.inputs["Value"])
        seam.inputs["From Max"].default_value = 0.03
        fine = nt.nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value = 60 * scale
        nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
        h = _math(nt, "MULTIPLY_ADD", fine.outputs["Fac"], 0.08, seam.outputs["Result"])
        bump.inputs["Strength"].default_value = 0.5; nt.links.new(h, bump.inputs["Height"])
    if not emit: nt.links.new(bump.outputs[0], b.inputs["Normal"])
    if coat: b.inputs["Coat Weight"].default_value = coat
    if emit:
        b.inputs["Emission Color"].default_value = col; b.inputs["Emission Strength"].default_value = emit
    MATS[name] = m
    return m

def hazard_mat():
    m = bpy.data.materials.new("hazard"); m.use_nodes = True; nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord"); w = nt.nodes.new("ShaderNodeTexWave")
    w.inputs["Scale"].default_value = 6.0; w.bands_direction = "DIAGONAL"; w.wave_profile = "SAW"
    nt.links.new(tc.outputs["Object"], w.inputs["Vector"])
    nt.links.new(_mix(nt, _ramp(nt, w.outputs["Fac"], 0.49, 0.51), (0.7, 0.42, 0.02, 1), (0.02, 0.02, 0.02, 1)), b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.6; m["team"] = False; MATS["hazard"] = m

def make_materials():
    MATS.clear()
    TEAM = (0.03, 0.12, 0.85)
    # Concord
    mat("hull", (0.27, 0.265, 0.24), metal=0.2, rough=0.45)
    mat("olive", (0.17, 0.19, 0.11), metal=0.15, rough=0.5)
    mat("armor", (0.13, 0.14, 0.15), metal=0.5, rough=0.4)
    mat("dark", (0.045, 0.047, 0.055), metal=0.7, rough=0.4, panel=0.7)
    mat("concrete", (0.19, 0.18, 0.16), rough=0.85, panel=0.6, wear=0.2)
    mat("team", TEAM, metal=0.3, rough=0.35, team=True)
    mat("glow", (1.0, 0.55, 0.2), emit=1.4)
    mat("red", (1, 0.08, 0.04), emit=8)
    mat("glass", (0.05, 0.12, 0.16), metal=0.0, rough=0.05, panel=0, coat=1.0)
    hazard_mat()
    # Lattice
    mat("obsidian", (0.035, 0.038, 0.05), metal=0.6, rough=0.22, panel=1.4)
    mat("gunmetal", (0.11, 0.12, 0.135), metal=0.85, rough=0.32)
    mat("chrome", (0.5, 0.52, 0.55), metal=1.0, rough=0.12, panel=0, wear=0)
    mat("cyan", (0.2, 0.85, 1.0), emit=2.5)
    mat("teamglow", (0.1, 0.3, 1.0), emit=1.6, team=True)
    mat("molten", (0.25, 0.9, 1.0), emit=1.2)
    # Brood
    mat("chitin", (0.09, 0.04, 0.09), metal=0.1, rough=0.3, organic=True, scale=5)
    mat("flesh", (0.16, 0.035, 0.06), rough=0.35, organic=True, scale=6)
    mat("bone", (0.42, 0.36, 0.27), rough=0.45, organic=True, scale=8)
    mat("creep", (0.1, 0.045, 0.1), rough=0.4, organic=True, scale=3)
    mat("bio", (0.45, 1.0, 0.3), emit=2.2)
    mat("teamchitin", (0.03, 0.09, 0.5), metal=0.1, rough=0.3, organic=True, scale=5, team=True)
    mat("hole", (0.0, 0.0, 0.0), rough=1.0, panel=0, wear=0)

# ---------------------------------------------------------------- geometry kit
BEV = 0.012

def finish(o, m, bevel=1.0, smooth=True, sub=0):
    o.data.materials.append(MATS[m])
    if bevel:
        bv = o.modifiers.new("bev", "BEVEL"); bv.width = BEV * bevel; bv.segments = 2; bv.limit_method = "ANGLE"
    if sub:
        s = o.modifiers.new("sub", "SUBSURF"); s.levels = s.render_levels = sub
    if smooth: bpy.ops.object.shade_auto_smooth()
    return o

def box(loc, size, m, rot=(0, 0, 0), bevel=1.0, sub=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, m, bevel, sub=sub)

def cyl(loc, r, h, m, rot=(0, 0, 0), verts=32, bevel=1.0, r2=None):
    if r2 is None: bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=verts)
    else: bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, rotation=rot, vertices=verts)
    return finish(bpy.context.object, m, bevel)

def hexp(loc, r, h, m, r2=None):
    return cyl(loc, r, h, m, verts=6, r2=r2)

def sph(loc, s, m, rot=(0, 0, 0), smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=loc, rotation=rot, segments=48, ring_count=24)
    o = bpy.context.object; o.scale = s if isinstance(s, (tuple, list)) else (s, s, s)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, m, bevel=0)

def organ(loc, s, m, rot=(0, 0, 0), lump=0.18):
    """A sphere with a lumpy organic surface (sacs, eggs, carapace plates)."""
    o = sph(loc, s, m, rot)
    tex = bpy.data.textures.new("lump", "CLOUDS"); tex.noise_scale = 0.12
    d = o.modifiers.new("lump", "DISPLACE"); d.texture = tex; d.texture_coords = "OBJECT"
    d.strength = lump * (max(s) if isinstance(s, (tuple, list)) else s)
    return o

def torus(loc, R_, r, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(location=loc, rotation=rot, major_radius=R_, minor_radius=r, major_segments=64, minor_segments=12)
    return finish(bpy.context.object, m, bevel=0)

def strut(a, b, r, m, verts=12):
    a, b = Vector(a), Vector(b); v = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=v.length, location=(a + b) / 2, vertices=verts)
    o = bpy.context.object; o.rotation_mode = "QUATERNION"; o.rotation_quaternion = v.to_track_quat("Z", "Y")
    return finish(o, m, bevel=0)

def horn(base, tip, r, m, bend=(0, 0, 0), segs=12):
    """Smooth tapered curved spike from base to tip (bone horns, thorns, spines, roots)."""
    base, tip, bend = Vector(base), Vector(tip), Vector(bend)
    cu = bpy.data.curves.new("horn", "CURVE"); cu.dimensions = "3D"
    cu.bevel_depth = r; cu.bevel_resolution = 4; cu.use_fill_caps = True; cu.resolution_u = 4
    sp = cu.splines.new("POLY"); sp.points.add(segs)
    for i in range(segs + 1):
        t = i / segs
        p = base.lerp(tip, t) + bend * math.sin(math.pi * t)
        sp.points[i].co = (*p, 1); sp.points[i].radius = (1 - t) ** 0.8 + 0.02
    ob = bpy.data.objects.new("horn", cu); bpy.context.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    return finish(bpy.context.object, m, bevel=0)

LIGHTS = []
def beacon(loc, m="red", s=0.03):
    sph(loc, s, m); LIGHTS.append(Vector(loc))

def blob(elements, m, resolution=0.03, displace=0.0, sub=1):
    """Organic mass from metaball elements [(loc, radius, (sx, sy, sz))], converted to a smooth mesh."""
    mb = bpy.data.metaballs.new("mb"); mb.resolution = resolution; mb.render_resolution = resolution
    ob = bpy.data.objects.new("mb", mb); bpy.context.collection.objects.link(ob)
    for loc, rad, s in elements:
        e = mb.elements.new(); e.co = loc; e.radius = rad
        if s: e.type = "ELLIPSOID"; e.size_x, e.size_y, e.size_z = s
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.object
    if displace:
        tex = bpy.data.textures.new("n", "CLOUDS"); tex.noise_scale = 0.25
        d = o.modifiers.new("disp", "DISPLACE"); d.texture = tex; d.strength = displace; d.texture_coords = "OBJECT"
    return finish(o, m, bevel=0, sub=sub)

def creep(n, m="creep"):
    """Organic ground mat filling the footprint."""
    blob([((0, 0, -0.02), n * 0.62, (1, 1, 0.08))], m, resolution=0.05, displace=0.03, sub=0)

def plinth(n, h=0.06, m="concrete", inset=0.03):
    box((0, 0, h / 2), (n - inset * 2, n - inset * 2, h), m)

# ---------------------------------------------------------------- Concord
def h_hq(n):
    plinth(n, 0.08)
    box((n * 0.48, 0, 0.085), (0.04, n * 0.94, 0.01), "hazard", bevel=0)
    box((0, -n * 0.48, 0.085), (n * 0.94, 0.04, 0.01), "hazard", bevel=0)
    box((0, 0, 0.2), (3.4, 3.4, 0.24), "armor")
    box((0, 0, 0.55), (3.2, 3.2, 0.5), "hull")
    box((0, 0, 0.82), (3.28, 3.28, 0.05), "armor")
    box((0.25, -1.61, 0.5), (1.3, 0.04, 0.6), "dark")
    for k in range(5): box((0.25, -1.64, 0.26 + k * 0.12), (1.22, 0.02, 0.02), "armor", bevel=0.3)
    box((0.25, -1.63, 0.84), (1.45, 0.06, 0.06), "hazard", bevel=0.3)
    for i in range(6): box((1.61, -1.2 + i * 0.48, 0.66), (0.02, 0.24, 0.09), "glow", bevel=0)
    for i in range(2): box((-1.25 + i * 0.48, -1.61, 0.66), (0.24, 0.02, 0.09), "glow", bevel=0)
    box((-0.4, 0.4, 1.15), (2.0, 2.0, 0.62), "hull")
    box((-0.4, 0.4, 1.17), (2.06, 2.06, 0.11), "team")
    for i in range(4):
        box((0.61, -0.3 + i * 0.38, 1.34), (0.02, 0.2, 0.07), "glow", bevel=0)
        box((-1.0 + i * 0.38, -0.61, 1.34), (0.2, 0.02, 0.07), "glow", bevel=0)
    box((-0.4, 0.4, 1.48), (2.08, 2.08, 0.05), "armor")
    box((-0.6, 0.6, 1.72), (0.8, 0.8, 0.45), "armor")
    box((-0.6, 0.19, 1.78), (0.62, 0.02, 0.12), "glow", bevel=0)
    strut((-0.6, 0.6, 1.9), (-0.6, 0.6, 2.85), 0.025, "dark")
    for z in (2.3, 2.5): box((-0.6, 0.6, z), (0.24, 0.02, 0.02), "dark", bevel=0)
    beacon((-0.6, 0.6, 2.88), s=0.05)
    cyl((-1.1, 1.1, 1.6), 0.07, 0.18, "dark")
    sph((-1.1, 1.1, 1.78), (0.3, 0.3, 0.08), "hull", rot=(0.5, 0, -0.8))
    cyl((0.9, -0.8, 0.88), 0.58, 0.04, "dark", verts=48)
    torus((0.9, -0.8, 0.91), 0.42, 0.014, "glow")
    for i in range(3): cyl((1.2, 0.45 + i * 0.36, 0.95), 0.12, 0.2, "armor")
    for z in (0.32, 0.4): cyl((1.66, 0, z), 0.03, 3.0, "dark", rot=(math.pi / 2, 0, 0), verts=12)
    for x, y in ((1.5, -1.5), (1.5, 1.5), (-1.5, -1.5)):
        box((x, y, 0.95), (0.12, 0.12, 0.14), "dark"); beacon((x, y, 1.04), "glow", 0.04)

def h_depot(n):
    plinth(n)
    box((-0.15, 0.1, 0.32), (1.3, 1.2, 0.5), "olive")
    box((-0.15, 0.1, 0.6), (1.38, 1.28, 0.06), "dark")
    box((-0.15, 0.1, 0.62), (1.3, 0.05, 0.08), "team")
    box((-0.15, -0.5, 0.3), (0.8, 0.04, 0.42), "dark")
    for k in range(4): box((-0.15, -0.52, 0.14 + k * 0.1), (0.76, 0.02, 0.02), "armor", bevel=0.3)
    # Cargo containers
    for i, (x, y, z, c) in enumerate(((0.62, -0.55, 0.16, "team"), (0.62, -0.1, 0.16, "olive"), (0.62, -0.32, 0.38, "hull"))):
        box((x, y, z), (0.3, 0.4, 0.22), c)
    # Fuel tanks
    for y in (0.45, 0.72): cyl((0.65, y, 0.3), 0.13, 0.5, "hull")
    # Loading crane
    strut((-0.75, -0.6, 0.06), (-0.75, -0.6, 0.95), 0.03, "hazard")
    strut((-0.75, -0.6, 0.93), (0.1, -0.75, 0.93), 0.025, "hazard")
    strut((0.05, -0.75, 0.93), (0.05, -0.75, 0.6), 0.006, "dark")
    beacon((-0.75, -0.6, 0.99))
    for i in range(3): box((0.28, -0.25 + i * 0.3, 0.45), (0.02, 0.14, 0.06), "glow", bevel=0)

def h_infantry(n):
    plinth(n)
    # Barracks: two long quonset-style halls on a base
    for x in (-0.55, 0.55):
        box((x, 0.1, 0.2), (0.85, 2.3, 0.28), "armor")
        cyl((x, 0.1, 0.34), 0.42, 2.25, "olive", rot=(math.pi / 2, 0, 0), verts=40)
        box((x, -1.02, 0.32), (0.5, 0.05, 0.5), "dark")
        box((x, -1.05, 0.62), (0.56, 0.04, 0.06), "hazard", bevel=0.3)
        for i in range(4): box((x + 0.43, -0.6 + i * 0.4, 0.38), (0.02, 0.18, 0.08), "glow", bevel=0)
        box((x, 0.1, 0.77), (0.1, 2.26, 0.04), "team")
    box((0, 0.1, 0.5), (0.3, 1.6, 0.6), "hull")
    # Sandbag wall and flag
    for i in range(6): sph((-1.1 + i * 0.44, -1.32, 0.1), (0.2, 0.09, 0.07), "olive")
    strut((1.2, -1.2, 0.06), (1.2, -1.2, 1.4), 0.018, "dark")
    box((1.2, -1.36, 1.28), (0.02, 0.3, 0.18), "team", bevel=0)
    beacon((1.2, -1.2, 1.42))
    strut((0, 0.8, 0.8), (0, 0.8, 1.4), 0.012, "dark")

def h_heavy(n):
    plinth(n)
    box((0, 0.15, 0.55), (2.5, 2.3, 1.0), "hull")
    box((0, 0.15, 1.08), (2.58, 2.38, 0.07), "dark")
    box((0, 0.15, 1.1), (2.5, 0.06, 0.1), "team")
    for x in (-0.62, 0.62):
        box((x, -1.0, 0.45), (1.0, 0.05, 0.78), "dark")
        for k in range(7): box((x, -1.03, 0.12 + k * 0.1), (0.96, 0.02, 0.02), "armor", bevel=0.3)
        box((x, -1.02, 0.88), (1.1, 0.06, 0.07), "hazard", bevel=0.3)
    # Gantry crane over the yard
    for x in (-1.3, 1.3): strut((x, -1.35, 0.06), (x, -1.35, 1.35), 0.04, "hazard")
    strut((-1.35, -1.35, 1.35), (1.35, -1.35, 1.35), 0.045, "hazard")
    box((0.3, -1.35, 1.28), (0.18, 0.14, 0.1), "dark")
    # Exhaust stacks
    for i in range(3): cyl((-0.9 + i * 0.25, 1.05, 1.35), 0.07, 0.5, "dark")
    for i in range(5): box((1.26, -0.4 + i * 0.3, 0.8), (0.02, 0.16, 0.07), "glow", bevel=0)
    beacon((1.3, -1.35, 1.42))

def h_air(n):
    plinth(n, 0.05)
    cyl((0.25, -0.25, 0.1), 1.1, 0.1, "concrete", verts=8)
    torus((0.25, -0.25, 0.16), 0.85, 0.02, "glow")
    box((0.25, -0.25, 0.155), (0.5, 0.08, 0.01), "team", bevel=0)
    for a in range(8):
        x, y = 0.25 + math.cos(a * math.pi / 4) * 1.05, -0.25 + math.sin(a * math.pi / 4) * 1.05
        beacon((x, y, 0.17), "glow", 0.025)
    # Control tower in the back corner
    box((-1.0, 1.0, 0.5), (0.5, 0.5, 0.9), "hull")
    box((-1.0, 1.0, 1.05), (0.7, 0.7, 0.22), "glass")
    box((-1.0, 1.0, 1.2), (0.76, 0.76, 0.06), "dark")
    box((-1.0, 1.0, 0.98), (0.72, 0.72, 0.05), "team")
    strut((-1.0, 1.0, 1.22), (-1.0, 1.0, 1.65), 0.015, "dark"); beacon((-1.0, 1.0, 1.67))
    cyl((-1.0, 0.0, 0.3), 0.25, 0.5, "hull"); cyl((0.0, 1.0, 0.3), 0.25, 0.5, "hull")
    for x in (-0.25, 0.25): box((1.25, x - 0.4, 0.2), (0.28, 0.28, 0.3), "olive")

def h_research(n):
    plinth(n)
    box((0, 0.2, 0.4), (2.2, 1.9, 0.7), "hull")
    box((0, 0.2, 0.77), (2.28, 1.98, 0.05), "dark")
    box((0, -0.76, 0.6), (2.2, 0.04, 0.08), "team")
    for i in range(6): box((-0.9 + i * 0.36, -0.77, 0.42), (0.2, 0.02, 0.1), "glow", bevel=0)
    sph((-0.35, 0.35, 0.8), (0.7, 0.7, 0.6), "glass")
    torus((-0.35, 0.35, 0.82), 0.7, 0.03, "dark")
    cyl((0.75, 0.6, 1.0), 0.06, 0.4, "dark")
    sph((0.75, 0.6, 1.25), (0.38, 0.38, 0.1), "hull", rot=(0.6, 0, -0.7))
    for i in range(3): strut((0.6 + i * 0.15, -0.3, 0.8), (0.6 + i * 0.15, -0.3, 1.3 + i * 0.1), 0.01, "dark")
    beacon((0.9, -0.3, 1.52))
    box((0.85, -1.0, 0.18), (0.4, 0.3, 0.24), "olive")

def h_tower(n):
    plinth(n)
    hexp((0, 0, 0.25), 0.7, 0.4, "armor")
    hexp((0, 0, 0.5), 0.55, 0.12, "dark")
    cyl((0, 0, 1.0), 0.22, 1.0, "hull")
    cyl((0, 0, 1.2), 0.24, 0.06, "team")
    box((0, 0, 1.62), (0.6, 0.55, 0.3), "armor")
    box((0, -0.28, 1.62), (0.4, 0.02, 0.08), "glow", bevel=0)
    for x in (-0.12, 0.12): cyl((x, -0.65, 1.62), 0.045, 0.6, "dark", rot=(math.pi / 2, 0, 0), verts=12)
    sph((0.22, 0.15, 1.85), (0.12, 0.12, 0.04), "dark")
    beacon((-0.2, 0.2, 1.82))
    for a in range(6): sph((math.cos(a) * 0.75, math.sin(a) * 0.75, 0.1), (0.14, 0.08, 0.06), "olive", rot=(0, 0, a + math.pi / 2))

def h_forward(n):
    plinth(n)
    box((0, 0.1, 0.25), (1.4, 1.2, 0.38), "concrete")
    box((0, -0.5, 0.3), (0.9, 0.04, 0.08), "dark")
    box((0, 0.1, 0.46), (1.44, 1.24, 0.05), "armor")
    box((0, -0.51, 0.4), (1.42, 0.03, 0.06), "team")
    for i in range(7): sph((-0.75 + i * 0.25, -0.75, 0.08), (0.13, 0.07, 0.06), "olive")
    # Repair arm and beacon mast
    strut((0.55, 0.45, 0.48), (0.55, 0.45, 1.15), 0.03, "hazard")
    strut((0.55, 0.45, 1.12), (0.05, -0.2, 0.95), 0.025, "hazard")
    box((0.05, -0.2, 0.9), (0.08, 0.08, 0.08), "dark")
    strut((-0.5, 0.5, 0.48), (-0.5, 0.5, 1.7), 0.02, "dark")
    beacon((-0.5, 0.5, 1.72), "glow", 0.06)
    box((-0.2, 0.3, 0.6), (0.4, 0.3, 0.25), "olive")

# ---------------------------------------------------------------- Lattice
def ring(z, R_, m="chrome", tilt=0.0, w=0.025):
    torus((0, 0, z), R_, w, m, rot=(tilt, 0, 0))

def m_hq(n):
    hexp((0, 0, 0.08), 1.95, 0.16, "obsidian")
    hexp((0, 0, 0.25), 1.6, 0.2, "gunmetal")
    hexp((0, 0, 0.25), 1.62, 0.05, "teamglow")
    hexp((0, 0, 0.45), 1.2, 0.22, "obsidian")
    for a in range(6):
        x, y = math.cos(a * math.pi / 3) * 1.45, math.sin(a * math.pi / 3) * 1.45
        hexp((x, y, 0.55), 0.14, 0.7, "obsidian", r2=0.06)
        sph((x, y, 0.93), 0.04, "cyan")
    hexp((0, 0, 1.3), 0.45, 1.6, "obsidian", r2=0.18)
    for z in (0.8, 1.2, 1.6): hexp((0, 0, z), 0.47 - (z - 0.8) * 0.33, 0.03, "cyan")
    sph((0, 0, 2.35), 0.22, "cyan"); LIGHTS.append(Vector((0, 0, 2.35)))
    ring(2.35, 0.5, tilt=0.35); ring(2.35, 0.65, tilt=-0.5, w=0.02)
    ring(2.0, 0.8, "teamglow", w=0.015)

def m_depot(n):
    hexp((0, 0, 0.06), 0.95, 0.12, "obsidian")
    hexp((0, 0, 0.06), 0.97, 0.04, "teamglow")
    cyl((0, 0, 0.42), 0.5, 0.55, "gunmetal", r2=0.62)
    cyl((0, 0, 0.69), 0.46, 0.03, "molten")    # molten surface
    torus((0, 0, 0.7), 0.6, 0.04, "chrome")
    for a in range(3):
        x, y = math.cos(a * 2.1) * 0.8, math.sin(a * 2.1) * 0.8
        strut((x, y, 0.12), (x * 0.6, y * 0.6, 0.65), 0.04, "chrome")
        hexp((x, y, 0.25), 0.12, 0.25, "obsidian")
    LIGHTS.append(Vector((0, 0, 0.72)))

def m_infantry(n):
    hexp((0, 0, 0.07), 1.45, 0.14, "obsidian")
    hexp((0, 0, 0.07), 1.47, 0.04, "teamglow")
    box((0, 0, 0.3), (1.6, 0.6, 0.18), "gunmetal")
    box((0, 0, 0.4), (1.5, 0.4, 0.02), "cyan", bevel=0)
    for x in (-0.6, 0.6):
        hexp((x, 0.6, 0.45), 0.25, 0.75, "obsidian")
        strut((x, 0.6, 0.8), (x * 0.4, 0.05, 0.75), 0.04, "chrome")
        strut((x * 0.4, 0.05, 0.75), (x * 0.4, 0.0, 0.5), 0.03, "chrome")
        sph((x * 0.4, 0.0, 0.48), 0.04, "cyan")
    hexp((0, -0.75, 0.4), 0.3, 0.55, "obsidian", r2=0.15)
    sph((0, -0.75, 0.75), 0.07, "cyan"); LIGHTS.append(Vector((0, -0.75, 0.75)))

def m_heavy(n):
    hexp((0, 0, 0.08), 1.45, 0.16, "obsidian")
    box((0, 0.15, 0.6), (1.9, 1.6, 0.9), "gunmetal")
    box((0, 0.15, 1.08), (2.0, 1.7, 0.08), "obsidian")
    box((0, -0.66, 0.45), (1.0, 0.04, 0.55), "obsidian")
    box((0, -0.68, 0.45), (0.8, 0.02, 0.38), "cyan", bevel=0)   # forge mouth
    box((0, 0.15, 0.86), (1.92, 1.62, 0.05), "teamglow")
    for x in (-0.6, 0.6):
        hexp((x, 0.4, 1.4), 0.22, 0.6, "obsidian", r2=0.12)
        sph((x, 0.4, 1.74), 0.05, "cyan"); LIGHTS.append(Vector((x, 0.4, 1.74)))
    strut((0.95, -0.9, 0.16), (0.95, -0.9, 1.0), 0.05, "chrome")
    box((0.95, -0.9, 1.05), (0.35, 0.35, 0.12), "obsidian")

def m_air(n):
    hexp((0, 0, 0.07), 1.4, 0.14, "obsidian")
    hexp((0, 0, 0.07), 1.42, 0.04, "teamglow")
    hexp((0, 0, 1.2), 0.32, 2.2, "obsidian", r2=0.06)
    for z, R_ in ((0.6, 0.9), (1.1, 0.72), (1.6, 0.52), (2.0, 0.35)):
        ring(z, R_, w=0.03); hexp((0, 0, z), R_ * 0.4, 0.03, "cyan")
    for a in range(3):
        x, y = math.cos(a * 2.1) * 1.1, math.sin(a * 2.1) * 1.1
        hexp((x, y, 0.3), 0.2, 0.3, "gunmetal"); sph((x, y, 0.5), 0.05, "cyan")
    sph((0, 0, 2.35), 0.07, "cyan"); LIGHTS.append(Vector((0, 0, 2.35)))

def m_research(n):
    hexp((0, 0, 0.07), 1.45, 0.14, "obsidian")
    hexp((0, 0, 0.07), 1.47, 0.04, "teamglow")
    random.seed(4)
    for i in range(7):
        a = i * 2 * math.pi / 7 + 0.3; r = 0.9 if i else 0
        x, y = math.cos(a) * r, math.sin(a) * r; h = 0.6 + random.random() * 0.8 if i else 1.7
        hexp((x, y, 0.15 + h / 2), 0.16 if i else 0.25, h, "obsidian", r2=0.03)
        sph((x, y, 0.2 + h), 0.05, "cyan")
        if i: strut((x, y, 0.3 + h * 0.4), (0, 0, 0.9), 0.008, "cyan")
    LIGHTS.append(Vector((0, 0, 1.9)))

def m_tower(n):
    hexp((0, 0, 0.08), 0.9, 0.16, "obsidian")
    hexp((0, 0, 0.08), 0.92, 0.04, "teamglow")
    hexp((0, 0, 1.0), 0.35, 1.7, "obsidian", r2=0.12)
    for z in (0.5, 0.9, 1.3): hexp((0, 0, z), 0.33 - (z - 0.5) * 0.25, 0.025, "cyan")
    sph((0, 0, 2.05), 0.16, "cyan"); LIGHTS.append(Vector((0, 0, 2.05)))
    ring(2.05, 0.32, tilt=0.4); ring(2.05, 0.4, tilt=-0.6, w=0.018)

def m_forward(n):
    hexp((0, 0, 0.06), 0.85, 0.12, "obsidian")
    hexp((0, 0, 0.06), 0.87, 0.04, "teamglow")
    for a in range(3):
        x, y = math.cos(a * 2.1) * 0.6, math.sin(a * 2.1) * 0.6
        strut((x, y, 0.12), (0, 0, 1.6), 0.05, "gunmetal")
    hexp((0, 0, 1.6), 0.12, 0.2, "obsidian")
    sph((0, 0, 2.0), 0.13, "cyan"); LIGHTS.append(Vector((0, 0, 2.0)))
    ring(2.0, 0.42, tilt=0.25); ring(1.2, 0.55, "teamglow", w=0.02)

# ---------------------------------------------------------------- Brood
def ribs(cx, cy, z0, R_, count, height, m="bone", lean=0.35):
    for i in range(count):
        a = i * 2 * math.pi / count
        b = Vector((cx + math.cos(a) * R_, cy + math.sin(a) * R_, z0))
        t = Vector((cx + math.cos(a) * R_ * 0.35, cy + math.sin(a) * R_ * 0.35, z0 + height))
        horn(b, t, 0.05, m, bend=(math.cos(a) * lean, math.sin(a) * lean, height * 0.25))

def a_hq(n):
    creep(n)
    # A great ridged mound filling the footprint, with carapace shields and a glowing heart-sac in front.
    blob([((0, 0.15, 0.35), 1.55, (1.15, 1.1, 0.62)), ((-0.6, 0.6, 0.75), 0.95, None), ((0.55, 0.45, 0.6), 0.85, None),
          ((-0.2, -0.5, 0.3), 0.9, None)], "chitin", displace=0.12)
    for a, (x, y, z) in enumerate(((-0.55, 0.65, 1.32), (0.45, 0.55, 1.1), (-0.95, 0.0, 0.95), (0.05, 0.15, 1.42))):
        organ((x, y, z), (0.36, 0.22, 0.06), "teamchitin", rot=(0.5, 0.2, a * 0.9))
    organ((0.35, -0.85, 0.55), (0.42, 0.36, 0.48), "flesh")
    sph((0.35, -0.92, 0.6), (0.24, 0.2, 0.3), "bio"); LIGHTS.append(Vector((0.35, -0.95, 0.65)))
    ribs(0.35, -0.85, 0.05, 0.55, 6, 0.9, lean=0.1)
    for a in range(5):
        x, y = math.cos(a * 1.26 + 0.3), math.sin(a * 1.26 + 0.3)
        horn((x * 1.2, y * 1.2 + 0.15, 0.3), (x * 0.55, y * 0.55 + 0.15, 1.9 + (a % 2) * 0.45), 0.14, "bone", bend=(x * 0.35, y * 0.35, 0.2))
    for a in range(12):
        x, y = math.cos(a * 0.55), math.sin(a * 0.55)
        sph((x * 1.75, y * 1.75, 0.04), 0.05, "bio")

def a_depot(n):
    creep(n)
    blob([((0, 0, 0.35), 0.62, (1, 1, 0.9)), ((0.2, -0.2, 0.15), 0.45, None)], "flesh", displace=0.06)
    organ((-0.1, 0.1, 0.72), (0.3, 0.26, 0.08), "teamchitin", rot=(0.2, 0.1, 0))
    for a in range(5):
        x, y = math.cos(a * 1.25) * 0.75, math.sin(a * 1.25) * 0.75
        horn((x * 0.4, y * 0.4, 0.5), (x, y, 0.0), 0.06, "chitin", bend=(0, 0, 0.25))
    for p in ((0.25, -0.3, 0.62), (-0.3, -0.1, 0.55)): sph(p, 0.07, "bio")
    LIGHTS.append(Vector((0.25, -0.3, 0.62)))

def a_infantry(n):
    creep(n)
    blob([((0, 0.2, 0.35), 1.1, (1.1, 1.0, 0.6)), ((0.4, 0.5, 0.6), 0.6, None)], "chitin", displace=0.07)
    sph((0.0, -0.55, 0.32), (0.45, 0.3, 0.32), "hole")          # cavern mouth
    ribs(0, -0.55, 0.0, 0.55, 7, 0.7, lean=0.15)
    organ((0.3, 0.6, 0.98), (0.34, 0.26, 0.07), "teamchitin", rot=(0.2, -0.2, 0.5))
    for a in range(6): sph((math.cos(a) * 0.9, 0.2 + math.sin(a) * 0.8, 0.55), 0.05, "bio")
    LIGHTS.append(Vector((0, -0.55, 0.35)))

def a_heavy(n):
    creep(n)
    random.seed(7)
    for i in range(7):
        a = i * 0.9; r = 0.25 + (i % 3) * 0.32
        x, y = math.cos(a) * r, math.sin(a) * r; s = 0.25 + random.random() * 0.15
        organ((x, y, s * 1.2), (s, s, s * 1.4), "flesh")
        if i == 0: organ((x, y, s * 2.3), (s * 0.8, s * 0.6, s * 0.18), "teamchitin")
        sph((x, y, s * 1.2), (s * 0.5, s * 0.5, s * 0.8), "bio")
    ribs(0, 0, 0.0, 1.1, 6, 1.0)
    LIGHTS.append(Vector((0, 0, 0.5)))

def a_air(n):
    creep(n)
    blob([((0, 0, 0.25), 0.7, (1, 1, 0.5))], "chitin", displace=0.05)
    horn((0, 0, 0.3), (0.1, -0.1, 2.0), 0.16, "chitin", bend=(0.15, 0, 0))
    for a in range(6):   # petal membranes at the top
        x, y = math.cos(a * 1.05), math.sin(a * 1.05)
        organ((x * 0.35 + 0.1, y * 0.35 - 0.1, 2.05), (0.4, 0.14, 0.04), "teamchitin" if a % 2 else "flesh", rot=(0.5 * y, -0.5 * x, a * 1.05))
    sph((0.1, -0.1, 2.08), 0.13, "bio"); LIGHTS.append(Vector((0.1, -0.1, 2.08)))

def a_research(n):
    creep(n)
    blob([((0, 0, 0.45), 0.95, (1.1, 1.0, 0.8)), ((-0.3, 0.3, 0.7), 0.6, None), ((0.4, 0.1, 0.65), 0.55, None)], "flesh", displace=0.14)
    organ((0, 0.4, 1.0), (0.3, 0.22, 0.06), "teamchitin", rot=(0.3, 0, 0.3))
    for p in ((0.3, -0.4, 0.95), (-0.4, -0.1, 1.05), (0.5, 0.4, 0.9), (0.0, 0.0, 1.2)): sph(p, 0.07, "bio")
    LIGHTS.append(Vector((0.0, 0.0, 1.2)))
    ribs(0, 0, 0.0, 1.2, 5, 0.6, lean=0.2)

def a_tower(n):
    creep(n)
    blob([((0, 0, 0.2), 0.6, (1, 1, 0.6))], "chitin", displace=0.05)
    horn((0, 0, 0.2), (0.1, 0.1, 2.3), 0.22, "chitin", bend=(0.2, -0.1, 0))
    random.seed(3)
    for i in range(10):
        z = 0.5 + i * 0.17; a = i * 2.3
        b = Vector((0.1 * z / 2.3 + math.cos(a) * 0.12, 0.1 * z / 2.3 + math.sin(a) * 0.12, z))
        horn(b, b + Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, 0.18)), 0.035, "bone", segs=4)
    sph((0.1, 0.1, 2.3), 0.09, "bio"); LIGHTS.append(Vector((0.1, 0.1, 2.3)))
    organ((0, 0, 0.62), (0.3, 0.3, 0.07), "teamchitin")

def a_forward(n):
    creep(n)
    for a in range(7):
        x, y = math.cos(a * 0.9), math.sin(a * 0.9)
        horn((0, 0, 0.2), (x * 0.85, y * 0.85, 0.02), 0.07, "chitin", bend=(0, 0, 0.15))
    horn((0, 0, 0.1), (0, 0, 1.4), 0.12, "chitin", bend=(0.1, 0.05, 0))
    organ((0, 0, 1.55), (0.22, 0.22, 0.28), "chitin")
    organ((0, 0, 1.3), (0.2, 0.2, 0.05), "teamchitin")
    sph((0, 0, 1.55), 0.12, "bio"); LIGHTS.append(Vector((0, 0, 1.6)))

BUILDERS = {k: v for k, v in globals().items() if k[:2] in ("h_", "m_", "a_") and callable(v)}

# ---------------------------------------------------------------- render
def render_building(bid):
    d = DEFS[bid]; n = d["size"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"; prefs.get_devices()
    for dv in prefs.devices: dv.use = True
    sc.cycles.device = "GPU"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
    make_materials(); LIGHTS.clear()
    BUILDERS[bid](n)
    geo = [o for o in sc.objects if o.type == "MESH"]

    # Shadow catcher ground
    bpy.ops.mesh.primitive_plane_add(size=n * 4, location=(0, 0, 0)); ground = bpy.context.object
    ground.is_shadow_catcher = True

    w_pt = 64 * n; h_pt = 32 * n + HEADROOM.get(d["kind"], 100)
    cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = w_pt / PX; cam_data.clip_end = 200
    cam = bpy.data.objects.new("cam", cam_data); sc.collection.objects.link(cam); sc.camera = cam
    view = (U * math.cos(ELEV) + Vector((0, 0, -math.sin(ELEV)))).normalized()
    cam.rotation_euler = view.to_track_quat("-Z", "Y").to_euler()
    up = cam.rotation_euler.to_matrix() @ Vector((0, 1, 0))
    cam.location = -view * 60 + up * ((h_pt / 2 - 16 * n) / PX)
    sc.render.resolution_x = int(w_pt * SCALE); sc.render.resolution_y = int(h_pt * SCALE)

    def sun(direction, energy, color, angle=3):
        ld = bpy.data.lights.new("sun", "SUN"); ld.energy = energy; ld.color = color; ld.angle = math.radians(angle)
        o = bpy.data.objects.new("sun", ld); sc.collection.objects.link(o)
        o.rotation_euler = Vector(direction).normalized().to_track_quat("-Z", "Y").to_euler()
        return o
    suns = [sun(-(-R + U) * 0.55 + Vector((0, 0, -1)), 4.5, (1.0, 0.93, 0.82)),
            sun((-R + U) * 0.6 + Vector((0, 0, -0.5)), 0.9, (0.6, 0.72, 1.0), 10)]
    wd = bpy.data.worlds.new("w"); sc.world = wd; wd.use_nodes = True
    bg = wd.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.45, 0.5, 0.6, 1); bg.inputs["Strength"].default_value = 0.7
    sc.view_settings.view_transform = "AgX"
    try: sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception: pass
    sc.cycles.samples = 96; sc.cycles.use_denoising = True
    sc.render.filepath = os.path.join(OUT, f"b3d_{bid}.png")
    bpy.ops.render.render(write_still=True)

    # Team mask: team materials white, everything else black; no shadow catcher.
    ground.hide_render = True
    for s in suns: s.hide_render = True
    bg.inputs["Strength"].default_value = 0
    white = bpy.data.materials.new("w"); white.use_nodes = True
    black = bpy.data.materials.new("k"); black.use_nodes = True
    for mm, c in ((white, 1.0), (black, 0.0)):
        nt = mm.node_tree; em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (c, c, c, 1)
        nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    for o in geo:
        for i, m in enumerate(o.data.materials):
            o.data.materials[i] = white if m.get("team") else black
    sc.view_settings.view_transform = "Raw"; sc.view_settings.look = "None"   # mask values are data
    sc.cycles.samples = 8; sc.cycles.use_denoising = False
    sc.render.filepath = os.path.join(OUT, f"b3d_{bid}m.png")
    bpy.ops.render.render(write_still=True)

    # Metadata in points relative to the footprint centre (scene y up).
    bpy.context.view_layer.update()
    def to_pt(p):
        v = world_to_camera_view(sc, cam, Vector(p))
        return [round((v.x - 0.5) * w_pt, 1), round(v.y * h_pt - 16 * n, 1)]
    top = 0.0
    for o in geo:
        for c in o.bound_box:
            top = max(top, to_pt(o.matrix_world @ Vector(c))[1])
    json.dump({"height": round(top, 1), "lights": [to_pt(l) for l in LIGHTS]}, open(os.path.join(OUT, f"b3d_{bid}.json"), "w"))
    print("BUILDING", bid, "height", round(top, 1), "lights", len(LIGHTS))

if __name__ == "__main__":
    for bid in (args or list(DEFS)):
        render_building(bid)
