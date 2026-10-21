# Mission 4: Tactical Movement, Formations & Battlefield Intelligence

Before this mission the code was tagged `v0.3-combat`; the measured baseline is commit `02de2e6`. All headless numbers come from `meridian-sim tactics`, which uses deterministic, fixed-seed scenarios on an Apple M4 Max. In-app captures use Xcode 27.1 simulators running iOS 27.1, not phone hardware.

## 1. Observation (baseline)

I watched the 50v50 battle in the app (`docs/combat/after/`, `docs/tactics/before_filmstrip.jpg`) and measured nine scenarios. Prioritised problems:

1. **Armies collapse into a dense mass as size grows.** Overlap, defined as units whose bodies intrude more than 15% into a neighbour, rises from 1% at 20v20 to 13% at 100v100 and 28% at 200v200. Peak crowding reaches 22–24 units within 1.5 tiles.
2. **Units wedge and stall:** 88–108 unit-seconds stuck in the 50v50 and 200v200 battles.
3. **Ranged units get caught by melee:** Rangers spent 41% of the kite scenario in melee contact.
4. **No army shape.** Units deploy and march as a loose block or a thin diagonal line, with siege, support and assault units mixed together.
5. **Spectator framing** leaves empty terrain around small skirmishes.

## 2. What was built

**Movement** (`MeridianCore/Movement.swift`). All of this is deterministic.
- **Mixed-strength separation:** heavy hulls (radius ≥ 0.65) push 1.6× harder. Idle friends keep a small personal-space pad.
- **Heading smoothing:** a 65/35 blend with the previous heading, accepting direction changes under about 107°, which removes jitter.
- **Look-ahead avoidance:** a mover slips around a stationary friend in its path instead of shoving it.
- **Stuck watchdog:** after about 2 s with no progress far from the goal, the unit sidesteps at alternating ±69°.
- **Line-of-travel cache (8 ticks):** in open ground, units walk straight to their own formation slot, so the formation keeps its shape on the march. Around obstacles they share the group's flow field.

**Formations** (`Formations.swift`). Ranks are 0 front (heavy armour, assault, melee), 1 line (rifles, fast), 2 support (anti-armour, anti-air, healers, specialists) and 3 rear (siege). Aircraft fly a band over the middle.
- **Balanced:** straight ranks.
- **Assault:** a forward wedge, with fast units on the front wings.
- **Defensive:** a curved shield wall and a compact core.

Slots keep each unit's left-to-right order to avoid crossing paths, and the formation is centred on the tap. Artillery is capped at (weapon range − 6) tiles behind the front rank so it stays in reach of the fight. Mixed and partial selections work, and groups of three or fewer keep their shape.

**Group cohesion.** A group shares the slowest member's pace: units ahead of the group's average progress slow down, and laggards run. This applies only in open ground; in chokepoints it switches off.

**Combat positioning:**
- **Melee fans out:** when a target has two or more attackers, melee units approach from spread angles.
- **Ranged kiting:** ranged units give ground between shots to slower melee units that are targeting them.
- **Aircraft strafe** their target (range ≥ 3 only, so bombers still hover over theirs).

**Tactical AI** (`AI.swift`).
- **Gather, then attack:** it assembles at the staging point (70% present, or 25 s) before attacking.
- **Faction doctrine:**
  - Concord switches to *defensive* against melee-heavy enemies and to *assault* against artillery.
  - Lattice uses *balanced* (*defensive* for the tech doctrine).
  - Brood uses *assault*.
- **Flanking:** fast raiders swing to a flank point 9 tiles off the attack axis.
- **Retreat:** Brood retreat into owned Bloom sites to regenerate.
- **Territory:** Normal and Hard defend contested sites.
- **No fragile squads:** site-capture squads exclude siege, support and scouts.
- **Difficulty:** Easy skips assembly and site defence. Hard keeps its focus-fire and retreat micro.

**Controls.** A Formation button in the unit command card cycles Balanced → Assault → Defensive (hotkey F; one slot, so it fits the Duo cover screen). Move, attack-move, patrol and smart taps use it. Hold and Stop are unchanged.

**Spectator camera.** It frames units of both sides that fired or were hit in the last 2.5 s, falling back to the 8-tile core, and centres on that box. Zoom ranges from 0.75 (small skirmishes fill the screen) to a readability cap of 1.6 on phone-width screens.

**A/B switches** (`TacticsFlags`, `--disable kite,surround,cohesion,avoidance,mass,strafe,formations,frontline`) let each behaviour be measured in isolation. Two ideas were measured and **switched off by default** because the data didn't support them:
- **Target spreading** (penalising targets that already have attackers) cut weapon uptime by 3–8 points without reducing overlap.
- **A front-line gap between enemy lines** made no difference: enemy intrusion was already about 0%, because the visual "pile" comes from sprites drawn larger than collision bodies.

