# Meridian: Three Fronts — Project Status

Original isometric 2.5D sci-fi RTS for iPhone (primary target: **iPhone Duo**, cover + inner screens), also runs on iPad and macOS for desktop testing.
Last updated: 2026-10-20.

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
- No audio, no save/load, 1v1 only, no multiplayer.
- Sprites face left/right only (mirrored), no per-frame animation beyond bobbing, recoil flash and effects.

## Next priorities

1. Profile on a physical iPhone (Instruments: frame time, energy); reduce node count (merge shadows/rings into the body texture, cap effects) if needed.
2. Verify fold/unfold on device; preserve camera centre across size changes.
3. Lengthen AI games toward 20–30 min (stronger early defence, slower aggression ramp) and fix the aggressive-strategy imbalance.
4. Make Hard measurably stronger (multi-prong attacks, harassment, better army splitting, transport drops).
5. Audio, unit voice/feedback, last-seen fog snapshots, more maps and 2v2.

## How to build, play and test

See `README.md`.
