# Style test renders for Meridian: one Concord building + one Concord soldier, in three looks.
# Usage: Blender -b -P scene.py -- <style: real|stylised|toy> <subject: hub|marine> <out.png>
import bpy, bmesh, sys, math
from mathutils import Vector

style, subject, out = sys.argv[sys.argv.index("--") + 1:][:3]
REAL, STYL, TOY = style == "real", style == "stylised", style == "toy"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---------------------------------------------------------------- materials
def mix_rgb(nt, fac, a, b):
    m = nt.nodes.new("ShaderNodeMix"); m.data_type = "RGBA"; m.blend_type = "MIX"
    ins = {s.identifier: s for s in m.inputs}
    for k, v in (("Factor_Float", fac), ("A_Color", a), ("B_Color", b)):
        if isinstance(v, bpy.types.NodeSocket): nt.links.new(v, ins[k])
        else: ins[k].default_value = v
    return {s.identifier: s for s in m.outputs}["Result_Color"]

def ramp(nt, inp, lo, hi):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = lo; r.color_ramp.elements[1].position = hi
    nt.links.new(inp, r.inputs[0]); return r.outputs[0]

def math_node(nt, op, a, b=None):
    n = nt.nodes.new("ShaderNodeMath"); n.operation = op
    for i, v in enumerate((a, b)):
        if v is None: continue
        if isinstance(v, bpy.types.NodeSocket): nt.links.new(v, n.inputs[i])
        else: n.inputs[i].default_value = v
    return n.outputs[0]

