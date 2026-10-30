# Procedural hard-surface unit models (Concord vehicles and aircraft, all Lattice machines), built from the
# buildings.py kit. unit_render.py calls build(uid) for units marked "source": "proc" in unit_fixes.json.
#
# Conventions: forward is -Y, ground units stand on z = 0, left/right is ±X. Sizes are arbitrary (the renderer
# fits each model to its canvas) but proportions matter: walkers keep legs under the hips and arms out to the
# sides so the biped/multiped rigs find them.
import math
from mathutils import Vector
import buildings as K
from buildings import box, cyl, hexp, sph, torus, strut, horn

def wheel(x, y, r, w, m="dark"):
    cyl((x, y, r), r, w, m, rot=(0, math.pi / 2, 0), verts=24)
    cyl((x + (w / 2 + 0.005) * (1 if x > 0 else -1), y, r), r * 0.5, 0.01, "armor", rot=(0, math.pi / 2, 0), verts=16)

def track(x, y0, y1, h, w):
    box((x, (y0 + y1) / 2, h / 2), (w, abs(y1 - y0), h), "dark", sub=0)
    for i in range(5): cyl((x, y0 + (y1 - y0) * i / 4, h * 0.45), h * 0.4, w * 1.04, "armor", rot=(0, math.pi / 2, 0), verts=16)

def engine_glow(loc, r, m="glow"):
    cyl(loc, r, 0.02, m, rot=(math.pi / 2, 0, 0), verts=20)

# ---------------------------------------------------------------- Concord
def h_buggy():
    for x in (-0.42, 0.42):
        for y in (-0.5, 0.5): wheel(x, y, 0.2, 0.16)
    box((0, 0, 0.32), (0.6, 1.3, 0.14), "olive")
    box((0, -0.62, 0.36), (0.5, 0.12, 0.12), "team")
    for x in (-0.25, 0.25):
        strut((x, -0.25, 0.38), (x, -0.05, 0.72), 0.02, "dark"); strut((x, 0.35, 0.38), (x, 0.15, 0.72), 0.02, "dark")
    strut((-0.25, 0.05, 0.72), (0.25, 0.05, 0.72), 0.02, "dark")
    box((0, 0.1, 0.47), (0.36, 0.3, 0.16), "armor")
    box((0, 0.2, 0.62), (0.16, 0.16, 0.1), "dark")
    for x in (-0.05, 0.05): cyl((x, -0.15, 0.64), 0.025, 0.55, "dark", rot=(math.pi / 2, 0, 0), verts=10)

def h_bastion():
    for x in (-0.5, 0.5): track(x, -0.8, 0.8, 0.3, 0.26)
    box((0, 0, 0.42), (0.9, 1.6, 0.28), "olive")
    box((0, -0.85, 0.36), (0.8, 0.16, 0.18), "armor", rot=(0.6, 0, 0))
    box((0, 0.1, 0.62), (0.62, 0.7, 0.22), "olive", sub=0)
    box((0, 0.1, 0.74), (0.64, 0.72, 0.04), "team")
    cyl((0, -0.65, 0.64), 0.045, 1.0, "dark", rot=(math.pi / 2, 0, 0), verts=14)
    cyl((0, -1.12, 0.64), 0.06, 0.1, "armor", rot=(math.pi / 2, 0, 0), verts=14)
    box((0.22, 0.32, 0.8), (0.1, 0.1, 0.08), "dark")
    for x in (-0.47, 0.47): box((x, 0, 0.5), (0.06, 1.5, 0.1), "armor")

def h_mortar():
    for x in (-0.42, 0.42):
        for y in (-0.55, 0.0, 0.55): wheel(x, y, 0.17, 0.15)
    box((0, 0, 0.42), (0.72, 1.5, 0.3), "olive")
    box((0, -0.55, 0.62), (0.6, 0.35, 0.16), "armor")
    box((0, -0.72, 0.62), (0.5, 0.02, 0.08), "glow", bevel=0)
    box((0, 0.3, 0.6), (0.6, 0.7, 0.08), "team")
    cyl((0, 0.35, 0.8), 0.1, 0.12, "dark")
    strut((0, 0.35, 0.82), (0, 0.05, 1.35), 0.07, "dark")
    cyl((0, 0.05, 1.36), 0.085, 0.04, "armor", rot=(0.55, 0, 0))

