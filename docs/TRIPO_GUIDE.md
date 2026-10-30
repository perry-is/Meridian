# Tripo Guide: Meridian Unit Models

The goal is realistic, StarCraft 2-style units. Infantry and creatures come from Tripo. Buildings, vehicles, aircraft and every Lattice machine are built in Blender. Every model then goes through the same Blender pipeline so they share materials, team colours and lighting.

## Who makes what

| Source | Units |
|---|---|
| **Tripo (you)** | 8 Concord infantry and all 15 Brood creatures (23 models) |
| **Blender (Claude)** | 7 Concord vehicles and aircraft, all 15 Lattice machines, all 24 buildings |

## Start with one pilot unit

Make the **Ranger** first and drop it in the folder below. I'll put it in the game so we can check scale, team colour and lighting before you spend credits on the other 22.

## Steps in Tripo

1. Open Tripo Studio and choose **Text to 3D** (or Text to Model).
2. Paste the unit's prompt from the list below. Every prompt already ends with the shared style line, so you can copy each block as it is.
3. Generate, then pick the variant with the clearest silhouette. At game zoom a unit is only about 50 pixels tall, so a strong shape matters more than fine detail.
4. Turn on the highest texture quality, PBR if offered, and refine or upscale if available.
5. **Rigging (soldiers only):** if Tripo offers auto-rig and animation, rig the model and add **Idle**, **Walk** and, if available, **Shoot** or **Attack**. If not, skip this; I can animate in Blender.
6. **Creatures:** skip rigging. Most Brood units aren't humanoid, so I'll animate their legs, wings and breathing in Blender.
7. Export as **GLB**, named with the unit's id, for example `h_ranger.glb`.
8. Put the file in **`/Users/perry/Meridian/art/tripo/`**.

If the buttons in Tripo are named differently from the ones above, tell me what you see and I'll adjust the steps.

### Rules that keep the models usable

- **Team colour:** each prompt asks for **bright pure blue** markings on the armour or carapace. I swap that blue for each player's colour, so keep the blue limited to the marked parts.
- **Pose:** soldiers stand in a relaxed **A-pose** (arms slightly out from the body) with the weapon held at the side or slung. A clean pose makes rigging work.
- **One model per file:** no base, ground plane or extra props.
- **Regenerate** a model if it comes back with melted hands, merged legs or text on it.

## Shared style line

Every prompt below already includes this line:

> realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background

---

## Concord infantry (8)

Concord is a human military of combined-arms engineers. Its look is olive-drab and gunmetal powered armour with angular plates, amber visor glow and hazard-yellow details. Its team colour is on the shoulder pauldrons and knee plates.

| id | Unit | Prompt |
|---|---|---|
| `h_engineer` | Engineer | Human construction engineer in a bulky utility exosuit, olive and steel armour, hazard-yellow stripes, welding torch and wrench mounted on the forearms, tool backpack with antenna, amber visor, bright pure blue shoulder pads, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `h_pathfinder` | Pathfinder | Lean recon scout in light camo armour and a hooded cloak, sensor goggles with a glowing amber lens, long-range carbine slung on the back, radio pack, bright pure blue armband and shoulder plate, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `h_ranger` | Ranger | Standard rifle infantry in heavy powered combat armour, olive and gunmetal plates, sealed helmet with an amber visor slit, assault rifle held at the side, ammo pouches, bright pure blue shoulder pauldrons and knee plates, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `h_breacher` | Breacher | Heavily armoured shock trooper, thick riot-style chest plate, combat shotgun, breaching charges strapped to the chest, scarred helmet with a narrow amber visor, bright pure blue shoulder pauldrons, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `h_lancer` | Lancer | Anti-armour rocket infantry in powered armour carrying a long shoulder-fired rocket launcher, spare rockets on the back, targeting monocle with an amber glow, bright pure blue shoulder pauldrons, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `h_skyguard` | Skyguard | Anti-air missile trooper in powered armour, twin-tube missile launcher on the shoulder, radar dish on the backpack, upward-tilted helmet sensor, bright pure blue shoulder pauldrons, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `h_medic` | Field Medic | Combat medic in white and olive armour, red-cross arm patch, medical backpack with injector arms, healing beam emitter on the forearm, glowing green vials, bright pure blue shoulder plates, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `h_ghost` | Ghost Operative | Covert sniper operative in a sleek black stealth suit, hood and respirator mask with a glowing amber eye lens, long suppressed sniper rifle held at the side, EMP grenades on the belt, bright pure blue thin accent lines on the suit, A-pose, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |

