# Image prompts for the Tripo remakes

Workflow: generate a concept image from the prompt, check it reads clearly, then feed it to Tripo's Image to 3D. Export a GLB named with the unit's id into `/Users/perry/Desktop/tripo/`.

Rules for every image:

- One object, the whole model in frame, three-quarter front view, plain light grey background, no ground shadow and no text.
- Team colour is **bright pure blue**, on the marked panels only. The renderer swaps that blue for each player's colour.
- Lattice glow is **turquoise**, not blue, so it isn't mistaken for team colour.
- Vehicles: turret and guns pointing forward. Aircraft: level flight with landing gear up. Creatures: the head clearly at one end.

Rigging in Tripo: skip it for everything here, except Shockframe and Arc Sentry. Those two can try the Humanoid rig. If it fails, skip it and I'll handle them.

Every prompt ends with the same style line, so each block can be copied as it is.

## Concord vehicles and aircraft

**h_buggy: Strider Buggy**
```
Strider Buggy, fast four-wheeled military raider buggy, open steel roll-cage frame, huge off-road tyres on long-travel suspension, twin autoguns on a pivot mount behind the driver seat, armoured nose plate, olive-drab and gunmetal angular armour, hazard-yellow stripes, amber headlights, bright pure blue side panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**h_bastion: Bastion Tank**
```
Bastion Tank, main battle tank, wide tracked hull with heavily sloped front armour, large angular turret with one long main cannon pointing forward, armoured side skirts over the tracks, folded hydraulic bracing legs at the rear corners, olive-drab and gunmetal angular armour, hazard-yellow stripes, amber lights, bright pure blue turret side panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**h_mortar: Mortar Carrier**
```
Mortar Carrier, six-wheeled armoured artillery truck, armoured cab at the front, large heavy mortar tube on a rotating rear platform angled steeply upward, shell racks along the sides, folded stabiliser legs, olive-drab and gunmetal angular armour, hazard-yellow stripes, amber lights, bright pure blue cab door panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**h_minelayer: Mine Layer**
```
Mine Layer, compact tracked military engineering vehicle, large rotating mine-dispenser drum and chute at the rear, stacks of disc-shaped proximity mines on side racks, small autogun turret on the roof, olive-drab and gunmetal angular armour, hazard-yellow stripes, amber warning lights, bright pure blue side panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**h_kestrel: Kestrel**
```
Kestrel, agile single-seat air-superiority jet fighter, forward-swept wings, twin angled tail fins, tinted cockpit canopy, missiles on underwing pylons, glowing amber engine exhausts, level flight with landing gear retracted, olive-drab and gunmetal angular panels, hazard-yellow stripes, bright pure blue wingtips, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**h_harrier: Harrier**
```
Harrier, heavy carpet bomber aircraft, wide armoured flying-wing body with four turbofan engines, open bomb bay with rows of bombs underneath, small armoured cockpit at the front, level flight with landing gear retracted, olive-drab and gunmetal angular panels, hazard-yellow stripes, amber navigation lights, bright pure blue wing panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**h_dropship: Dropship**
```
Dropship, VTOL military troop transport, boxy armoured troop bay with a rear loading ramp, four tilting ducted-fan engines on short stub wings, cockpit at the front, folded mechanical repair arms under the nose, olive-drab and gunmetal angular armour, hazard-yellow stripes, amber lights, bright pure blue hull side panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

## Lattice machines

The Lattice is a machine intelligence. Its look is obsidian, gunmetal and chrome, with hexagonal plates and floating rings.

**m_fabricator: Fabricator**
```
Fabricator, hovering robotic worker drone, hexagonal obsidian core body with a floating chrome ring around it, four articulated manipulator arms holding welding and cutting tools, cargo clamp underneath, glowing turquoise circuitry and core, bright pure blue hexagonal armour plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_recon: Recon Drone**
```
Recon Drone, small flying sensor drone, lens-shaped obsidian body with one large glowing turquoise eye sensor at the front, rotating chrome antenna ring, small thruster fins, no weapons, bright pure blue hexagonal plates on top, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_arc: Arc Sentry**
```
Arc Sentry, human-sized bipedal combat robot, backward-jointed legs, torso built around a two-pronged arc projector crackling with turquoise electricity, hexagonal obsidian and gunmetal armour, chrome joints, bright pure blue shoulder plates, standing pose with arms slightly out from the body, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_shockframe: Shockframe**
```
Shockframe, heavy humanoid brawler robot, hunched broad shoulders, huge oversized fists with hammer plates on the forearms, exposed chrome pistons at the joints, glowing turquoise chest core, obsidian and gunmetal hexagonal armour, bright pure blue shoulder plates, standing pose with arms slightly out from the body, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_piercer: Piercer**
```
Piercer, four-legged robotic railgun platform, spider-like armoured legs, long twin-rail cannon mounted on top pointing forward with turquoise energy between the rails, obsidian and gunmetal hexagonal armour, chrome joints, bright pure blue hull plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_flak: Flak Drone**
```
Flak Drone, hovering anti-air battery, floating hexagonal obsidian platform held up by a glowing turquoise anti-gravity ring underneath, quad-barrel flak cannon turret on top angled upward, gunmetal and chrome details, bright pure blue platform side plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_repair: Repair Drone**
```
Repair Drone, compact flying repair robot, rounded obsidian body with a floating chrome ring, three thin articulated arms ending in glowing turquoise nanite spray emitters, small thruster pods, bright pure blue top plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_jammer: Jammer**
```
Jammer, low six-legged crawler robot carrying a tall obelisk antenna array with emitter fins, faceted stealth-angled obsidian armour, faint turquoise glowing emitter lines, gunmetal legs, bright pure blue panels on the obelisk base, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_runner: Skirmish Runner**
```
Skirmish Runner, fast low robotic tank, sleek wedge-shaped obsidian hull on two narrow tracks, small beam-emitter turret on top pointing forward with a turquoise lens, gunmetal and chrome details, bright pure blue side plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_bulwark: Bulwark Walker**
```
Bulwark Walker, massive two-legged war walker, heavy armoured obsidian torso, two large pulse cannons as arms with glowing turquoise muzzles, thick legs with chrome hydraulic pistons, hexagonal gunmetal plating, bright pure blue torso side plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_coil: Coil Cannon**
```
Coil Cannon, robotic magnetic siege gun, very long coilgun barrel wrapped in glowing turquoise rings, mounted on a heavy tracked obsidian base with anchoring spikes at the corners, gunmetal and chrome details, bright pure blue base plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_suppress: Suppression Array**
```
Suppression Array, hovering field-projector machine, central obsidian obelisk with three floating chrome rings stacked around it, emitter dish at the base glowing turquoise, small thrusters, bright pure blue hexagonal panels on the obelisk, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_vector: Vector**
```
Vector, heavy unmanned interceptor aircraft, angular delta wing with no cockpit, long-range missile racks under the wings, glowing turquoise engine exhausts and seams, obsidian and gunmetal hexagonal panels, level flight, bright pure blue wing panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_quake: Quake Drone**
```
Quake Drone, bulky flying seismic bomber drone, heavy obsidian body on four thruster pods, large piston hammer and seismic charge hanging underneath glowing turquoise, gunmetal and chrome details, level flight, bright pure blue top plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**m_carrier: Carrier Drone**
```
Carrier Drone, large flying transport drone, long hexagonal obsidian hull with a cargo bay, tall relay antenna mast on top, several glowing turquoise anti-gravity rings underneath, gunmetal and chrome details, level flight, bright pure blue hull side panels, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

