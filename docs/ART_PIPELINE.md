# Art pipeline: from 3D models to isometric sprites

Meridian is a 2D SpriteKit game, but every unit, building and prop is a 3D model rendered into sprites. The game gets the look of a 3D RTS while keeping 2D's low cost on a phone: thousands of sprites at 60 fps, with no 3D scene at runtime.

![One unit rendered in 8 facings, with its team-colour mask below](showcase/pipeline_facings.jpg)

## Sources

| Asset | Source |
|---|---|
| All 45 units | Concept image from a prompt ([prompts](TRIPO_IMAGE_PROMPTS.md)), turned into a model with [Tripo](https://www.tripo3d.ai)'s Image to 3D and rigged there where it could be (the first soldiers came from text prompts and were rigged in Mixamo or Blender) |
| Buildings (24) | Tripo image-to-3D models (`art/tripo/buildings`), placed by `tools/blender/buildings.py`. Each is scaled to fill its footprint and shrunk if needed to fit under the canvas top. The original procedural builders remain as a fallback |
| Iron and gold deposits | Tripo models (`art/tripo/props`), three variants each, rendered by `tools/blender/props.py` |
| Rocks, trees and plants | Modelled procedurally in Blender Python (`tools/blender/props.py`). Hundreds appear on a map, and code gives endless variation |

Nothing is placed by hand in the Blender UI. Every asset can be rebuilt from scripts with one command, so changing a camera angle or material re-renders the whole game consistently.

## Matching the game's camera

The game uses a 2:1 isometric projection: a tile is 64×32 points. The Blender camera is orthographic, 30° above the horizon and rotated 45°. Its scale is set so one world unit covers exactly 32√2 points, so screen-right points along world (1, 1). Buildings render onto the same canvas size the game uses for each footprint, so they drop into place with no hand-tuned offsets.

## Animation

Most units are rigged and animate on real skeletons. `tools/blender/import_rig.py` brings a Tripo-rigged model in: VRM humanoid skeletons get Mixamo bone names, and creature skeletons are kept as they are.

**Humanoids: motion capture.** The soldiers, plus the humanoid mechs and aliens (Arc Sentry, Shockframe, Bulwark, Mantis, Needleback, Lifebinder), have Mixamo-compatible skeletons. The renderer judges each one's facing from which side its left hip is on, since Tripo doesn't always export them facing the same way. Three soldiers were auto-rigged by Mixamo and the Ranger by Tripo. Mixamo's rigger rejected the other four, so they were rigged in Blender: a skeleton was built from joint positions marked on front-view renders, then auto-weighted on a voxel-remeshed proxy and the weights transferred to the real mesh. `unit_render.py` retargets Mixamo clips onto each skeleton bone by bone. Each bone copies the clip's world rotation, corrected for the difference between the two rest poses, so one set of clips drives every humanoid whatever their proportions:

| Pose | Clip |
|---|---|
| idle | rifle idle |
| walk (4 frames) | rifle walk, in place |
| attack | firing rifle (Engineer: working on a device) |
| death (3 frames) | death, played once when the unit dies |

**Creatures: gaits read from the skeleton.** Tripo's creature skeletons are only partly named, so `AutoGait` in `unit_render.py` works from the skeleton's shape instead. A bone chain counts as a leg if the mesh it moves reaches the ground; bones often stop short of the toes, so the mesh decides. Each leg starts below the last bone it shares with another leg. Legs step in alternating sets (a trot on four legs, tripods on six), each swinging along its own axis and lifting as it comes forward. Tails, antennae and mandibles sway, and the attack raises the front legs. Older hand-built skeletons with named bones use fixed cycles:

| Body plan | Motion |
|---|---|
| biped | stride with knee bend and counter-swinging arms; strike raises both arms |
| quadruped | trot in diagonal pairs; attack rears and lunges |
| hexapod | alternating tripods; attack raises the front legs |
| flyer | wing beats with the outer bones lagging; attack dips the head and swings the legs forward |

Each unit renders **8 facings × 6 poses** (9 with death), from 48 to 72 frames per unit.

Vehicles, aircraft, drones and the few creatures Tripo couldn't rig use simple body motion on the mesh instead (`vehicle`, `aircraft`, `hover`, `flyer` and `multiped` in `unit_render.py`): pitch and bob on the move, banking in flight, wing beats, recoil when firing.

## Live portraits

`tools/blender/portraits.py` renders each rigged unit's head and shoulders for the selection panel:

- 5 head turns × 3 mouth openings, each with a team-colour mask.
- The head turns on the skeleton's head and neck bones.
- Talking is a shape key. The lower front of the head (jaw, mandibles, respirator) hinges down about a pivot behind it.

In game, `ModelPortrait` crossfades between head turns as the unit glances around. The mouth opens on each syllable of the unit's radio line. A long press on the portrait switches back to the hand-drawn version.

## Team colours

Each sprite has a matching grayscale mask marking where team colour goes. The mask comes from a hue detector that finds the bright blue panels on Tripo models and buildings. Building masks start the hue ramp further from cyan, because Lattice buildings carry a lot of turquoise glow. Procedural models flag their team material instead. Masks render with Blender's Raw view transform so their values stay linear. In game, SpriteKit multiplies the team colour through the mask, so one set of renders serves every player colour.

## Building lights

Buildings have pulsing glow points: beacons, cores and glowing pores. For Tripo buildings they are found automatically in the lit render. The script picks the brightest saturated spots and skips blue, because blue is team colour and gets tinted. The points are written to `b3d_<id>.json` together with the building's visual height, which places health bars and effects.

## Shadows and anchors

Buildings and props render over a shadow catcher, so their soft ground shadows are baked into the sprite. Props get a margin so shadows don't clip at the canvas edge. The game's sprite anchor accounts for the margin, so each object still sits on its tile.

## Running it

Blender runs headless with Cycles on Metal:

```bash
tools/render_units.sh h_breacher a_mantis   # listed units, one Blender process each (keeps memory flat)
tools/render_portraits.sh                    # live portraits for every rigged unit
/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/buildings.py
/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/props.py
```

Output goes straight into the app bundle folders (`Meridian/Units3D`, `Meridian/Portraits3D`, `Meridian/Buildings3D`, `Meridian/Props3D`). The Tripo `.glb` sources and rigged `.fbx` meshes (`art/rigged`) are kept out of git because of their size. The motion-capture clips (`art/anims`, skeleton only) are small and checked in.