def h_minelayer():
    for x in (-0.42, 0.42):
        for y in (-0.55, 0.0, 0.55): wheel(x, y, 0.17, 0.15)
    box((0, -0.35, 0.5), (0.7, 0.7, 0.45), "olive")
    box((0, -0.71, 0.58), (0.5, 0.02, 0.16), "glow", bevel=0)
    box((0, -0.35, 0.74), (0.72, 0.72, 0.04), "team")
    cyl((0, 0.4, 0.55), 0.3, 0.6, "hull", rot=(0, math.pi / 2, 0))
    for i in range(6):
        a = i * math.pi / 3
        sph((0.31 * (1 if i % 2 else -1), 0.4 + math.cos(a) * 0.2, 0.55 + math.sin(a) * 0.2), 0.04, "hazard")
    box((0, 0.78, 0.3), (0.5, 0.06, 0.25), "hazard")

def h_kestrel():
    box((0, 0, 0), (0.22, 1.5, 0.18), "hull", sub=1)
    sph((0, -0.6, 0.06), (0.1, 0.25, 0.08), "glass")
    for s in (-1, 1):
        box((s * 0.45, 0.15, -0.02), (0.75, 0.42, 0.03), "hull", rot=(0, 0, s * 0.45))
        box((s * 0.8, 0.32, -0.01), (0.12, 0.18, 0.035), "team", rot=(0, 0, s * 0.45))
        box((s * 0.14, 0.62, 0.14), (0.03, 0.26, 0.22), "armor", rot=(0, s * 0.3, 0))
        engine_glow((s * 0.07, 0.77, 0), 0.06)

def h_harrier():
    box((0, 0, 0), (0.42, 1.5, 0.3), "olive", sub=1)
    sph((0, -0.62, 0.1), (0.14, 0.24, 0.1), "glass")
    for s in (-1, 1):
        box((s * 0.6, 0.1, 0), (0.95, 0.55, 0.05), "olive", rot=(0, 0, s * 0.2))
        cyl((s * 0.62, 0.05, 0.0), 0.2, 0.08, "dark", verts=24)             # VTOL fan
        torus((s * 0.62, 0.05, 0.04), 0.2, 0.025, "armor")
        box((s * 0.95, 0.25, 0.0), (0.18, 0.25, 0.06), "team", rot=(0, 0, s * 0.2))
        for k in range(2): cyl((s * (0.3 + k * 0.18), -0.1, -0.12), 0.06, 0.4, "hazard", rot=(math.pi / 2, 0, 0), verts=12)
        engine_glow((s * 0.12, 0.76, 0), 0.08)

def h_dropship():
    box((0, 0, 0), (0.7, 1.6, 0.55), "olive", sub=1)
    box((0, -0.72, 0.1), (0.5, 0.25, 0.25), "glass", sub=1)
    box((0, 0.82, -0.12), (0.5, 0.1, 0.3), "hazard", rot=(0.4, 0, 0))
    box((0, 0, 0.3), (0.5, 1.2, 0.06), "team")
    for s in (-1, 1):
        box((s * 0.55, 0.1, 0.15), (0.45, 0.25, 0.06), "armor")
        cyl((s * 0.85, 0.1, 0.15), 0.18, 0.55, "hull", rot=(math.pi / 2, 0, 0), verts=24)
        engine_glow((s * 0.85, 0.38, 0.15), 0.14)

# ---------------------------------------------------------------- Lattice
def core(loc, r=0.08): sph(loc, r, "cyan")

def m_fabricator():
    hexp((0, 0, 0.55), 0.32, 0.28, "gunmetal")
    hexp((0, 0, 0.55), 0.33, 0.05, "teamglow")
    core((0, -0.28, 0.55), 0.07)
    for s in (-1, 1):
        strut((s * 0.25, -0.1, 0.5), (s * 0.45, -0.35, 0.35), 0.03, "chrome")
        strut((s * 0.45, -0.35, 0.35), (s * 0.3, -0.55, 0.25), 0.025, "chrome")
    torus((0, 0, 0.3), 0.25, 0.02, "cyan")

def m_recon():
    sph((0, 0, 0), 0.22, "obsidian")
    sph((0, -0.17, 0.0), 0.09, "cyan")
    torus((0, 0, 0), 0.4, 0.025, "chrome", rot=(0.3, 0, 0))
    hexp((0, 0, 0.22), 0.08, 0.08, "teamglow")
    for a in range(3): strut((0, 0, -0.1), (math.cos(a * 2.1) * 0.25, math.sin(a * 2.1) * 0.25, -0.35), 0.012, "gunmetal")

def m_arc():
    for a in range(3):
        x, y = math.cos(a * 2.1 + 0.5) * 0.45, math.sin(a * 2.1 + 0.5) * 0.45
        strut((x * 0.5, y * 0.5, 0.55), (x, y, 0.35), 0.035, "gunmetal")
        strut((x, y, 0.35), (x * 1.1, y * 1.1, 0.0), 0.03, "gunmetal")
    hexp((0, 0, 0.62), 0.28, 0.2, "obsidian")
    hexp((0, 0, 0.62), 0.29, 0.05, "teamglow")
    cyl((0, 0, 0.95), 0.06, 0.4, "chrome", verts=12)
    for z in (0.85, 0.97, 1.09): torus((0, 0, z), 0.12, 0.02, "cyan")
    core((0, 0, 1.2), 0.08)

