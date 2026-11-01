# Renders live 3D portraits for rigged units: a head-and-shoulders close-up in 5 head turns x 3 mouth openings,
# each with a team-colour mask, for UnitPortraitView to blend between as the unit looks around and talks.
#
# Usage: Blender -b -P tools/blender/portraits.py -- <unit_id> ...
# Reads  art/rigged/<id>.fbx (and art/anims for soldiers' standing pose).
# Writes Meridian/Portraits3D/p3d_<id>_<look>_<mouth>.jpg and ..._<look>_<mouth>m.jpg, look 0..4 (left..right as
#        the viewer sees it), mouth 0..2 (closed..open).
#
# The head turns on the skeleton's head and neck bones. Talking is a shape key: the lower front of the head (jaw,
# mandibles, grille) hinges down about a pivot behind it, so it follows the head as it turns.
import bpy, sys, os, math
import numpy as np
from mathutils import Vector, Matrix, Euler, Quaternion

sys.path.insert(0, os.path.dirname(__file__))
import unit_render as ur

ids = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.join(ur.ROOT, "Meridian/Portraits3D")
os.makedirs(OUT, exist_ok=True)
PX = 224
LOOKS = (-1, -0.5, 0, 0.5, 1)
MOUTHS = (0, 0.5, 1)

def bone(arm, *names):
    return next((arm.pose.bones[n] for n in names if n in arm.pose.bones), None)

