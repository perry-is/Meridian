# Meridian: Three Fronts — Project Status

Original isometric 2.5D sci-fi RTS for iPhone (primary target: **iPhone Duo**, cover + inner screens), also runs on iPad and macOS for desktop testing.
Last updated: 2026-10-20 (Mission 5: the living battlefield; see `docs/world/REPORT.md`).

## Architecture

| Layer | Tech | Where |
|---|---|---|
| Simulation core (deterministic, 20 Hz fixed step, headless) | Swift package, no dependencies | `MeridianCore/Sources/MeridianCore` |
| Balance data (editable) | JSON | `MeridianCore/Sources/MeridianCore/Data/*.json` |
| Headless harness: AI matches, tournaments, combat sims, stress | Swift CLI `meridian-sim` | `MeridianCore/Sources/meridian-sim` |
| Renderer + touch/mouse input | SpriteKit (isometric `SKTileMapNode`, sprite atlas, fog shader) | `Meridian/Render` |
| HUD, menus, tech tree | SwiftUI overlay | `Meridian/UI`, `Meridian/Game` |
| Art | 100% procedural CoreGraphics drawings (original, no external assets) | `Meridian/Render/UnitArt.swift`, `WorldArt.swift` |

## Working features (verified)

- **Playable match vs computer opponent** from the main menu: faction choice (3), opponent faction, difficulty (Easy/Normal/Hard), AI style (balanced/aggressive/territorial/tech), 3 procedural map layouts (Crossroads, Riverbend, Shattered Highlands; point-symmetric, connectivity-checked).
- **Three factions, 45 unit types (15 each), 8 building types each (24), 47 upgrades**, all producible in-game. See `docs/UNITS.md` (generated from the JSON).
- **Economy**: Iron, Gold, Wood gathered by workers and returned to HQ/depots/forward structures; worker auto-retreat when wounded; captured sites give income.
- **Production**: queues (5 per building, cancel/refund), rally points (rally onto a resource sends new workers to gather), Skitters spawn in pairs, **200 actual-unit cap** (no weighted supply).
- **Construction**: placement ghost with per-tile validity, territory build zones, tower zones and **escalating tower cost (+20% each)** to prevent tower spam; cancel for 75% refund; workers repair.
- **Combat model**: armor with 25% damage floor, tag bonuses (light/armored/bio/mech/air/structure/massive), ground/air targeting, splash with falloff, homing and ballistic projectiles, min range, chain lightning (Arc Sentry), piercing rails (Piercer), armor shred (Spinecaster), acid/spore clouds, proximity mines (Mine Layer, detectable), slow/burn fields (Suppression Array), jamming (Jammer), EMP (Ghost, autocast), setup time (Coil Cannon), configurable modes (Skyguard AA/ground, Bastion brace, Sentry Tower balanced/anti-ground/anti-air), cloaking + detection, transports (load by tapping the transport; Unload command), healing/repair units and auras.
- **Faction mechanics**: Concord staging (+10% damage near HQ/Forward Post/sites) and forward repair + forward drop-off at captured sites; Lattice network links (≥2 allies or network structure: −15% damage taken / +10% dealt, non-stacking, broken by EMP/Jammer; linked Pulse Towers +25% damage +1 range); Brood Bloom territory (regeneration out of combat, +15% speed, Sporewing mobile Bloom) and mutually exclusive adaptations.
- **Territory**: 7 contested sites per map; capture/contest/neutralize/recapture; income, vision, faction effects; installations (Extractor / Watchpost with detection / Bulwark turret).
- **Victory**: base destruction, or **territorial dominance** (hold 5 of 7 sites for 3:30, countdown only after 14:00) — both occur in tests.
- **Fog of war** (visible / explored, soft-edged shader), remembered enemy buildings, detection.
- **Tech tiers** 1–3 with building/upgrade prerequisites; tech tree screen.
- **AI** plays full matches alone: economy on all three resources, build orders, factory scaling, research, scouting, site capture and defence, attacks with retreat, composition adaptation (counters seen air/armor/light, detection vs cloak), worker retreat, gold-aware production, faction-specific openings; Hard adds focus-fire, wounded retreat and territory defence.
- **Controls**: touch (tap select/command, double-tap select type, hold-drag box select, one/two-finger pan, pinch zoom, minimap tap/drag, control groups with long-press assign, Army / Idle-worker buttons, attack-move/patrol/stop/hold, building placement drag + confirm). Desktop: mouse select/box, right-click command, scroll/pinch, hotkeys (A/S/H/P/B/M/E/X/I, ⌘1-9, Space, T).
- **Adaptive HUD** for the Duo cover screen (narrow portrait) and tablet-sized/unfolded portrait; landscape layout for wide windows.