## 3. Results: baseline → final (same harness, same seeds)

| Scenario | Overlap % | Peak density | Stuck unit·s | Weapon uptime % | Other |
|---|---|---|---|---|---|
| 20v20 | 1.1 → **0.2** | 10 → 10 | 20 → 30 | 84 → **88** | |
| 50v50 | 2.6 → **0.6** | 14 → 13 | 88 → **68** | 90 → 86 | |
| 100v100 | 13.0 → **5.3** | 18 → 18 | 68 → 74 | 87 → 86 | |
| 200v200 | 27.9 → **13.8** | 22 → 22 | 108 → **46** | 83 → 78 | |
| Kite (12 Rangers vs 12 Mantis) | 4.6 → **0.0** | 14 → **9** | | | melee contact 41% → **25%** |
| Wall with two gaps (40 units) | | | 0 → 0 | | 100% arrived; t90 21.2 s → 22.2 s |
| Corridor, two groups crossing | 4.4 → **3.5** | | 0 → 4 | | 100% arrived; t90 30.4 s → 30.9 s |
| Siege protection | 16.6 → **6.7** | 24 → **21** | | 66 → 65 | siege alive 8/8 → 8/8 |
| Airstrike on a defended position | | | | | aircraft alive 5/14 → **6/14** |
| Command response (90% moving) | | | | | 0.2 s → 0.2 s (unchanged) |

Simulation cost at 200v200: 0.87 → 1.55 ms average per 20 Hz tick (max 3.5 → 4.6 ms). Full tables are in `baseline.md` and `final_tactics.md`.

## 4. Performance in the app (Duo cover simulator, 466×678 pt; not hardware)

| Per side | Frame (p95) | sim avg / max | scene update |
|---|---|---|---|
| 100 | 16.7 ms | 0.72 / 4.3 ms | 0.6 ms |
| 200 | 16.7 ms | 1.79 / 9.1 ms | 0.7 ms |

Mission 3 for comparison: 200 per side at 1.20 ms simulation.

## 5. Balance check (movement changes, no stat changes)

**Counter duels** (24 designed checks, equal cost): 21 keep the same winner. Three changed:
- **Spinecaster vs Bastion Tank:** loss → draw.
- **Bastion Tank vs Ravager:** draw → loss.
- **Colossus vs Ranger:** win → loss. This is kiting working as designed: Colossus are slower than Rangers, so equal-cost Rangers now give ground between shots and win. It contradicts the Colossus's "strong vs infantry blobs" role, so it's a real balance consequence of the movement change.

**72-game AI tournament (Normal):**

| | Baseline | After |
|---|---|---|
| Humans | 54% | 56% |
| Machines | 52% | 38% |
| Aliens | 44% | 56% |

Games run a median 17:19 (was 15:29). Dominance victories rose from 13 to 28 of 72.

| Pairing (24 games each) | Baseline | After |
|---|---|---|
| Humans vs Aliens | 16–8 | 14–10 |
| Humans vs Machines | 10–14 | 13–11 |
| Machines vs Aliens | 11–13 | 7–17 |

**Regression reported, not compensated:** Machines vs Aliens moved toward Aliens. A larger 48-game sample gives 18–30 at baseline (the baseline already favoured Aliens) versus 13–35 after, a shift of about 10 points. Attribution runs show no single behaviour responsible; the best single switch restores only 9–15.

An earlier version had Humans vs Machines at 6–18. That came from Ranger kiting and the melee fan-out. Narrowing both, and fixing an artillery-placement bug in the formations, brought it back to 13–11. Following your instructions, no unit statistics were changed. A deliberate balance pass is the right fix if this matters.

## 6. Remaining issues

- **The visual pile.** Sprites are drawn about 1.3× larger than collision bodies, so dense fights still look crowded even though measured enemy intrusion is about 0%. A separate pass could scale combat sprites down in dense areas or thin the visuals of the second rank.
- **The front still compresses at the point of contact** in 200v200: overlap is 13.8%, down from 27.9%.
- **Ranged kiting doesn't work against faster melee** such as Mantis and Skitter, by design: stepping back from a faster attacker just wastes shots.
- **Corridor congestion:** two opposing groups in a 3-tile corridor work through it, but with 4 unit-seconds of stuck time. There is no lane discipline (keep-right).
- **Formation cost:** formations are recomputed every time a group is re-ordered. The AI re-orders laggards each second, which is fine for performance but can reshuffle slots.
- **Machines vs Aliens** has shifted toward Aliens (above).
- **Kiting changed three counter duels,** most notably Colossus vs Ranger (above). A possible movement-side fix is to stop kiting against massive units; not done here, to keep the behaviour uniform and the result visible.
