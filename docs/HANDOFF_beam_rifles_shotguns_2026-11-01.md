# Handoff: Beam Rifles 2 to 4, Shotguns 2 and 3, manual shotgun fire, the GunWeapon load fix

Written 2026-11-01. Branch: `ccr-4f661095-l2et8e` (all work committed and pushed; it continues from
`ccr-4df8074c-yr96fd`, `docs/HANDOFF_swappable_parts_2026-11-01.md`). Read CLAUDE.md, AGENTS.md, this file, and in
DESIGN.md the sections "Beam Rifle 2", "Beam Rifle 3", "Beam Rifle 4", "Shotgun 2", "Shotgun 3" and "Reminders for the
user".

## Done this session (oldest first)

- Beam Rifle 2 (user picture `models/guides/beam_rifle_2_ref.png`): rapid beam bolts with heat (`BeamRepeaterWeapon`),
  bolts from the middle barrel, the two rail bores flash red; more body and character.
- Beam Rifle 3 (`beam_rifle_3_ref.png`): PPC-like (`BeamCannonWeapon`): 0.3 s charge, one bolt
  (`scenes/weapons/ppc_bolt.tscn`), 3 s cool down; grey rings and side rails glow orange during the charge; red prong
  tips at a shot; more body and character.
- GunWeapon load cycle fixed: a GunWeapon subclass scene failed to load first ("Could not resolve class GunWeapon").
  `WeaponController` and `WeaponPose` ask `MechWeapon.is_forearm_gun()`, `is_shoulder_gun()`, `wants_brace()`
  instead of naming the classes.
- Beam Rifle 4 (`beam_rifle_4_ref.png`): 10 m, one barrel, more heft; lower armor as thick as the upper; charged
  particle rifle (`ParticleRifleWeapon`): hold LMB to charge 3 s (the mech may walk), release, the mech stops and
  braces (ShoulderBrace, now usable by the right hand weapon), one large amber shot
  (`scenes/weapons/particle_shot.tscn`); three light bars light body -> midsection -> barrel and fade over the 3 s cool
  down; equal, centered bars; vents on all three segments; left aim hold 0.6 m forward.
- Shotgun 2 (`shotgun_2_ref.png`): one hand, three heads open at each shot (`PulseShotgunWeapon`), 2 shots/s.
- Shotgun 3 (`shotgun_3_ref.png`): one hand, four heads in an X spin while held (`SpinPulseShotgunWeapon`); 0.2 s hold
  fires the X pulse; the spin slows after; 0.05 s wait.
- Manual fire for every shotgun (`WeaponData.semi_auto`, `GunWeapon` queues one shot per press; `AiPilot` lets go
  between shots).
- Pulse looks (user reference `models/guides/pulse_rune_ref.jpg`): `PulseShot` + `shaders/pulse_rune.gdshader`:
  Shotgun 2 a horizontal rectangle, Shotgun 3 an X, about crosshair size on screen; scattered cyan particles, no
  outline, soft edges, two 25% cuts (measured 53 to 55% of the first scattered count). Pellet patterns follow
  (`pattern_half_deg` 7.2 x 4.15 degrees).

## User decisions this session

- Beam rifles and shotguns are new weapons next to the old ones (Beam Rifle, Shotgun stay). Picture colors; no
  lettering or decals on the shotguns.
- Beam Rifle 2 rapid shots; 3 PPC; 4 sniper, then the charged particle shot with stop to fire (charge while moving).
- Shotguns are one hand and fire once per press.
- Amber for Beam Rifle 4's lights and shot.

## How it works (code map)

- Weapon scripts (`scripts/weapons/`): `beam_repeater_weapon.gd` (Beam Rifle 2), `beam_cannon_weapon.gd` (3),
  `particle_rifle_weapon.gd` (4), `pulse_shotgun_weapon.gd` (Shotgun 2; pattern, heads, glow, arc),
  `spin_pulse_shotgun_weapon.gd` (Shotgun 3). All extend `GunWeapon` (drop, dual guns and AI treat them as guns).
  `scripts/effects/shot_glow.gd` (flash glow on meshes), `scripts/effects/pulse_shot.gd` (pulse look).
