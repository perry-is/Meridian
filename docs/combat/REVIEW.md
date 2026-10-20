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
