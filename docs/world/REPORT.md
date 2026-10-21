# Mission 5: The Living Battlefield

The baseline is tag `m5-baseline` (commit `62520db`) and the result is tag `v0.5-world`. Every change is in the renderer (`Meridian/Render`), the art, and one settings toggle. The simulation core, unit stats, balance, AI, tactical movement and touch controls are untouched.

**Environment.** All captures and timings below come from Xcode 27.1 iOS 27.1 simulators (iPhone 18 Pro Max, 440×956 pt) on an Apple M4 Max. **No measurements were taken on a physical iPhone or a Duo.** The simulator draws with the Mac's GPU, so its fill-rate cost is not representative of a phone.

## What changed

### 1. A distinct place for each map (`Biome.swift`, `TerrainLayer.swift`)

The ground shader now takes a palette, water style, wind and grading for each map.

| Map | Look | Ambience |
|---|---|---|
| **Crossroads: Amber Meadows** | The original golden dusk palette | Pollen motes, dark swifts, fireflies at night |
| **Riverbend: Verdant Delta** | Deep greens and mossy stone; the river visibly flows downstream | Low mist banks over the water, egret flocks, green critters |
| **Shattered Highlands: Rust Plateau** | Ochre steppe, red cracked earth, mauve lichen, rust-tinted trees and cliffs | Luminous mineral pools that glow at night, sideways dust, dust devils, gliding sky-rays |

On every map:
- **Wind gusts** roll across the grass as soft moving bands.
- **Fine blade shimmer** runs along the wind direction.

### 2. Time of day (`Atmosphere.swift`)

A cosmetic 11-minute cycle runs afternoon → golden hour → dusk → a short blue night → dawn. It is drawn as a single multiply overlay above the battlefield, and light sources draw above that overlay:
- building lamps grow brighter, and light pools glow on the ground beneath buildings;
- gold deposits light their surroundings;
- captured sites glow in their owner's colour;
- Concord towers sweep searchlights;
- the Concord airfield beacon turns;
- aircraft carry red/green navigation lights and a strobe;
- Concord and Lattice vehicles switch on headlights that follow their heading;
- Brood creatures glow faintly (bioluminescence);
- fireflies come out, and occasionally a shooting star crosses the sky;
- the plateau's pools and the gold glints are emissive in the ground shader, so they stay bright at night.

Readability guards:
- The night floor stays at about 66–71% brightness.
- Combat effects, health bars and the delivery/production pops draw above the overlay, so they are never darkened.
- **Settings → "Day/night cycle (cosmetic)"** turns the cycle off, which holds the original look.
- The staged battle and stress modes stay in daylight.

### 3. Wind and the living economy

- **Sway shader (`Sway`).** Grass tufts, reeds and trees bend in the fragment shader, which reads each sprite's position within the texture atlas. Thousands of decor sprites animate with **zero per-frame CPU work**. Gust phase follows position along the wind, so you can see gusts travel across the field.
- **Harvesting:** chips fly off the node and the tree or ore shivers when struck.
- **Workers:**
  - they swing their tools while gathering;
  - they visibly carry their load (iron, gold or timber colour);
  - a **"+N"** pops on each delivery;
  - **idle workers** wear a small bobbing amber marker.
- **Exhausted resources:** a felled tree **topples** with leaves and dust, and an exhausted deposit crumbles.

### 4. Working buildings (`GameScene+Buildings.swift`)

All 24 structures have purposeful motion, and it speeds up while a building is producing. A few parts that used to be baked into the art (dishes, flag, crane cable) are now separate moving sprites.