- New `MechWeapon` methods: `is_forearm_gun`, `is_shoulder_gun`, `wants_brace`, `raise_on_trigger` (false = LMB does
  not raise a two-hand weapon, so walking is not locked), `holds_raised`. New `WeaponData.semi_auto`.
- Models: `tools/blender/beam_rifle_2_build.py`, `beam_rifle_3_build.py`, `beam_rifle_4_build.py`,
  `shotgun_2_build.py`, `shotgun_3_build.py` (start from an empty file; `blender -b --python <script>`). The beam
  rifles use the first Beam Rifle's grip place; the shotguns the first Shotgun's grip place, so the hand markers fit.
  Scenes `scenes/weapons/beam_rifle_2..4.tscn`, `shotgun_2..3.tscn` are hand made (markers copied from the Beam
  Rifle / Shotgun scenes; left hand markers moved where the armor is deeper). Data in `data/weapons/`; garage lists in
  `data/garage_catalog.tres` (hand edit) and `tools/data_gen/garage_data.py`; beam rifle data also in
  `tools/mech_gen/weapons.py`.
- Tests (`tools/godot/`): `test_beam_rifles.gd`, `test_shotgun_2.gd`, `test_shotgun_3.gd` (0 failures at the end);
  regression after the shared changes: test_weapon_hands, test_stability, test_weapon_ranges, test_stagger_rules,
  test_shoulder_stop, test_drone_pack, test_beam_arm_break, test_part_models: 0 failures.
- Tools: `measure_left_aim.gd` (left hand gap at the aim hold, AIM_DZ), `render_beam_rifle_glow.gd` (a rifle alone
  dark and lit), `screenshot_charge.gd` (charge, shot, cool down; game camera and a camera above the rifle),
  `screenshot_shot.gd` (gun at rest, at the shot, the shot in flight). Pictures in `models/<weapon>/`.

## Open (see DESIGN "Reminders for the user")

1. Play test Beam Rifles 2, 3, 4 and Shotguns 2, 3 (looks, holds, firing, values). Beam Rifle 4: the full cycle is
   6.5 s (3 s charge, about 0.5 s to stop and raise, 3 s cool down); the user asked for 6 s; offer to start the cool
   down at the release.
2. Pulse looks: after the soft edges they read about crosshair size, not 10% larger; offer to scale `half_deg`.
   The look keeps its size on screen for 16:9 only.
3. The AI drone tactics hold the trigger of Beam Rifle 4 like a gun (no release at drones).
4. Older items: the Haliya upload; SGG play test after the part split and swappable parts phase 2; SGGv2 paused;
   backpacks and drones; Pile Bunkers and melee; arm clipping decision; thumb grip and Cross Punch upload; test mode on
   and PS1 look off; pixel-art option.

## Known small issues

- Godot is not in a fresh container. Download 4.7.2 (the user allowed it):
  `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` to
  `/tmp/claude-0/godot/`, link `/usr/local/bin/godot`, then `git lfs pull` and `godot --headless --path . --import`.
- Blender here is 4.0.2 (system `blender`); the new build scripts work with it. No GPU: render pictures with Cycles
  CPU (`/tmp` scripts in this session set `engine = "CYCLES"`, 12 samples) or in Godot with xvfb and
  `--rendering-driver opengl3`.
- Emissive colors wash out to yellow or peach in Godot: keep glow energy low and colors deep (see Beam Rifle 3 and 4
  notes); Beam Rifle 4's bars are unshaded for that reason.
- Wait in game time (physics frames) in screenshot tools: xvfb renders slowly.
- `find_children("Name*")` misses renamed siblings; match `scene_file_path` (see the shotgun tests).

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, docs/HANDOFF_beam_rifles_shotguns_2026-11-01.md. Remind me of the open reminders, then
> continue: I will send play test results or the next weapon picture.