## Brood creatures

The Brood look is dark purple-brown chitin, bone spines, wet flesh and bio-green glowing pores.

**a_sporewing: Sporewing**
```
Sporewing, huge floating alien transport creature, swollen translucent gas-bladder body like a jellyfish with veins and bio-green glowing spores inside, ribbed chitin belly forming a cargo pouch, long trailing tendrils underneath, small membranous fins along the sides, no legs, dark purple-brown chitin and wet flesh, bone ridges, bright pure blue markings on the chitin plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_glint: Glint**
```
Glint, small fast alien scout creature, low four-legged insect body built for darting, oversized glowing bio-green compound eyes, long sweeping sensory antennae and a wide sensory frill behind the head, thin bone-tipped legs, dark purple-brown glossy chitin, bright pure blue markings on the back plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_wisp: Wisp**
```
Wisp, swift alien flying predator in level flight, slender dragonfly-wasp body, four long membranous wings spread flat, barbed spine-tipped tail, small claws tucked under the head, glowing bio-green eyes, dark purple-brown chitin, bright pure blue markings on the thorax plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_shadeling: Shadeling**
```
Shadeling, sleek alien ambush predator, low panther-like four-legged body, pale bone ridges and spines along the back, long whip tail with a blade tip, glowing bio-green eyes, glossy dark purple chitin plates with lighter edges, bright pure blue markings on the shoulder plates, prowling pose, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

