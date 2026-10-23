# Difficulty retune

The goals:
- **Easy:** a 10-year-old can win.
- **Normal:** slightly easier than the old Easy.
- **Hard:** unchanged.

All changes are to the AI's decision-making only: how fast it reacts, how big its economy is, when it attacks, how big its attacks are and when it retreats. It gets no stat or resource bonuses or penalties.

Measured with `meridian-sim ladder --d0 X --d1 Y`. Each ladder covers 27 games: every faction pairing (mirrors included) on every playable map.

| Matchup | Before | After |
|---|---|---|
| Easy vs Normal | 11–16 | 0–27 |
| Easy vs Hard | 6–21 | 0–27 |
| Normal vs Hard | 16–11 | 7–20 |

New settings:
- **Easy:**
  - thinks every 4 s, aims for 6 workers, attack threshold 5600;
  - first attack no earlier than 13 minutes, at least 5 minutes between attacks;
  - attacks with at most 8 units and retreats after losing 30% of them;
  - builds no towers before 10 minutes, does no extra research before 15 minutes, and sends no site squads before 8 minutes.
- **Normal:**
  - thinks every 3 s, aims for 8 workers, attack threshold 5000;
  - first attack no earlier than 10 minutes, about 4 minutes between attacks;
  - retreats after losing 38% of the attack force.
- **Hard:** the original settings.

Note: AI-vs-AI ladders measure the AIs against each other, not against people. The settings changes (slower reactions, a smaller economy, later and smaller attacks) are what make the game gentler for a human.
