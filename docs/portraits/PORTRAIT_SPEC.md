# Meridian painted portraits: asset specification

A painted portrait is **one master image plus a few facial layers**. The game's existing portrait engine animates
them: gaze, blinking, speech timing and idle sway, all at once and continuously. Units without layers keep their
Swift-drawn portraits automatically.

- Code: `Meridian/Render/LayeredPortrait.swift` (loader and renderer) and `Meridian/Render/PortraitPipeline.swift` (template, validator, fixtures).
- Template: `docs/portraits/portrait_template.png`.
- Artwork lives in `Meridian/Portraits/<unitID>/`. Files there are bundled automatically.

## 1. Canvas

| | |
|---|---|
| Size | **1024 × 1024 px**, square (768 minimum). Every layer uses the **same canvas**. |
| Format | PNG, 8-bit RGBA, sRGB. |
| Visible area | The centre **965 × 965 px**. A 29 px margin on each side may be cropped by idle sway: keep it filled, but put nothing important in it. |
| Frame corners | The frame is chamfered: about 118 px triangles at the visible corners are cut. |
| Speaking light | A small green light sits in the top-right corner (about 150 × 150 px inside the visible area). Keep key detail out. |
| Display size | 66–78 pt, which is **198–234 px on iPhone**. Judge every portrait at that size. Detail finer than about 4 px at 1024 disappears. |
| Lighting | Light from the upper left, matching the units and buildings. |

## 2. Layers

All file names are `<unitID>_<layer>.png`, for example `a_colossus_eyes_open.png`.

| Layer | Required | Content |
|---|---|---|
| `base` | **yes** | The complete portrait with a **neutral face**: eyes open, looking straight ahead, mouth closed. Opaque edge to edge, including the background. |
| `eyes_open` | for blinking | The eye patch in its neutral state. If you supply `pupils`, paint this **without** the moving pupil (empty sclera or lens). |
| `eyes_half` | optional | The same patch, half closed. It makes blinks smoother. |
| `eyes_closed` | for blinking | The same patch, closed: eyelids, membrane or shutter. |
| `pupils` | optional | **Only** the moving part (iris, pupil, lens glow), centred, on transparent. Slid by the gaze. |
| `eyes_mask` | with `pupils` | White, opaque where the pupils may be seen (the eye opening), on transparent. Must lie inside the eye patch. |
| `mouth_closed` | for talking | The mouth or jaw patch, closed. It must match `base`. |
| `mouth_open1` | for talking | The same patch, half open. |
| `mouth_open2` | optional | The same patch, fully open. |
| `team` | optional | Team markings painted **white or light grey** on transparent. The game tints them with the owner's colour (blue or red). Paint those areas dark and neutral in `base`. |
| `fx_<name>` | optional | Glows: light on transparent, added on top. Listed in the JSON with what drives them. |

### No-ghosting rules (the validator checks these)

1. **One footprint per feature.** Every state of the eyes (`open`, `half`, `closed`) covers exactly the same area with opaque pixels. The same goes for every mouth state. Make the patch selection once and paint each state inside it. A state that covers less would let the base's own eyes or mouth show through.
2. **The base contains the neutral face**, and `eyes_open` (with its pupils centred) and `mouth_closed` match the base exactly inside their patches. Starting to animate then causes no visible pop.
3. **Soft edges only over identical pixels.** A feathered edge must sit where patch and base are the same (skin, shell, metal), never across the feature itself.
4. **Eyes and mouth don't overlap.** Leave a gap of at least 8 px so both can animate at the same time.
5. **Pupils stay inside the mask.** Leave room in the eye opening for the pupil to travel (`pupilTravel`).

## 3. `<unitID>_portrait.json` (optional; defaults shown)

```json
{
  "eyes":   { "pupilTravel": [0, 0], "halfAt": 0.2, "closedAt": 0.6 },
  "mouth":  { "thresholds": [0.12, 0.55] },
  "fx":     [ { "layer": "fx_glow", "blend": "add", "driver": "speech", "min": 0, "max": 1, "rate": 0.5 } ],
  "motion": { "sway": 1, "breathe": 1, "lookShift": 1 }
}
```

- `pupilTravel`: how far the pupils slide at full gaze, in master pixels (x, y).
- `halfAt` / `closedAt`: blink amount (0–1) at which `eyes_half` / `eyes_closed` show.
- `thresholds`: speech level at which `mouth_open1` / `mouth_open2` show.
- fx `driver`: `speech` (follows the voice line), `pulse` (sine at `rate` per second), `blink`, or `always`. `blend`: `add`, `screen` or `normal`. Opacity runs from `min` to `max`.
- `motion`: multipliers on the idle sway, the breathing, and how far the whole head shifts with the gaze. Use 0 for a rigid machine.