## Test & verification results (all measured in this session)

Reproduce with the commands in *How to test* below. Raw logs in `docs/balance/`.

### Automated tests
- `swift test` (MeridianCore): **9/9 pass** — data validity, faction multipliers, map symmetry/connectivity, **deterministic replay hash**, gathering+production, armor/bonus math, territory capture/contest, tower cost escalation, full AI match completes.
- `xcodebuild test` (MeridianUITests on iPhone Duo simulator): **2/2 pass** — touch playthrough (menu → match → tap-select HQ → train → hold-drag box select → build menu → place + confirm Drill Hall → orders), portrait/landscape layout capture.

### Balance (AI vs AI, Normal, 72 games: 3 pairings × 3 maps × 4 seeds × both start slots)
| Faction | Wins |
|---|---|
| Humans | 26/48 (54%) |
| Machines | 25/48 (52%) |
| Aliens | 21/48 (44%) |

Pairings: Humans–Aliens 16-8, Humans–Machines 10-14, Machines–Aliens 11-13. Start slot A/B: 32-40 (earlier 72-game run). Victory types: 59 base destruction, 13 dominance. Duration: **median 15:29**, min 10:49, max 28:30.

Mixed AI strategies (72 games): Humans 65%, Machines 50%, Aliens 35% — see *Known problems*.

Difficulty (mirror matches): Normal beat Easy 10-2; Hard vs Easy 9-3; **Hard vs Normal 13-11** (only marginally stronger).

Equal-cost combat simulations (`meridian-sim combat --counters`, `comps`): 21/24 designed counter relationships hold (e.g. Lancer > Colossus, Flak > Harrier, Skitter > Coil Cannon); exceptions: Spinecaster loses to Bastion, Ranger loses to Mantis at equal cost, Bastion–Ravager draw. Mixed-army equal-cost battles: Humans–Aliens 9-1, Humans–Machines 3-7, Machines–Aliens 5-5 (equal-cost fights ignore production speed and regeneration, which full matches include).

### Performance
- Simulation, 200 vs 200 units with towers, projectiles, pathing (M4 Max host): **1.15 ms avg / 2.0 ms p95 per 20 Hz tick** while both armies are above half strength; 100 vs 100: 0.48 ms; 50 vs 50: 0.28 ms.
- Renderer in the **iPhone Duo simulator** (uses the Mac GPU, *not representative of phone hardware*): 347 live units / 1,550 nodes at 58–60 fps; 100 units at 60 fps.
- **Not measured on a physical iPhone** — no device was available.

## Known problems / limitations

- **No on-device measurements** (performance, thermals, touch feel). Simulator only.
- **Fold transitions not verified**: the layout adapts to size changes and was checked at the cover-screen size (Duo simulator) and an inner-screen-like size (iPad mini simulator), but live fold/unfold could not be exercised (toggling simulator screen power crashed SpringBoard). Device rotation also did not take effect on the Duo cover screen in the simulator.
- AI-vs-AI games median **~15.5 min**, below the 20–30 min target (human-vs-AI games are expected to run longer; not measured).
- Strategy/faction interaction: aggressive Humans 11/12 wins, aggressive Aliens 2/12 (small samples).
- Hard AI only marginally stronger than Normal.
- AI never uses transports, Bastion brace, or Sentry Tower modes (players can); it doesn't build expansion HQs.
- Pathing is flow-field + local separation: large blobs can congest in narrow chokes; no formation-preserving avoidance.
- Remembered enemy buildings show their live state rather than a last-seen snapshot.
- No multiplayer (humans only command slot 1; the other commanders are AI).
- Sprites face left/right only (mirrored), no per-frame animation beyond bobbing, recoil flash and effects.

