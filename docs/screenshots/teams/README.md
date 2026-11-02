# Multi-commander battlefields

- `app_*`: the app on the iPhone Duo simulator (Release), spectator mode after a 180 s warp, seed 3:
  `-autostart -spectate -players 4 -teams 0,0,1,1 -victory annihilation -map riverbend` and `-players 3`.
  The `_minimap` crops show the bottom-left minimap (the spectator sees through commander 1's team's fog).
  Recapture with `TEST_RUNNER_TEAM_SHOTS=<dir> xcodebuild … test -only-testing:MeridianUITests/TeamsCaptureUITests`.
- `layout_<map>_<N>p.png`: the generator's output for seed 3, one 5×5 block per tile. Grass/dirt/moss greens and browns,
  rock grey, water blue; iron light grey, gold yellow, wood dark green dots; HQs in player colours
  (P1 blue, P2 red, P3 yellow, P4 purple); strategic sites as white squares. Four-player maps rotate onto themselves
  tile for tile; three-player maps are round with crag corners.