def m_shockframe():
    for s in (-1, 1):
        strut((s * 0.18, 0, 0.55), (s * 0.2, -0.05, 0.28), 0.07, "gunmetal")
        strut((s * 0.2, -0.05, 0.28), (s * 0.2, 0.02, 0.05), 0.07, "gunmetal")
        box((s * 0.2, -0.04, 0.04), (0.16, 0.26, 0.08), "obsidian")
        strut((s * 0.38, 0, 0.92), (s * 0.48, -0.1, 0.62), 0.07, "gunmetal")
        box((s * 0.5, -0.14, 0.52), (0.2, 0.22, 0.2), "obsidian", sub=1)     # big fists
        box((s * 0.36, 0, 0.95), (0.18, 0.24, 0.16), "teamglow")
    box((0, 0, 0.8), (0.55, 0.38, 0.45), "obsidian", sub=1)
    core((0, -0.2, 0.82), 0.07)
    box((0, -0.05, 1.08), (0.22, 0.2, 0.12), "gunmetal")
    box((0, -0.16, 1.08), (0.16, 0.02, 0.03), "cyan", bevel=0)

def m_piercer():
    for sx in (-1, 1):
        for sy in (-1, 1):
            strut((sx * 0.2, sy * 0.25, 0.45), (sx * 0.45, sy * 0.45, 0.25), 0.03, "gunmetal")
            strut((sx * 0.45, sy * 0.45, 0.25), (sx * 0.5, sy * 0.5, 0.0), 0.025, "gunmetal")
    box((0, 0, 0.5), (0.45, 0.6, 0.18), "obsidian")
    box((0, 0, 0.5), (0.47, 0.62, 0.04), "teamglow")
    for x in (-0.06, 0.06): box((x, -0.6, 0.62), (0.04, 1.2, 0.06), "chrome")
    box((0, -0.6, 0.62), (0.04, 1.1, 0.02), "cyan", bevel=0)
    core((0, 0.2, 0.68), 0.06)

def m_flak():
    hexp((0, 0, 0.55), 0.35, 0.3, "obsidian")
    hexp((0, 0, 0.55), 0.36, 0.05, "teamglow")
    for i in range(4):
        x = -0.15 + i * 0.1
        strut((x, -0.1, 0.7), (x, -0.3, 1.05), 0.025, "chrome")
    torus((0, 0, 0.32), 0.3, 0.03, "cyan")
    core((0, -0.33, 0.55), 0.05)

def m_repair():
    sph((0, 0, 0), (0.25, 0.3, 0.16), "gunmetal")
    hexp((0, 0, 0.14), 0.12, 0.06, "teamglow")
    for s in (-1, 1):
        torus((s * 0.38, 0, 0), 0.14, 0.02, "chrome", rot=(0, 0, 0))
        strut((s * 0.15, -0.2, -0.05), (s * 0.1, -0.45, -0.2), 0.02, "chrome")
        core((s * 0.1, -0.46, -0.21), 0.035)
    core((0, -0.26, 0.02), 0.05)

def m_jammer():
    for a in range(4):
        x, y = math.cos(a * math.pi / 2 + 0.78) * 0.35, math.sin(a * math.pi / 2 + 0.78) * 0.35
        strut((x * 0.4, y * 0.4, 0.4), (x, y, 0.0), 0.03, "gunmetal")
    hexp((0, 0, 0.75), 0.18, 0.8, "obsidian", r2=0.08)
    hexp((0, 0, 0.5), 0.19, 0.03, "teamglow")
    for z in (0.75, 0.95): torus((0, 0, z), 0.2 - (z - 0.75) * 0.3, 0.015, "cyan")
    for a in range(3): strut((0, 0, 1.1), (math.cos(a * 2.1) * 0.2, math.sin(a * 2.1) * 0.2, 1.35), 0.01, "chrome")
    core((0, 0, 1.18), 0.05)

def m_runner():
    for x in (-0.35, 0.35): track(x, -0.55, 0.55, 0.22, 0.2)
    box((0, 0, 0.32), (0.6, 1.1, 0.2), "obsidian")
    box((0, 0, 0.32), (0.62, 1.12, 0.04), "teamglow")
    box((0, -0.05, 0.5), (0.3, 0.4, 0.14), "gunmetal")
    for x in (-0.08, 0.08): cyl((x, -0.45, 0.52), 0.025, 0.5, "chrome", rot=(math.pi / 2, 0, 0), verts=10)
    core((0, -0.27, 0.5), 0.04)