## Next priorities

1. Profile on a physical iPhone (Instruments: frame time, energy); reduce node count (merge shadows/rings into the body texture, cap effects) if needed.
2. Verify fold/unfold on device; preserve camera centre across size changes.
3. Lengthen AI games toward 20–30 min (stronger early defence, slower aggression ramp) and fix the aggressive-strategy imbalance.
4. Make Hard measurably stronger (multi-prong attacks, harassment, better army splitting, transport drops).
5. Audio, unit voice/feedback, last-seen fog snapshots, more maps and 2v2.

## Mission 2: presentation overhaul (v0.2)

Simulation, balance, AI, economy, unit stats and victory conditions are unchanged. The core tests still pass 9/9, including the deterministic replay hash. The only core addition is a read-only `World.anyEntity(_:)` accessor used by the renderer for death animations. The prototype is tagged `v0.1-prototype`.

**Implemented** (art direction in `docs/ART_DIRECTION.md`):
- **Terrain:** shader-drawn terrain with blended biomes, animated water and foam, and relief lighting.
- **Environment:** faceted rock formations, alien flora, three tree species, new ore and gold deposits.
- **Atmosphere:** cloud shadows, vignette, motes, drifting fog-of-war haze.
- **Units:** 4-frame animation for all 45 units (legs, wheels, treads, engines), an automatic rim-light pass, team rings, faction motion language (sway, judder, breathing, banking), recoil, hit and cloak tints.
- **Buildings:** all 24 redesigned with faction architecture, plus pulsing lights and cores, faction-specific construction effects, production smoke and sparks, damage smoke and fire, and collapse into rubble.
- **Combat effects:**
  - glowing projectiles, missile smoke trails and arcing artillery,
  - forked lightning, two-layer rail beams, melee slashes,
  - 8-frame fireballs, shockwaves, flying debris and scorch or ichor decals,
  - faction death animations, camera shake, capture light-pillars.
- **Interface:** tactical-glass HUD, site strip, portraits and stat chips, production rings and queue badges, multi-select tiles, control-group previews, idle-worker badge.
- **Screens:** live-battle main menu, styled pause, game-over and tech tree.
- **Audio:** synthesized and spatialised effects with a global throttle, an ambient score, volume settings.

**Measured (simulator on an M4 Max host, not phone hardware):** the renderer stress test (`-stress N`) holds a 16.7 ms p95 frame time at 50, 100 and 200 units per side. With 298 live units the average is 18.5 ms over the first 300 frames, which include startup, then 60 fps. Texture generation at match start takes 0.28 s. An audio bottleneck (per-shot `stop()`/`play()` on the main thread) cut the frame rate to 36–44 fps in large battles. It was found with `-perf nosound` and fixed by queueing buffers onto permanently running voices from a background queue, with a global trigger budget.

**Before/after:** `docs/screenshots/compare/*.jpg` (same scripted scenarios, `tools/capture.sh`). The inner-screen layout is at `docs/screenshots/after/07_inner_screen_ipad_mini_proxy.png`.

**Visual limitations:**
- Sprites face only left or right (mirrored); there are no front or back views and no turret rotation.
- Animations are 4 procedural frames plus transforms, not hand-keyed.
- Audio is synthesized and functional, but I couldn't listen to it.
- All performance numbers come from the simulator.
- The cover/inner fold transition and device rotation remain unverified (see above).

## Mission 3: combat presentation (v0.3)

Simulation, balance, stats, production and victory are unchanged. Core tests pass 9/9 and UI tests 3/3 (the new `testSpectatorBattle` drives Battle Lab: FOLLOW, ½× speed, CINEMA). The `meridian-sim combat --counters` output is byte-identical to the recorded results. The core gained only renderer-facing event data: impact `power` and `surface`.

- **Reproducible staged battle:** `-battle N`, or **Battle Lab** in the main menu. Combined-arms rosters for each faction, deterministic formation, both sides attack-moving.
- **Combat visuals, readability and spectator mode:** see `docs/combat/REVIEW.md`. That covers weapon families, power- and surface-aware impacts, artillery telegraphs, wrecks, damage reactions, class markers, the battle camera, the spectator HUD, adaptive effect quality (3 tiers, auto) and trauma-based shake.
- **Before/after:** `docs/combat/before/` and `docs/combat/after/`, each with timed mid-combat screenshots and a demo video, plus close-ups in `after_closeup/`.

