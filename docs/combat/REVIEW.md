# Combat Presentation Review

## Test scenario (reproducible)

`-battle 50` launch argument (`GameController.setupBattle`): 50 Concord vs 50 Lattice units on the open Test Arena, with a deterministic roster and formation.

**Concord:** 13 Rangers, 6 Breachers, 6 Lancers, 4 Skyguards, 3 Field Medics, 3 Strider Buggies, 4 Bastion Tanks, 4 Mortar Carriers, 1 Mine Layer, 3 Kestrels, 3 Harriers.

**Lattice:** the mirror roles (Arc Sentry, Shockframe, Piercer, Flak Drone, Repair Drone, Skirmish Runner, Bulwark Walker, Coil Cannon, Suppression Array, Vector, Quake Drone).

**Formation:** assault in front, then infantry, then anti-armor/AA/support, armor, aircraft, and siege at the rear. Both sides attack-move into each other.

`tools/battle_capture.sh <dir> <N> [device] [video-seconds]` captures timed screenshots at 5/8/11/14/18 s and an optional video. All captures use the iPhone 18 Pro Max simulator (iOS 27.1) on an Apple M4 Max host.

## Before (v0.2-visual): `docs/combat/before/`

### What works
- Team rings separate the two armies instantly, even inside the blob.
- Big silhouettes (Bastion, Bulwark, Coil Cannon) are recognisable.
- Rail beams and arc lightning read well. Projectiles exist and travel.

### What doesn't
1. **Fog of war hides half the battle in spectator mode**; the observer sees through one side's eyes.
2. **Camera too far out and badly framed.** Infantry are about 20 px tall; the fight is a thin diagonal line, and the camera doesn't zoom to fit it.
3. **The front line collapses into one blob** where you can't tell who is shooting whom. Muzzle flashes and sparks are tiny at this zoom.
4. **Aircraft get lost**: they have the same ring as ground units and no strong altitude cue.
5. **Light and heavy hits look the same.** A Coil Cannon slug and a rifle round produce similar sparks, and splash attacks don't show their area.
6. **Artillery is unreadable**: shells arc but nothing marks where they will land (no danger telegraph).
7. **No wrecks.** Units vanish after a short animation, so the battlefield doesn't accumulate a sense of carnage.
8. **Critical damage is invisible** unless you happen to look at a 2 px health bar.
9. **The spectator HUD is the player HUD**: resources and build controls are irrelevant, and there is no army comparison.
10. **The battle is fast.** It is mostly decided within about 12 seconds of contact; this is a balance property that stays unchanged. Presentation has to read instantly, and slow-motion viewing helps.

## After (Mission 3): `docs/combat/after/`, `after_closeup/`, `battle50_demo.mp4`

Same scenario, same capture script. Demo video: `after/battle50_demo.mp4` (about 20 s, 540 px). The before video is `before/battle50_demo.mp4`, and `after/battle50_filmstrip.jpg` holds six frames from it.

### Fixes for each problem above
1. **Spectators see everything:** fog is hidden in observer modes.
2. **The battle camera (`Render/BattleCamera.swift`)** tracks a decaying heat map of impacts and deaths, weighted by damage. It commits to an engagement for at least 3.5 s and only switches when another fight is 1.7× hotter. It moves on a critically damped spring and auto-zooms to frame the 8-tile core of the fight. Zoom is capped at 1.45 on narrow phone screens so infantry stay legible. Any pan or pinch hands control to the player for 6 s. A FOLLOW toggle is in the spectator HUD.
3. **Muzzle flashes come from the weapon end,** sized by damage and styled per weapon family. Recoil scales with the gun's punch, vehicles pitch up when firing, and units jolt when hit.
4. **Class markers under every unit:** a plain ring for infantry and light vehicles, a double ring for heavy armour, a crosshair ring for siege, and a dashed ring for aircraft. Aircraft also bank into turns and leave engine streaks. Rings get bolder when zoomed out.
5. **Hits scale with power and react to what they hit:**
   - armour shows sparks plus a white-hot penetration flare and molten shards (power ≥ 24),
   - Brood flesh splashes green ichor, human flesh shows a dark-red mist, ground throws up dust.
   - Area attacks draw a shockwave ring at the true splash radius, then a family-specific blast.
   - Anti-air hits burst in the sky: flak smoke for Concord, cyan rings for Lattice, spore puffs for Brood.
6. **Artillery telegraph:** every arcing splash shell shows a pulsing red reticle where it will land, sized to its blast and brightening as it approaches. Suppression Array and Jammer fields show a permanent faint dome.
7. **Wrecks:** vehicles and heavies leave a scorched, burning hull for about 5 s:
   - Concord fire,
   - Lattice cyan sparks,
   - Brood a collapsing carcass with an ichor pool.

   Heavies add a secondary explosion. Aircraft spiral down trailing smoke and crash. Infantry deaths stay faction-specific.
8. **Critical damage (< 30% HP):** the team ring pulses red, vehicles trail smoke (plus sparks for the Lattice), and Brood units drip ichor. Health bars only appear below 70% HP, on selection, or at very close zoom.
9. **Spectator HUD:** army-strength tug-of-war bar, unit and kill counts, ½×–4× speed, FOLLOW, CINEMA (hides the HUD), PAUSE, RESTART, EXIT. The main menu now has **Watch AI Match** and **Battle Lab 50/100/200**.
10. **Explosions are staged:** a white flash frame, an 8-frame fireball, a ground shockwave, arcing debris, a rising smoke column with embers for heavy blasts, and a scorch decal. Screen shake uses a decaying trauma model: it offsets the world rather than the camera so tracking stays smooth, scales with damage and only fires on screen. It can be turned off in settings.

### Readability changes
- Decorative flora is smaller and desaturated, so it never competes with units.
- Selected units draw thin lines to their current targets, and a single selected unit or tower shows its weapon range ring.
- Turning uses a quick squash through profile instead of an instant mirror flip.

### Remaining problems
- **The contact point is still a dense blob.** Unit separation is a simulation property and was deliberately left unchanged. Team rings and target lines help, but individual duels in the middle of 200 vs 200 are hard to follow.
- **Battles are decided quickly** (a balance property). Use ½× speed in the spectator HUD to watch details.
- **Two facings only** (mirrored), with no turret rotation.