## Brood regeneration (the other 11)

Rigging: use Tripo's **Humanoid** rig for the upright ones (Mantis, Needleback, Lifebinder), and its **four-legged** rig for Ravager, Spinecaster, Rupturer and Seeder, the same rig Shadeling got. Skip rigging for Weaver, Skitter, Colossus and Blightwing; I'll build those skeletons myself.

**a_weaver: Weaver**
```
Weaver, small six-legged alien worker creature, rounded armoured back carrying glowing amber resin sacs, spindly jointed legs, large harvesting mandibles at the front, glowing bio-green pores, dark purple-brown glossy chitin, bright pure blue markings on the back plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_mantis: Mantis**
```
Mantis, fast upright alien warrior shaped like a praying mantis, two huge serrated scythe-blade forelimbs raised, lean armoured chitin body on two strong digitigrade legs, narrow head with glowing bio-green eyes, dark purple-brown chitin, bone spikes, bright pure blue stripes on the thorax, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_ravager: Ravager**
```
Ravager, hulking four-legged alien brute, massive cleaver-shaped bone blades on its front limbs, heavy plated hunched shoulders, low armoured head with a drooling fanged jaw, thick muscular legs, dark purple-brown chitin and wet flesh, bone spikes, glowing bio-green pores, bright pure blue shoulder plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_spinecaster: Spinecaster**
```
Spinecaster, four-legged alien artillery creature, hunched arched back bristling with long acid-dripping launchable spines angled forward, glowing green acid glands along the flanks, sturdy legs, low armoured head, dark purple-brown chitin, bright pure blue markings on the back plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_needleback: Needleback**
```
Needleback, upright two-legged alien anti-air creature like a giant porcupine, tall quills fanned upward along its back with glowing bio-green tips, short clawed arms, armoured head looking up, dark purple-brown chitin, bright pure blue markings on the chest plates, standing pose with arms slightly out from the body, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_lifebinder: Lifebinder**
```
Lifebinder, graceful upright alien healer creature, tall slender body, glowing bio-green heart-sac pulsing in the chest, long flowing tentacle tendrils from the shoulders, soft translucent membranes, delicate head with glowing eyes, dark purple-brown chitin, bright pure blue markings on the shoulder plates, standing pose with arms slightly out from the body, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_skitter: Skitter**
```
Skitter, tiny fast alien swarm creature, beetle-crab hybrid, low wide armoured shell, six sharp pointed legs, snapping pincer jaws at the front, glowing bio-green eyes, dark purple-brown glossy chitin, bright pure blue markings on the shell, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_colossus: Colossus**
```
Colossus, towering alien behemoth, elephant-sized armoured body on six massive pillar legs, huge curved bone tusks, crushing armoured battering-ram head, glowing green vents along the back, dark purple-brown chitin plates, bone spikes, bright pure blue carapace plates on the back, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_rupturer: Rupturer**
```
Rupturer, bloated four-legged alien bio-artillery creature, giant translucent green acid sac swelling on its back, short sturdy legs, a wide mortar-like spitting orifice on top of the head, dark purple-brown chitin and wet flesh, bright pure blue plates along the sides, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_seeder: Spore Seeder**
```
Spore Seeder, slow heavy four-legged alien creature, large mushroom-like spore cap on its back covered in glowing bio-green pods, fungal growths along the legs, low head with feeding tendrils, dark purple-brown chitin, bright pure blue markings on the flank plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```

**a_blightwing: Blightwing**
```
Blightwing, large flying alien bombardier in level flight, wide bat-like leathery wings spread, long neck with a spitting fanged maw, bulging acid gland dangling under the belly, short tucked legs, long tail, dark purple-brown chitin and membrane, bone spikes, bright pure blue markings on the back plates, single game asset concept render, three-quarter front view from slightly above, entire model in frame, centered, plain light grey background, soft even studio lighting, no ground shadow, no text, no logos, stylized-realistic AAA sci-fi RTS look, PBR materials, worn and weathered, bold readable silhouette
```