### Performance (in-app renderer; Xcode 27.1 simulators, iOS 27.1, Apple M4 Max host; **not phone hardware**)

Staged battle, all units fighting (moving, pathing, projectiles, deaths). Averages are per 2-second window after the 2-second start-up window; *sim* is time inside `match.step()` per frame and *scene* is our SpriteKit update work.

| Screen | Per side | Frame (p95) | sim avg / max | scene update | Peak nodes |
|---|---|---|---|---|---|
| iPhone Duo cover, 466×678 pt | 50 | 16.7 ms | 0.29 / 2.6 ms | 0.57 ms | 1,279 |
| iPhone Duo cover | 100 | 16.7 ms | 0.61 / 4.1 ms | 0.70 ms | 1,716 |
| iPhone Duo cover | 200 | 16.7 ms | 1.20 / 8.6 ms | 0.77 ms | 2,493 |
| iPad mini, 744×1133 pt (unfolded-size stand-in) | 50 | 16.7 ms | 0.30 / 2.5 ms | 0.43 ms | 1,300 |
| iPad mini | 100 | 16.7 ms | 0.60 / 4.5 ms | 0.60 ms | 1,714 |
| iPad mini | 200 | 16.7 ms (avg 16.8–17.1) | 1.34 / 10.2 ms | 0.75 ms | 2,489 |

- The first run on a freshly booted iPad simulator stalled, with 150 ms frames that our update code didn't cause. The adaptive quality system dropped to tier 0 as designed. The re-run held 60 fps.
- The headless simulation stress test (`meridian-sim stress`) is unchanged.
- The Duo's inner display couldn't be selected in the simulator, so the iPad mini stands in for the unfolded size.

## Mission 4: tactical movement (v0.4)

Full report with methodology and every number: `docs/tactics/REPORT.md`.

- **Formations:** role-based ranks in three shapes (balanced, assault, defensive), selected from a Formation button in the command card (hotkey F).
- **Movement:** group cohesion, heading smoothing, friend avoidance, stuck recovery, melee fan-out, ranged kiting, aircraft strafing.
- **Tactical AI:** it gathers before attacking and uses a per-faction formation doctrine, flanks with fast units, retreats into Bloom (Brood) and defends sites.
- **Spectator camera:** frames the engaged units of both sides.
- **Tactical test harness:** `meridian-sim tactics`, nine deterministic scenarios with overlap, density, stuck time, weapon uptime, arrival, response and survival metrics. Behaviours can be switched off one at a time (`--disable`) for A/B attribution.
- **Measured against the baseline** (same harness, same seeds):
  - overlap fell at 50v50 (2.6% → 0.6%), 100v100 (13% → 5.3%) and 200v200 (28% → 13.8%),
  - stuck time at 200v200 fell from 108 to 46 unit·s,
  - Ranger melee contact fell from 41% to 25%,
  - wall and corridor completion are unchanged at 100%, with t90 within 1 s.
- **Cost:** simulation at 200v200 rose from 0.87 to 1.55 ms per tick (headless) and 1.79 ms in-app. The renderer still holds 60 fps in the simulator.
- **Tests:** core 13/13 (4 new tactics tests). Counter duels: 21 of 24 unchanged; 3 changed, listed in the report.
- **Balance regressions, reported and not compensated:**
  - Machines vs Aliens shifted about 10 points toward Aliens (48-game samples: 18–30 → 13–35).
  - Colossus vs Ranger flipped because Rangers now kite slower melee.
  - Tournament overall: Humans 56%, Machines 38%, Aliens 56% (baseline 54/52/44).
- **App support:** `-scenario <name>` runs any tactical scenario in the app with the battle camera.

## How to build, play and test

See `README.md`.

## Mission 5: the living battlefield (tag `v0.5-world`)

Renderer-only; the simulation, stats, AI and controls are unchanged. Full write-up with before/after images, video and performance numbers: `docs/world/REPORT.md`.