def m_bulwark():
    for s in (-1, 1):
        strut((s * 0.22, 0, 0.62), (s * 0.3, -0.12, 0.32), 0.09, "gunmetal")
        strut((s * 0.3, -0.12, 0.32), (s * 0.3, 0.02, 0.05), 0.08, "gunmetal")
        box((s * 0.3, -0.04, 0.05), (0.22, 0.34, 0.1), "obsidian")
        box((s * 0.5, -0.1, 0.98), (0.2, 0.55, 0.2), "obsidian")                 # pulse cannons as arms
        cyl((s * 0.5, -0.45, 0.98), 0.06, 0.3, "chrome", rot=(math.pi / 2, 0, 0), verts=12)
        core((s * 0.5, -0.6, 0.98), 0.05)
    box((0, 0, 0.9), (0.62, 0.5, 0.5), "obsidian", sub=1)
    box((0, 0, 0.98), (0.64, 0.52, 0.05), "teamglow")
    hexp((0, 0, 1.25), 0.15, 0.14, "gunmetal")
    core((0, -0.26, 0.92), 0.08)

def m_coil():
    for sx in (-1, 1):
        for sy in (-1, 1):
            strut((sx * 0.22, sy * 0.25, 0.4), (sx * 0.55, sy * 0.5, 0.2), 0.035, "gunmetal")
            strut((sx * 0.55, sy * 0.5, 0.2), (sx * 0.6, sy * 0.55, 0.0), 0.03, "gunmetal")
    box((0, 0.05, 0.45), (0.55, 0.7, 0.2), "obsidian")
    box((0, 0.05, 0.45), (0.57, 0.72, 0.04), "teamglow")
    cyl((0, -0.45, 0.68), 0.07, 1.2, "chrome", rot=(math.pi / 2 - 0.25, 0, 0), verts=16)
    for i in range(5): torus((0, -0.1 - i * 0.2, 0.6 + i * 0.05), 0.12, 0.022, "cyan", rot=(math.pi / 2 - 0.25, 0, 0))

def m_suppress():
    for x in (-0.38, 0.38): track(x, -0.55, 0.55, 0.24, 0.2)
    box((0, 0, 0.35), (0.7, 1.1, 0.22), "obsidian")
    box((0, 0, 0.35), (0.72, 1.12, 0.04), "teamglow")
    cyl((0, 0.05, 0.62), 0.08, 0.3, "gunmetal")
    sph((0, 0.05, 0.85), (0.35, 0.35, 0.1), "chrome", rot=(0.3, 0, 0))
    core((0, 0.0, 0.9), 0.06)
    torus((0, 0.05, 0.86), 0.3, 0.02, "cyan", rot=(0.3, 0, 0))

def m_vector():
    box((0, 0, 0), (0.2, 1.4, 0.12), "obsidian", sub=1)
    for s in (-1, 1):
        box((s * 0.4, 0.2, 0), (0.7, 0.35, 0.03), "obsidian", rot=(0, 0, s * 0.6))
        box((s * 0.72, 0.42, 0.0), (0.1, 0.2, 0.035), "teamglow", rot=(0, 0, s * 0.6))
        cyl((s * 0.25, -0.1, -0.06), 0.03, 0.6, "chrome", rot=(math.pi / 2, 0, 0), verts=10)
        engine_glow((s * 0.06, 0.71, 0), 0.05, "cyan")
    core((0, -0.4, 0.06), 0.05)

def m_quake():
    hexp((0, 0, 0), 0.55, 0.25, "obsidian")
    hexp((0, 0, 0.0), 0.56, 0.05, "teamglow")
    for a in range(6):
        x, y = math.cos(a * math.pi / 3) * 0.7, math.sin(a * math.pi / 3) * 0.7
        torus((x, y, 0.0), 0.12, 0.02, "chrome")
    cyl((0, 0, -0.3), 0.15, 0.35, "gunmetal", r2=0.06, verts=6)
    core((0, 0, -0.5), 0.08)

def m_carrier():
    hexp((0, 0, 0), 0.7, 0.35, "obsidian", r2=0.5)
    hexp((0, 0, -0.06), 0.65, 0.05, "teamglow")
    torus((0, 0, -0.05), 0.85, 0.035, "chrome")
    for a in range(3):
        x, y = math.cos(a * 2.1) * 0.85, math.sin(a * 2.1) * 0.85
        sph((x, y, -0.05), 0.07, "cyan")
    box((0, -0.55, -0.05), (0.4, 0.25, 0.15), "gunmetal")
    core((0, 0, 0.28), 0.1)

BUILDERS = {k: v for k, v in globals().items() if k[:2] in ("h_", "m_") and callable(v)}

def build(uid):
    K.make_materials()
    BUILDERS[uid]()