def panel_seams(nt, tc, sc):
    """Distance to the nearest straight plating seam: an axis-aligned grid, ignoring the axis a face points along."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sp = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Object"], sp.inputs[0])
    sn = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(geo.outputs["Normal"], sn.inputs[0])
    best = None
    for i, (k, off) in enumerate(((1.0, 0.37), (0.8, 0.11), (1.6, 0.53))):   # x, y, z spacing
        f = math_node(nt, "FRACT", math_node(nt, "MULTIPLY_ADD", sp.outputs[i], sc * k) if False else math_node(nt, "ADD", math_node(nt, "MULTIPLY", sp.outputs[i], sc * k), off))
        d = math_node(nt, "SUBTRACT", 0.5, math_node(nt, "ABSOLUTE", math_node(nt, "SUBTRACT", f, 0.5)))
        d = math_node(nt, "ADD", d, math_node(nt, "MULTIPLY", math_node(nt, "ABSOLUTE", sn.outputs[i]), 2.0))
        best = d if best is None else math_node(nt, "MINIMUM", best, d)
    return best

def mat(name, color, metal=0.0, rough=0.5, emit=0.0, panel=1.0, scale=1.0, wear=1.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    col = (*color, 1)
    if TOY:
        b.inputs["Base Color"].default_value = col
        b.inputs["Roughness"].default_value = 0.35
        b.inputs["Coat Weight"].default_value = 0.4
    elif STYL:
        # Hand-painted feel: lighter towards the top of each part, dark in crevices.
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Generated"], sep.inputs[0])
        top = tuple(min(1, c * 1.35 + 0.06) for c in color) + (1,)
        bot = tuple(c * 0.6 for c in color) + (1,)
        grad = mix_rgb(nt, sep.outputs["Z"], bot, top)
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.4
        dark = mix_rgb(nt, ramp(nt, ao.outputs["AO"], 0.2, 0.9), tuple(c * 0.3 for c in color) + (1,), grad)
        nt.links.new(dark, b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.8
        b.inputs["Metallic"].default_value = 0.0
    else:
        # Realistic PBR: grime in crevices, worn bare-metal edges, panel seams, roughness variation.
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.5 * scale
        nz.inputs["Detail"].default_value = 10; nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.35 / scale
        edge = nt.nodes.new("ShaderNodeAmbientOcclusion"); edge.inside = True; edge.inputs["Distance"].default_value = 0.04 / scale
        grime = ramp(nt, ao.outputs["AO"], 0.15, 0.85)
        dirty = mix_rgb(nt, grime, (color[0] * 0.25, color[1] * 0.22, color[2] * 0.18, 1), col)
        blotch = ramp(nt, nz.outputs["Fac"], 0.45, 0.75)
        dirty = mix_rgb(nt, blotch, dirty, tuple(c * 0.7 for c in color) + (1,))
        edgemask = ramp(nt, edge.outputs["AO"], 0.55, 0.75)   # low inside-AO = convex edge
        inv = nt.nodes.new("ShaderNodeInvert"); nt.links.new(edgemask, inv.inputs["Color"])
        wearmask = nt.nodes.new("ShaderNodeMath"); wearmask.operation = "MULTIPLY"
        nt.links.new(inv.outputs[0], wearmask.inputs[0]); wearmask.inputs[1].default_value = wear * (0 if emit else 0.85)
        base = mix_rgb(nt, wearmask.outputs[0], dirty, (0.55, 0.55, 0.57, 1))
        nt.links.new(base, b.inputs["Base Color"])
        mt = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(wearmask.outputs[0], mt.inputs["Value"])
        mt.inputs["To Min"].default_value = metal; mt.inputs["To Max"].default_value = 1
        nt.links.new(mt.outputs["Result"], b.inputs["Metallic"])
        rr = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(nz.outputs["Fac"], rr.inputs["Value"])
        rr.inputs["To Min"].default_value = rough - 0.15; rr.inputs["To Max"].default_value = rough + 0.2
        nt.links.new(rr.outputs["Result"], b.inputs["Roughness"])
        if panel > 0:
            seam = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(panel_seams(nt, tc, 1.25 * scale * panel), seam.inputs["Value"])
            seam.inputs["From Max"].default_value = 0.03
            fine = nt.nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value = 60 * scale
            nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
            add = nt.nodes.new("ShaderNodeMath"); add.operation = "MULTIPLY_ADD"
            nt.links.new(fine.outputs["Fac"], add.inputs[0]); add.inputs[1].default_value = 0.08
            nt.links.new(seam.outputs["Result"], add.inputs[2])
            bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6
            bump.inputs["Distance"].default_value = 0.02 / scale
            nt.links.new(add.outputs[0], bump.inputs["Height"]); nt.links.new(bump.outputs[0], b.inputs["Normal"])
    if emit:
        b.inputs["Emission Color"].default_value = col
        b.inputs["Emission Strength"].default_value = emit
    return m

if REAL:
    P = dict(hull=(0.16, 0.155, 0.14), armor=(0.075, 0.08, 0.085), dark=(0.025, 0.026, 0.03), team=(0.012, 0.07, 0.42),
             hazard=(0.7, 0.42, 0.02), concrete=(0.11, 0.105, 0.095), glow=(1.0, 0.55, 0.2), visor=(1.0, 0.4, 0.08),
             red=(1, 0.08, 0.04), ground=(0.075, 0.06, 0.045))
elif STYL:
    P = dict(hull=(0.62, 0.58, 0.48), armor=(0.45, 0.47, 0.5), dark=(0.16, 0.17, 0.2), team=(0.08, 0.35, 0.95),
             hazard=(1.0, 0.75, 0.1), concrete=(0.52, 0.5, 0.46), glow=(1.0, 0.8, 0.35), visor=(0.3, 0.9, 1.0),
             red=(1, 0.15, 0.1), ground=(0.28, 0.45, 0.2))
else:
    P = dict(hull=(0.5, 0.48, 0.42), armor=(0.22, 0.26, 0.32), dark=(0.06, 0.065, 0.08), team=(0.03, 0.16, 0.7),
             hazard=(0.9, 0.55, 0.05), concrete=(0.3, 0.28, 0.25), glow=(1.0, 0.75, 0.35), visor=(0.2, 0.7, 1.0),
             red=(1, 0.15, 0.1), ground=(0.18, 0.32, 0.14))
SC = 3.0 if subject == "marine" else 1.0
M = {k: mat(k, v, scale=SC) for k, v in P.items()}
M["hull"] = mat("hull", P["hull"], metal=0.2, rough=0.45, scale=SC)
M["armor"] = mat("armor", P["armor"], metal=0.5, rough=0.4, scale=SC)
M["dark"] = mat("dark", P["dark"], metal=0.7, rough=0.4, panel=0.7, scale=SC)
M["team"] = mat("team", P["team"], metal=0.3, rough=0.35, scale=SC)
M["concrete"] = mat("concrete", P["concrete"], rough=0.85, panel=0.6, wear=0.2, scale=SC)
M["glow"] = mat("glow", P["glow"], emit=2.5 if REAL else 3, panel=0)
M["visor"] = mat("visor", P["visor"], emit=8 if REAL else 3, panel=0)
M["red"] = mat("red", P["red"], emit=25, panel=0)
M["ground"] = mat("ground", P["ground"], rough=0.95, panel=0, wear=0, scale=0.3)

# Hazard stripes (yellow/black diagonal) for realistic + stylised.
def hazard_mat():
    m = bpy.data.materials.new("hazstripe"); m.use_nodes = True; nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord"); w = nt.nodes.new("ShaderNodeTexWave")
    w.inputs["Scale"].default_value = 3.0; w.bands_direction = "DIAGONAL"; w.wave_profile = "SAW"
    nt.links.new(tc.outputs["Object"], w.inputs["Vector"])
    stripe = ramp(nt, w.outputs["Fac"], 0.49, 0.51)
    nt.links.new(mix_rgb(nt, stripe, (*P["hazard"], 1), (0.02, 0.02, 0.02, 1)), b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.6
    return m
M["hazstripe"] = hazard_mat() if not TOY else M["hazard"]

# ---------------------------------------------------------------- geometry helpers
BEV = 0.0 if TOY else (0.09 if STYL else 0.035)

def finish(o, m, bevel=1.0, smooth=True, subsurf=0):
    o.data.materials.append(M[m])
    if BEV and bevel:
        bv = o.modifiers.new("bev", "BEVEL"); bv.width = BEV * bevel; bv.segments = 3 if REAL else 2
        bv.limit_method = "ANGLE"; bv.harden_normals = REAL
    if subsurf and not TOY:
        s = o.modifiers.new("sub", "SUBSURF"); s.levels = s.render_levels = subsurf
    if smooth and not TOY:
        bpy.ops.object.shade_auto_smooth() if hasattr(bpy.ops.object, "shade_auto_smooth") else bpy.ops.object.shade_smooth()
    elif TOY:
        bpy.ops.object.shade_flat()
    return o

def box(loc, size, m, rot=(0, 0, 0), bevel=1.0, subsurf=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, m, bevel, subsurf=subsurf)

def cyl(loc, r, h, m, rot=(0, 0, 0), verts=32, bevel=1.0):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=8 if TOY else verts)
    return finish(bpy.context.object, m, bevel)

def sph(loc, scale, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=loc, rotation=rot, segments=10 if TOY else 48, ring_count=6 if TOY else 24)
    o = bpy.context.object; o.scale = scale; bpy.ops.object.transform_apply(scale=True)
    return finish(o, m, bevel=0)

def limb(a, b, w, d, m, subsurf=1):
    """Beveled box spanning points a→b (w×d cross-section)."""
    a, b = Vector(a), Vector(b); v = b - a
    bpy.ops.mesh.primitive_cube_add(size=1, location=(a + b) / 2)
    o = bpy.context.object; o.scale = (w, d, v.length); bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.location = (a + b) / 2
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = v.to_track_quat("Z", "Y")
    return finish(o, m, subsurf=subsurf)

# ---------------------------------------------------------------- subjects
def command_hub():
    box((0, 0, 0.2), (9.4, 9.4, 0.4), "concrete")
    # Hazard trims along the two camera-facing plinth edges
    box((4.62, 0, 0.42), (0.18, 9.0, 0.06), "hazstripe", bevel=0)
    box((0, -4.62, 0.42), (9.0, 0.18, 0.06), "hazstripe", bevel=0)
    # Sloped armor skirt + main block
    box((0, 0, 0.75), (8.0, 8.0, 0.7), "armor")
    box((0, 0, 1.6), (7.4, 7.4, 1.2), "hull")
    box((0, 0, 2.25), (7.6, 7.6, 0.14), "dark")
    # Big hangar door on the front (-y) face
    box((0.6, -3.72, 1.25), (3.2, 0.12, 1.5), "dark")
    for k in range(5): box((0.6, -3.79, 0.65 + k * 0.3), (3.0, 0.04, 0.05), "armor", bevel=0.3)
    box((0.6, -3.76, 2.05), (3.5, 0.14, 0.14), "hazstripe", bevel=0.3)
    # Windows
    for i in range(6):
        box((3.71, -2.8 + i * 1.1, 1.75), (0.06, 0.55, 0.22), "glow", bevel=0)
    for i in range(2):
        box((-2.9 + i * 1.1, -3.71, 1.75), (0.55, 0.06, 0.22), "glow", bevel=0)
    # Upper command block, offset back
    box((-0.9, 0.9, 3.0), (4.8, 4.8, 1.5), "hull")
    box((-0.9, 0.9, 3.05), (4.95, 4.95, 0.28), "team")
    for i in range(4):
        box((1.52, -0.7 + i * 0.9, 3.45), (0.06, 0.5, 0.18), "glow", bevel=0)
        box((-2.3 + i * 0.9, -1.52, 3.45), (0.5, 0.06, 0.18), "glow", bevel=0)
    box((-0.9, 0.9, 3.8), (5.0, 5.0, 0.12), "dark")
    # Bridge tower + antenna + red beacon
    box((-1.4, 1.4, 4.4), (1.9, 1.9, 1.1), "armor")
    box((-1.4, 0.43, 4.55), (1.5, 0.06, 0.3), "glow", bevel=0)
    cyl((-1.4, 1.4, 6.0), 0.06, 2.2, "dark", verts=12)
    for z in (5.4, 5.9): box((-1.4, 1.4, z), (0.55, 0.05, 0.05), "dark", bevel=0)
    sph((-1.4, 1.4, 7.15), (0.12, 0.12, 0.12), "red")
    # Radar dish
    cyl((-2.6, 2.6, 4.05), 0.18, 0.4, "dark")
    sph((-2.6, 2.6, 4.5), (0.7, 0.7, 0.18), "hull", rot=(0.5, 0, -0.8))
    # Landing pad on the main roof
    cyl((2.1, -1.9, 2.36), 1.35, 0.1, "dark", verts=48)
    bpy.ops.mesh.primitive_torus_add(location=(2.1, -1.9, 2.42), major_radius=1.0, minor_radius=0.035)
    finish(bpy.context.object, "glow", bevel=0)
    # Roof vents + pipes along the right wall
    for i in range(3): cyl((2.9, 1.0 + i * 0.85, 2.55), 0.28, 0.5, "armor")
    for z in (0.95, 1.15): cyl((3.95, 0, z), 0.07, 7.2, "dark", rot=(math.pi / 2, 0, 0), verts=16)
    # Corner floodlights
    for x, y in ((3.6, -3.6), (3.6, 3.6), (-3.6, -3.6)):
        box((x, y, 2.5), (0.3, 0.3, 0.35), "dark"); box((x, y, 2.72), (0.22, 0.22, 0.06), "glow", bevel=0)
    return 6.2, (0, 0, 2.2)

def marine():
    sx = 1
    # Legs (armored boots, knee guards)
    for s in (-1, 1):
        hip, knee, ank = (0.2 * s, 0.03 * s, 0.98), (0.24 * s, -0.12 - 0.08 * s, 0.55), (0.24 * s, 0.02 - 0.08 * s, 0.14)
        limb(hip, knee, 0.24, 0.26, "armor")
        limb(knee, ank, 0.27, 0.3, "hull")
        box((knee[0], knee[1] - 0.14, knee[2] + 0.02), (0.22, 0.1, 0.24), "team", subsurf=1)
        box((ank[0], ank[1] - 0.08, 0.08), (0.28, 0.46, 0.16), "dark")
    # Pelvis, torso, chest plate, backpack
    box((0, 0, 1.02), (0.56, 0.36, 0.26), "dark", subsurf=1)
    box((0, 0, 1.42), (0.78, 0.5, 0.62), "hull", subsurf=1)
    box((0, -0.24, 1.5), (0.6, 0.12, 0.42), "armor", subsurf=1)
    box((0, -0.31, 1.32), (0.2, 0.04, 0.12), "glow", bevel=0)
    box((0, 0.36, 1.5), (0.62, 0.32, 0.6), "armor", subsurf=1)
    for s in (-1, 1): cyl((0.2 * s, 0.48, 1.38), 0.08, 0.36, "dark", verts=16)
    # Helmet + visor
    sph((0, -0.04, 1.93), (0.2, 0.22, 0.21), "hull")
    box((0, -0.21, 1.93), (0.28, 0.08, 0.09), "visor", bevel=0.4, subsurf=1)
    box((0, -0.1, 1.79), (0.24, 0.2, 0.12), "dark", subsurf=1)
    # Arms: big team-colour pauldrons, armored forearms, holding a rifle
    for s, elbow, hand in ((1, (0.5, -0.22, 1.32), (0.18, -0.5, 1.3)), (-1, (-0.46, -0.32, 1.38), (-0.04, -0.82, 1.42))):
        sh = (0.5 * s, 0.0, 1.66)
        box((0.55 * s, 0.0, 1.78), (0.36, 0.56, 0.2), "team", rot=(0, 0.45 * s, 0), subsurf=1)
        box((0.66 * s, 0.0, 1.62), (0.1, 0.5, 0.26), "armor", rot=(0, 0.2 * s, 0), subsurf=1)
        limb(sh, elbow, 0.2, 0.2, "dark")
        limb(elbow, hand, 0.25, 0.26, "armor")
        sph(hand, (0.09, 0.09, 0.09), "dark")
    # Gauss rifle
    a, b = Vector((0.22, -0.3, 1.33)), Vector((-0.12, -1.25, 1.5))
    limb(a, b, 0.11, 0.17, "dark", subsurf=0)
    limb(b, b + (b - a).normalized() * 0.35, 0.05, 0.05, "dark", subsurf=0)
    limb((0.08, -0.62, 1.32), (0.1, -0.68, 1.1), 0.08, 0.1, "dark", subsurf=0)
    limb((0.12, -0.45, 1.44), (-0.02, -0.85, 1.52), 0.04, 0.05, "glow", subsurf=0)
    return 2.7, (0, -0.2, 1.1)

ortho, target = command_hub() if subject == "hub" else marine()

# Ground disc
bpy.ops.mesh.primitive_cylinder_add(radius=40, depth=0.1, location=(0, 0, -0.05), vertices=64)
bpy.context.object.data.materials.append(M["ground"])

# ---------------------------------------------------------------- camera + light
bpy.ops.object.empty_add(location=target); tgt = bpy.context.object
d = 40
bpy.ops.object.camera_add(location=(d * 0.62, -d * 0.62, d * 0.68))
cam = bpy.context.object; cam.data.type = "ORTHO"; cam.data.ortho_scale = ortho * 1.75
c = cam.constraints.new("TRACK_TO"); c.target = tgt; c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
sc.camera = cam

bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-30)))
sun = bpy.context.object.data
sun.energy = 4.5 if REAL else 3.2; sun.angle = math.radians(2 if REAL else 8)
sun.color = (1.0, 0.93, 0.82) if REAL else (1, 0.97, 0.92)
if not TOY:   # cool rim from behind
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(70), 0, math.radians(150)))
    rim = bpy.context.object.data; rim.energy = 2.0 if STYL else 1.4; rim.color = (0.6, 0.75, 1.0)

w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.42, 0.52, 0.65, 1) if REAL else ((0.55, 0.65, 0.8, 1) if STYL else (0.85, 0.9, 1.0, 1))
bg.inputs["Strength"].default_value = 0.55 if REAL else (0.8 if STYL else 0.7)

# ---------------------------------------------------------------- render
sc.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"; prefs.get_devices()
for dv in prefs.devices: dv.use = True
sc.cycles.device = "GPU"
sc.cycles.samples = 256 if REAL else 128
sc.cycles.use_denoising = True
sc.render.resolution_x = sc.render.resolution_y = 1024
sc.view_settings.view_transform = "AgX"
try: sc.view_settings.look = "AgX - Medium High Contrast" if REAL else ("AgX - Punchy" if STYL else "None")
except Exception: pass
if STYL:
    sc.render.use_freestyle = True
    sc.render.line_thickness = 1.6
    ls = bpy.context.view_layer.freestyle_settings.linesets[0] if bpy.context.view_layer.freestyle_settings.linesets else bpy.context.view_layer.freestyle_settings.linesets.new("l")
    if ls.linestyle is None: ls.linestyle = bpy.data.linestyles.new("ink")
    ls.linestyle.color = (0.05, 0.04, 0.04)
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("RENDERED", out)
