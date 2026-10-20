# Meridian: Art Direction ("Twilight Frontier")

An alien frontier world at golden dusk, rendered in a slightly stylized, illustrative 2.5D. A warm key light comes from the upper left and cool violet shadows fall to the lower right. Each faction's emissive colour glows against the dusk palette, so armies stay readable at any zoom.

Every asset is generated in code (CoreGraphics drawings, GLSL shaders, synthesized audio). There are no third-party assets and no licensing constraints.

## Readability rules (mobile RTS first)

1. **Team rings under every unit.** The ring is the primary allegiance cue in large battles, and units are drawn about 18% larger than in v0.1.
2. **One light direction.** All sprites get an automatic rim-light pass (`Pen.lit`): a warm edge on the upper-left silhouette and a cool shade on the lower-right. This gives everything volume and a shared light.
3. **Health bars appear only when they matter.** They show when a unit is selected, below 60% health, or when zoomed in. Buildings always show them when damaged.
4. **Effects colour-code the weapon family:**
   - amber tracers and rockets: Concord
   - cyan arcs, rails and pulses: Lattice
   - green acid and bone spines: Brood
5. **Effects are budgeted** (about 50 new effect sprites per frame) and pooled.

## Factions

| | Concord (Humans) | Lattice (Machines) | Brood (Aliens) |
|---|---|---|---|
| Shape language | Angular, boxy, sloped armour | Hexagons, obelisks, floating rings | Curves, ribs, spines, sacs |
| Materials | Olive and steel, concrete, hazard stripes | Obsidian, gunmetal, chrome | Chitin, flesh, bone |
| Emissive | Amber windows, red beacons | Cyan circuitry and cores | Bio-green pores, heart glow |
| Motion | Marching sway, recoil kicks | Mechanical judder; ring glows when **linked** | Breathing squash and stretch, organic wobble |
| Construction | Grey-out and welding sparks | Cyan hologram flicker | Grows from a bud and pulses |
| Death | Soldiers fall; vehicles burn | Collapse, sparks, oil splat | Dissolve into an ichor splat |

## Battlefield

- **Ground:** a single GPU shader quad (`TerrainLayer.groundSource`) blends grass, moss, dirt, rock and water from a pre-blurred data texture. It adds world-space detail noise, wildflowers, ore stains and gold glints, fake relief lighting from the elevation map, and animated water with depth, ripples, glints and shoreline foam.
- **Rock formations:** faceted boulder clusters, taller in the interior of rock areas.
- **Flora:** grass tufts, reeds by water, glowcaps on moss, violet crystal shards.
- **Wood:** three tree species (teal spire pine, amber broadleaf, lantern tree).
- **Atmosphere:** drifting cloud shadows (multiply blend), a vignette, floating motes, and fog of war rendered as drifting haze.

## Interface

- "Tactical glass": chamfered dark panels with a faction-accent corner tick and edge gradient (`UI/Style.swift`).
- Drawn resource glyphs (iron ingot, gold crystal, timber log), a diamond site-control strip, portraits framed in team colour, stat chips, segmented health bars, production rings on command buttons, and multi-select type tiles.
- The main menu plays a live, silent AI-vs-AI battle behind the panels.

## Audio

Synthesized at launch (`Game/SoundEngine.swift`):
- weapon families, small and large explosions, UI feedback, construction, capture and alert stingers,
- a 32-second generative ambient score.

Effects are panned and attenuated relative to the camera and throttled globally. The pause menu and main menu have Master, Effects and Music volume sliders plus a screen-shake toggle.