def render_portrait(uid):
    fix = ur.FIX.get(uid, {}); pf = fix.get("portrait", {})
    sc = ur.setup_scene()
    bpy.ops.import_scene.fbx(filepath=ur.rig_path(uid))
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    obj = next(o for o in sc.objects if o.type == "MESH")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    soldier = "mixamorig:Head" in arm.pose.bones
    head = bone(arm, "mixamorig:Head", "head"); neck = bone(arm, "mixamorig:Neck", "neck", "neck.02", "thorax")
    # Stand it up and face it like the sprites: forward is -Y in the standing frame.
    fixm = Euler([math.radians(a) for a in fix.get("rotate", [0, 0, 0])]).to_matrix().to_4x4()
    fwd = Vector(fix.get("forward", [0, -1, 0]))
    yaw = Matrix.Rotation(math.atan2(fwd.x, -fwd.y), 4, "Z")
    to_arm = (fixm @ arm.matrix_world).inverted().to_3x3()
    F = (to_arm @ (yaw.inverted().to_3x3() @ Vector((0, -1, 0)))).normalized()   # whatever the yaw turns to face -Y
    Up = (to_arm @ Vector((0, 0, 1))).normalized(); Lat = F.cross(Up).normalized()
    if soldier:
        rt = ur.Retarget(arm); rt.clip("rifle_idle")
    orient = bpy.data.objects.new("orient", None); sc.collection.objects.link(orient)
    arm.parent = orient; orient.matrix_basis = yaw @ fixm
    if soldier:
        # Retargeting needs the rig at the origin; the standing frame for soldiers is the identity anyway.
        rt.apply("rifle_idle", 0.0)
    bpy.context.view_layer.update()

    # Head vertices (in mesh space) from the head bone's skin weights.
    vg = obj.vertex_groups.get(head.name)
    n = len(obj.data.vertices)
    co = np.empty(n * 3); obj.data.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    w = np.zeros(n)
    if vg:
        gi = vg.index
        for v in obj.data.vertices:
            for g in v.groups:
                if g.group == gi: w[v.index] = g.weight
    hv = co[w > 0.5] if (w > 0.5).sum() > 50 else co[w > 0.1]
    m2a = np.array(arm.matrix_world.inverted() @ obj.matrix_world)       # mesh space -> armature space
    a2m = np.linalg.inv(m2a)
    to_a = lambda P: P @ m2a[:3, :3].T + m2a[:3, 3]
    hva = to_a(hv)
    cen = hva.mean(axis=0)
    Fn, Un, Ln = (np.array(v) for v in (F, Up, Lat))
    rel = hva - cen
    span = lambda x: float(np.percentile(x, 95) - np.percentile(x, 5))     # ignore stray crests and spikes
    size = span(rel @ Un), span(rel @ Fn), span(rel @ Ln)
    hs = max(size)

    # Talking: hinge the lower front of the head down about a pivot behind it (about the lateral axis).
    A = to_a(co) - cen
    up_c, fw_c = A @ Un, A @ Fn
    low = ur.smooth(pf.get("jaw_top", 0.05) * hs, pf.get("jaw_top", 0.05) * hs - 0.25 * hs, up_c)
    front = ur.smooth(-0.05 * hs, 0.2 * hs, fw_c)
    near = ur.smooth(0.9 * hs, 0.6 * hs, np.linalg.norm(A, axis=1))
    jw = low * front * near * np.clip(w * 2, 0, 1)
    pivot = -Fn * 0.15 * hs + Un * 0.05 * hs
    ang = math.radians(pf.get("jaw", 14 if soldier else 24))
    sign = 1 if (Quaternion(Lat, 0.3) @ Vector(-Fn)).dot(-Up) > 0 else -1   # so the chin swings down
    R = np.array(Quaternion(Lat, sign * ang).to_matrix())
    Aopen = (A - pivot) @ R.T + pivot
    Aj = A + (Aopen - A) * jw[:, None]
    Pm = (Aj + cen) @ a2m[:3, :3].T + a2m[:3, 3]
    if not obj.data.shape_keys: obj.shape_key_add(name="Basis")
    talk = obj.shape_key_add(name="talk"); talk.data.foreach_set("co", Pm.astype(np.float32).ravel())

    # Head and neck turn about the standing up-axis, on top of the standing pose (armature space).
    turners = [(b, k) for b, k in ((neck, 0.45), (head, 1.0)) if b]
    base_rot = {b.name: b.matrix.to_quaternion() for b, _ in turners}
    def pose(look, mouth):
        talk.value = mouth
        for b, k in turners:            # neck first: the head's position follows it
            bpy.context.view_layer.update()
            # +look turns the head to the viewer's right.
            q = Quaternion(Up, math.radians(-26 * look * k)) @ base_rot[b.name]
            b.matrix = Matrix.Translation(b.matrix.translation) @ q.to_matrix().to_4x4()
        bpy.context.view_layer.update()

    # Camera: a short telephoto on the head from the front, a little above and to the side.
    hc = arm.matrix_world @ Vector(cen)
    hsw = hs * arm.matrix_world.to_scale().x
    view = Vector((math.sin(math.radians(pf.get("yaw", 22))), -1, 0)).normalized()
    view = (view * math.cos(math.radians(pf.get("pitch", 10))) + Vector((0, 0, math.sin(math.radians(pf.get("pitch", 10)))))).normalized()
    cd = bpy.data.cameras.new("cam"); cd.lens = 85; cd.sensor_width = 36
    cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam); sc.camera = cam
    dist = hsw * pf.get("zoom", 2.6) * cd.lens / cd.sensor_width
    target = hc + Vector((0, 0, -0.18 * hsw)) + Vector(pf.get("offset", [0, 0, 0])) * hsw
    cam.location = target + view * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cd.clip_start = dist * 0.05; cd.clip_end = dist * 10

    def light(kind, direction, energy, color, size=1.0):
        ld = bpy.data.lights.new(kind, "SUN" if kind == "sun" else "AREA"); ld.energy = energy; ld.color = color
        o = bpy.data.objects.new(kind, ld); sc.collection.objects.link(o)
        if kind == "sun": ld.angle = math.radians(6)
        else: ld.size = size * hsw * 4
        d = Vector(direction).normalized()
        o.location = target - d * dist; o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        return o
    alien = uid.startswith("a_")
    rim = (0.45, 1.0, 0.35) if alien else (0.45, 0.75, 1.0)
    light("sun", Vector((0.8, 1.0, -0.9)), 4.0, (1.0, 0.92, 0.8))
    light("sun", Vector((-1.0, 0.6, -0.3)), 0.9, (0.6, 0.7, 1.0))
    light("sun", Vector((-0.4, -1.0, -0.2)), 5.0, rim)                    # rim light from behind
    # The sky lights the model; the camera sees a dark backdrop instead, baked into the JPEG.
    wd = bpy.data.worlds.new("w"); sc.world = wd; wd.use_nodes = True; nt = wd.node_tree
    bg = nt.nodes["Background"]; bg.inputs["Color"].default_value = (0.4, 0.45, 0.55, 1)
    back = nt.nodes.new("ShaderNodeBackground"); back.inputs["Color"].default_value = (0.012, 0.016, 0.022, 1)
    lp = nt.nodes.new("ShaderNodeLightPath"); mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(bg.outputs[0], mix.inputs[1]); nt.links.new(back.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["World Output"].inputs["Surface"])
    lights = [o for o in sc.objects if o.type == "LIGHT"]
    sc.render.resolution_x = sc.render.resolution_y = PX
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "JPEG"; sc.render.image_settings.quality = 88

    pairs = ur.prepare_materials([obj], fix)
    slots = [m.name if m else None for m in obj.data.materials]
    for li, look in enumerate(LOOKS):
        for mi, mouth in enumerate(MOUTHS):
            pose(look, mouth)
            for i, nm in enumerate(slots):
                if nm: obj.data.materials[i] = pairs[nm][0]
            for l in lights: l.hide_render = False
            bg.inputs["Strength"].default_value = 0.5; back.inputs["Strength"].default_value = 1
            sc.render.image_settings.color_mode = "RGB"
            sc.cycles.samples = 48; sc.cycles.use_denoising = True
            sc.view_settings.view_transform = "AgX"
            sc.render.filepath = os.path.join(OUT, f"p3d_{uid}_{li}_{mi}.jpg")
            bpy.ops.render.render(write_still=True)
            for i, nm in enumerate(slots):
                if nm: obj.data.materials[i] = pairs[nm][1]
            for l in lights: l.hide_render = True
            bg.inputs["Strength"].default_value = 0; back.inputs["Strength"].default_value = 0
            sc.render.image_settings.color_mode = "BW"
            sc.cycles.samples = 4; sc.cycles.use_denoising = False
            sc.view_settings.view_transform = "Raw"
            sc.render.filepath = os.path.join(OUT, f"p3d_{uid}_{li}_{mi}m.jpg")
            bpy.ops.render.render(write_still=True)
    print("PORTRAIT", uid, "head", head.name, int((jw > 0.05).sum()), "jaw verts, head size", round(hsw, 3), "centre", tuple(round(x, 2) for x in hc))

for uid in ids: render_portrait(uid)