## 4. Workflow (per unit)

1. Paint `base` on the template, then hide the template.
2. Select the eye area generously, including some surrounding skin, shell or metal. Copy the selection to a new layer: that's `eyes_open`. Duplicate it and paint `eyes_half` and `eyes_closed` **inside the same selection**. If the pupils should move, paint them on their own layer, `pupils`, and make `eyes_mask` from the eye opening.
3. Do the same for the mouth or jaw: `mouth_closed`, `mouth_open1`, `mouth_open2`.
4. Optionally move team markings to `team`, and glows to `fx_…` layers.
5. Export every layer as a full-canvas PNG. Don't trim the canvas.
6. Check before adding to the game:
   `Meridian --validate-portraits <out-dir> <folder-with-your-pngs>`. It writes `portrait_report.txt` and `<unitID>_compare.png` (original against painted, through rest, gaze, blink and talk, at real display size).
7. Copy the files into `Meridian/Portraits/<unitID>/` and build. In the game, **long-press the portrait** to switch between painted and original.

## 5. Pilot portraits

The two pilot units currently hold **stand-in layers** cut from their Swift-drawn portraits (made with
`--portrait-fixtures`) to prove the pipeline. Replace them with painted files of the same names. The regions below
are where the stand-ins sit. Use them as a guide; your own regions are fine as long as the rules above hold.
Pixel coordinates are measured from the **top left** of the 1024 canvas.

### Arc Sentry (`m_arc`), Lattice

- **Subject:** the unit's chrome sensor sphere with a large cyan lens as its single eye, on a coiled neck above an armoured hex hull with a team band and a small LED strip. Gunmetal and polished chrome, cyan light, against a dark blue-steel feed with a faint hex grid.
- **Eye:** a lens centred at about **(512, 379)** with the glass about **300 px across**.
  - `eyes_open`: the lens with the glass empty and dark, no light inside. The patch is a circle about **340 px across**, centred on the lens.
  - `eyes_half` / `eyes_closed`: aperture blades half closed / fully closed.
  - `pupils`: the cyan iris glow and ring alone, centred on the lens.
  - `eyes_mask`: the glass circle (about 300 px).
  - JSON `pupilTravel`: about `[72, 56]`.
- **Mouth:** none. Speech is shown with glows:
  - `fx_speech`: cyan halo and small arcs around the sphere.
  - `fx_vox`: the LED strip bars lit.
- **Team:** the hull band (in `team`, painted light).
- **JSON:** `motion` `{ "sway": 0.6, "breathe": 0.5 }`. A machine barely breathes.

### Colossus (`a_colossus`), Brood

- **Subject:** an extreme close-up of the beast's armoured purple skull in three-quarter view facing right, cropped tight. It has bone dorsal spikes, a bone horn and tusk at the snout, and a heavy lower jaw lined with teeth. Glossy purple chitin and bone, green bioluminescent eye, a glowing team patch on the skull, a murky violet hive behind, lit from the side.
- **Eye:** a single slit-pupil bead eye centred at about **(696, 531)**, about **100 px wide**, under a heavy brow.
  - `eyes_open`: the eye with its dark surround and glint, without the green iris.
  - The patch is a circle about **145 px across**.
  - `eyes_closed`: a pale translucent membrane over the eye.
  - `pupils`: the green iris and slit.
  - `eyes_mask`: the eye opening (about 100 × 90 px).
  - JSON `pupilTravel`: about `[18, 11]`.
- **Mouth (jaw):** the patch covers **x 258–1024, y 621–1024**, the whole lower jaw and the space it swings into.
  - `mouth_closed`: the jaw shut, teeth meeting.
  - `mouth_open1`: half dropped, a glimpse of the throat.
  - `mouth_open2`: wide open, the throat glowing green.
  - Keep the patch clear of the eye patch (the eye patch ends near y 603).
- **Team:** the skull patch (in `team`, painted light).
- **fx:** `fx_eyeglow`, a soft green glow around the eye, `pulse` at 0.35 per second, opacity 0.15–0.55.

## 6. Performance (measured by the validator on the stand-ins)

Layers are decoded once at 256 px when a portrait is first shown (about 2–3 MB per unit while shown). The team
tint is made once per colour. Drawing takes about 2 ms per frame at 234 px on a Mac, under 7 % of a 30 fps frame,
and only the selected unit's portrait is drawn.