## Brood creatures (15)

The Brood is an alien swarm of chitin, flesh and bone. Its look is dark purple-brown carapace, bone spines, wet glistening flesh and glowing bio-green pores. Its team colour is bright pure blue markings on the carapace plates.

| id | Unit | Prompt |
|---|---|---|
| `a_weaver` | Weaver | Small six-legged alien worker creature, spindly legs, rounded carapace back with resin sacs, mandibles for harvesting, glowing bio-green pores, bright pure blue carapace markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_glint` | Glint | Small darting alien scout creature, slender body with oversized glowing eyes and sensory antennae, translucent fins, bright pure blue carapace markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_mantis` | Mantis | Fast predatory alien warrior shaped like a praying mantis, two huge scythe blade forelimbs, lean armoured chitin body, glowing bio-green eyes, bright pure blue carapace stripes, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_ravager` | Ravager | Hulking alien brute on four thick legs, massive cleaver-shaped bone forearms, heavy plated shoulders, drooling jaw, bright pure blue carapace plates, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_spinecaster` | Spinecaster | Alien artillery creature with a hunched back covered in launchable acid-dripping spines, four sturdy legs, glowing green acid glands, bright pure blue carapace markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_needleback` | Needleback | Upright alien anti-air creature like a porcupine, tall quills pointing skyward along its back, glowing tips, two-legged stance, bright pure blue carapace markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_lifebinder` | Lifebinder | Graceful alien healer creature with tentacle tendrils, a glowing green bioluminescent heart-sac in the chest, soft translucent membranes, bright pure blue carapace markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_shadeling` | Shadeling | Sleek shadowy ambush predator alien, low panther-like body, dark iridescent skin, long claws, faint glowing eyes, bright pure blue thin markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_skitter` | Skitter | Tiny fast alien swarm creature like a beetle-crab hybrid, sharp legs, snapping jaws, bright pure blue carapace markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_colossus` | Colossus | Towering alien behemoth with an elephant-sized armoured body, six massive legs, huge bone tusks and a crushing armoured head, glowing green vents, bright pure blue carapace plates, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_rupturer` | Rupturer | Bloated alien bio-artillery creature with a giant translucent acid sac on its back, short sturdy legs, a mortar-like spitting orifice, bright pure blue carapace plates, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_seeder` | Spore Seeder | Alien creature with a mushroom-like spore cap on its back that releases glowing pods, slow heavy legs, fungal growths, bright pure blue carapace markings, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_wisp` | Wisp | Small swift flying alien predator with four translucent dragonfly wings, long stinger tail, glowing green core, bright pure blue carapace markings, wings spread, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_blightwing` | Blightwing | Large flying alien bombardier with bat-like leathery wings, a dangling acid gland under its belly, long neck with a spitting maw, bright pure blue carapace plates, wings spread, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |
| `a_sporewing` | Sporewing | Huge floating alien transport creature like a manta ray balloon, gas bladders, dangling tendrils that carry passengers, glowing spore vents, bright pure blue carapace plates, realistic sci-fi RTS game unit, StarCraft 2 art style, PBR, worn and weathered materials, bold readable silhouette, full body, centered, plain background |

---

## Built in Blender (no Tripo needed)

- **Concord vehicles and aircraft:** `h_buggy` Strider Buggy, `h_bastion` Bastion Tank, `h_mortar` Mortar Carrier, `h_minelayer` Mine Layer, `h_kestrel` Kestrel, `h_harrier` Harrier, `h_dropship` Dropship.
- **All Lattice machines:** Fabricator, Recon Drone, Arc Sentry, Shockframe, Piercer, Flak Drone, Repair Drone, Jammer, Skirmish Runner, Bulwark Walker, Coil Cannon, Suppression Array, Vector, Quake Drone, Carrier Drone.
- **All 24 buildings.**

If Tripo goes well, any of these can switch to Tripo later.