- **Concord:**
  - the HQ and Research radar dishes turn;
  - the Vehicle Bay crane trolley shuttles while vehicles are built, and its stack exhausts;
  - the barracks flag streams *downwind* (the map's wind);
  - the airfield pad lights chase, and its tower beacon turns;
  - towers and forward posts sweep searchlights at night;
  - the depot silo vents steam.
- **Lattice:**
  - energy nodes orbit the HQ, airfield, tower and relay rings, passing behind the spire on the far side;
  - light packets run along the conduits;
  - welding sparks fly at the assembly arm, and the forge gate glows while working;
  - lightning jumps between the research cores while researching;
  - the depot vents glow.
- **Brood:**
  - volume-preserving squash-and-stretch breathing, faster when busy;
  - a heartbeat ripple crosses the creep;
  - spores drift up while spawning;
  - green regrowth motes rise while a damaged organism heals.

### 5. Production, upgrades and arrivals

- Production progress bars appear under the player's working buildings: amber for units, violet for research.
- When a unit is produced, its building flashes.
- Units arrive in a faction-specific way:
  - Concord: dust;
  - Lattice: materialise from a flickering cyan hologram with rising scan rings;
  - Brood: unfold from a squashed hatchling with a splash.
- Completed research sends a column of light up from the owner's labs.

### 6. Battlefield persistence (`GameScene+Scars.swift`)

Marks are ring buffers of ground sprites. Each kind is capped, the oldest is recycled first, there is no allocation once the buffer is warm, and nothing touches navigation or selection.

| Mark | Cap | Lasts |
|---|---|---|
| Artillery craters, tinted to the biome's earth | 90 | 150 s + 30 s fade |
| Scorch | 140 | 80 s + 20 s fade |
| Brood ichor and Lattice oil residue | 120 | 70 s + 20 s fade |
| Tread marks behind ground vehicles | 260 | 10 s + 6 s fade |

- Destroyed vehicles leave **wrecked hulks** that burn, then cool and stay about 30 s. At most 36 remain; the oldest clear first.
- Destroyed buildings leave rubble that smoulders for about 25 s and stays for about 2 minutes.

### 7. Unit personality and role readability

- **Energy weapons** visibly charge before each shot.
- **Hover units** bob.
- **Idle infantry** glance around now and then.
- Two new **role rings** join the existing heavy, siege and air rings:
  - support: a ring with plus-ticks;
  - workers: a slim dashed ring that reads quieter than combat units.

### 8. Ambient wildlife (`GameScene+Wildlife.swift`)

- **Flocks** cross the sky with shadows sliding over the ground:
  - swifts over the meadow;
  - white egrets over the delta;
  - bats after dusk;
  - slow sky-rays over the plateau.
- **Water:** fish jump out of the water and ripples spread.
- **Critters:** small field critters (tinted per biome) hop about and **scatter when troops come near**.
- **Plateau dust devils** wander downwind.

Wildlife is spawned near the camera and capped. It is disabled in stress tests, in staged battles above 260 entities, and at reduced effect quality.

## Before / after (matching scenes)

`docs/world/compare/*.jpg` holds side-by-side images: before on the left, after on the right. Each scene uses the same seed, map, faction and warp.

| Scene | File |
|---|---|
| Crossroads, Concord base | `01_crossroads_humans.jpg` |
| Riverbend, Lattice base | `02_riverbend_machines.jpg` |
| Highlands, Brood base | `03_highlands_aliens.jpg` |
| Mid-game spectate, 7:10 (dawn light, critters) | `04_midgame_spectate.jpg` |
| 50v50 staged battle | `05_battle50.jpg` |
| 200v200 staged battle | `06_battle200.jpg` |

Video: `docs/world/world_demo.mp4` (54 s, simulator), with a filmstrip in `demo_filmstrip.jpg`. The clips, in order:
1. Delta opening, with egrets and economy pops.
2. Concord base at night: searchlight, lit HQ, glowing gold, fireflies.
3. Lattice base: orbiting nodes, conduits, holograms.
4. Brood base on the plateau: breathing, ripples, sky-rays.
5. Late-game plateau fighting.
6. A 100v100 battle with scars and wrecks.

To regenerate everything:
```
tools/world_capture.sh docs/world/after
tools/world_video.sh docs/world/world_demo.mp4
```

Capture flags added in this mission:
- `-tod <phase>` pins the time of day;
- `-camhq <player>` holds the camera on a base;
- `-perf log` logs frame timings in any mode.

## Performance (simulator, M4 Max; not hardware)

The 200v200 staged battle runs at 440×956 pt. Each value below is the scene-update time per frame: the renderer's CPU work outside the simulation.

| Window | Baseline | Day | Night (all lights on) |
|---|---|---|---|
| t = 6 s | 0.70 ms | 0.80 ms | 0.87 ms |
| t = 8 s | 0.74 ms | 0.86 ms | 0.86 ms |
| t = 10 s | 0.70 ms | 0.77 ms | 0.83 ms |

- Frame rate is 60 fps throughout (p95 16.7 ms) in all three runs.
- Node count at peak: about 2,500 before, 2,800–3,000 after (scars and wrecks).
- The simulation cost is unchanged (the same code).
- A late-game spectated match (Highlands, 17 minutes, both bases built up, scars accumulated) also runs at 60 fps, with scene update at 0.44–0.77 ms.

Performance techniques used:
- Shader-driven sway: no per-sprite CPU work.
- Pooled, capped scars and wrecks.
- Camera-local, capped wildlife.
- One overlay for time of day.
- Lights created lazily and hidden in daylight.
- Unit lights and wildlife automatically turn off at reduced effect quality. The existing adaptive quality system still governs everything.

**Not verified:**
- **GPU fill cost on a phone.** The full-screen overlay plus the ground shader add pixels the simulator doesn't penalise. The ground shader got more expensive with the cracked-earth cells, but that work runs only on the plateau.
- **Thermal behaviour.**
- **Real Duo screens.**

## Tests

- **Core:** 14 of 14 passing (simulation untouched).
- **UI:** 3 of 3 passing (portrait/landscape layout, spectator battle, full playthrough). The playthrough covers both the box-select drag and the hold-then-drag camera pan.

## Limitations and honest notes

- **Day/night overlay:** health bars and effects stay above it, but team and selection rings sit beneath it and dim by about 30% at night. I kept rings under the overlay because drawing them above would paint them over the heads of units in dense crowds.
- **Building parts** are positioned from the art's coordinate system and checked visually at normal zoom. Some, such as the radar dish size, are judgement calls.
- **Flocks and critters can cross fogged ground** only beneath the fog layer, so they never reveal anything.
- **Critters are cosmetic.** They read the unit list to flee, but never affect the simulation.
- **No new audio** for wildlife or night ambience yet.
- **Delta mist banks** are static sprites that drift slightly. They read as mist at normal zoom but look flat when zoomed far in.
- **Dark menu backdrop.** The live backdrop also runs the time of day, so the menu can sometimes appear at night.

## Recommended next steps

1. **Profile on a real iPhone:** GPU time for the ground and overlay passes; add a reduced-shader option for older devices if needed.
2. **Night soundscape:** crickets, frogs on the delta, wind on the plateau, all tied to the existing time of day.
3. **Weather** (cosmetic, toggled): drizzle on the delta with puddle ripples, dust storms on the plateau.
4. **Explicit Lattice links:** draw the network connections as faint animated lines between linked Lattice units and network structures, which also teaches the faction mechanic.
5. **Per-unit idle animations** beyond the glance: Concord radio checks, Lattice sensor sweeps, Brood twitching.