- **Per-map biomes:** Amber Meadows, Verdant Delta (flowing river, mist banks) and Rust Plateau (cracked earth, luminous pools, dust devils).
- **Wind:** gusts across the grass; a shader sways grass, reeds and trees.
- **Cosmetic day/night cycle** (Settings toggle): lit buildings, light pools, searchlights, headlights, aircraft nav lights, fireflies, shooting stars.
- **Working buildings** for all three factions.
- **Visible economy:** harvest chips, carried loads, "+N" deliveries, idle-worker markers, toppling trees.
- **Production and arrival feedback;** research-complete light columns.
- **Persistent pooled battle scars:** craters, scorch, residue, tread marks, lingering wrecks, smouldering ruins.
- **Unit personality:** weapon charge-up, hover bob, idle glances; support and worker role rings.
- **Ambient wildlife:** flocks with shadows, fish, critters that flee troops, sky-rays.

## Mission 6: more commanders (teams, free-for-all, victory modes)

- **Two to four commanders** per match, each with a faction and a team letter (A–D). Same letter = allies: they share vision and detection, never damage each other, capture sites together (the ally with the most units on a site takes it) and win together. Free-for-all is the default when everyone has their own team. The setup screen has an **Add Commander** button, a team picker per slot, and refuses to deploy while everyone is on one team.
- **Victory modes.** *Annihilation* (the standard mode): destroy every enemy structure; a commander with no structures left is eliminated and their remaining forces disband; the last team standing wins. *Dominance* (optional): the previous territorial countdown, counted per team, on top of annihilation.
- **Bigger battlefields.** 2 players 112², 3 players 128², 4 players 144² (Quick: 84/96/108). The generator now builds every layout with N-fold rotational symmetry around the centre, so every base has the same ground, resources, sites and distances to its neighbours; two-player maps keep their original layouts. Three-player maps are round (the corners are crag) because a square cannot be made three-fold symmetric. Sites: 7 on two-player maps, 2N+1 otherwise (centre + a home flank and a contested boundary site per commander); Riverbend grows a river along every boundary with fords.
- **AI** aims at the nearest enemy commander still in the fight and defends an ally's base within reach of its own.
- **Saves** store teams and the victory mode. Saves from before team play are not offered: the map is rebuilt from the seed and the generator changed (save format 2). The game-over screen shows a column per commander; the spectator HUD groups them by team.
- **Harness:** `meridian-sim match --p0 humans --p1 machines --p2 aliens --p3 humans --teams 0,0,1,1 --victory annihilation --map riverbend`. App: `-players 4 -teams 0,0,1,1 -victory annihilation`.
- **Tests:** `TeamTests` (four-player maps rotate onto themselves tile for tile; 3- and 4-player starts are supplied and connected; shared vision; no friendly fire; team capture; elimination and team victory; victory modes; team save round trip; a 2v2 AI match completes).
- **Not measured:** phone performance with four commanders (up to 800 units and a 144² map). In the simulator the texture bank for four rosters builds in 3.9 s (2 players: 5.2 s).
- **Verified on macOS (Xcode 27.1):** `swift test` all pass; app builds; UI tests pass on the iPhone Duo simulator (iOS 27.1). 60 seeds × 2–4 players × 3 layouts × standard/quick: every start has ≥6 iron, ≥2 gold, ≥8 wood within 13 tiles and every base and site is connected. Headless 2v2 on all three maps and 3-player free-for-all all finish (20–45 min).
- **Fixes after first compile:** resource nodes on tile boundaries broke four-fold symmetry (rotate the tile, not the point); the home flank site on 3–4 player Riverbend/Highlands sat on the same side as the boundary site (on Riverbend, across the river in the neighbour's sector), now on the far side at 0.42 rad like Crossroads.
- **1v1 balance:** two-player maps keep their bases and sites, but obstacles and forests are drawn from a different random sequence. 108-game tournaments (`--seeds 6`): before this mission Humans 69%, Machines 24%, Aliens 57%; after it 74/26/50. The difference is within noise; the drift from the 54/52/44 table above predates this work.
- **Screenshots:** `docs/screenshots/teams/` (in-app 2v2 and three-way Riverbend; generator layouts for every map and player count).
