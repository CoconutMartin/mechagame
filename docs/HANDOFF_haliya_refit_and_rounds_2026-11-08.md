# Handoff: rounds of 2026-11-01 to 11-08, Haliya on the SGG legs, and the waist ball joint (first step)

Written 2026-11-08. Branch: `ccr-c2198b2d-613uc0` (all work committed and pushed; it continues from
`ccr-4f661095-l2et8e`, `docs/HANDOFF_beam_rifles_shotguns_2026-11-01.md` on that branch). Read CLAUDE.md, AGENTS.md,
this file, and in DESIGN.md: "Three rigs (user request 2026-11-05)" with the paragraphs just above it ("Skeleton
comparison SGG-101 and HLY-101", "HLY refit decision", "HLY refit built", "HLY refit, legs only"), and "Reminders for the
user". DESIGN.md is about 150 KB: search the headings, do not read it whole.

## First step for the next session: the torso joins the legs at the hip ball joint

User (2026-11-08): "The torso should be joined at the hip 'ball joint'. HLY legs + SGG torso makes the torso float,
while SGG legs + HLY torso puts it inside the leg - it should not be this."

Cause: in a garage mix the `torso` bone offset (pelvis to torso, the waist) comes from the CORE's rig
(`scripts/mech/skeletal_part_models.gd`, `CORE_BONES` = torso, head, upper_arm_L, upper_arm_R; `_set_offsets` copies
the core rig's offsets). SGG's waist is 0.66 m, Haliya's 0.23 m. So HLY legs + SGG core leave a 0.4 m gap (the SGG waist
ball floats), and SGG legs + HLY core put the HLY chest into SGG's pelvis belt. Pictures:
`docs/hly_legs_aligned_mixes_{front,side,back34}.png` and `_walk_*.png` (tool `tools/godot/render_hly_mixes.gd`).

Plan (check with the user before big changes; this follows the user's words):
1. Define a waist ball joint per part, as data:
   - Legs: the socket point on top of the pelvis (where the ball sits), in the pelvis bone's frame. SGG has a visible
     waist ball (white sphere between pelvis and chest); find its center in the SGG legs or core mesh. Haliya: the top of
     its pelvis / the bottom of its chest.
   - Core: the ball (plug) point under the chest, in the torso bone's frame.
   Store both in the part .tres (`LegPart`, `CorePart` or `PartData` fields, e.g. `waist_socket`, `waist_ball`), with a
   tool that measures them from the meshes (like `write_arm_hand_data.gd` does for hands).
2. Assembly: the torso bone offset = legs.waist_socket - core.waist_ball (in the pelvis frame; rest rotations are the
   same on every rig). Same mech (SGG on SGG, HLY on HLY) must give its current offset (0.66 m / 0.23 m) to within a few
   mm, so nothing changes for the pure mechs.
3. Clips: `_drop_position_tracks` already drops the clips' position keys on core bones; check the torso still moves
   right in walk, run, jump, kneel, melee clips and the Pile Bunker clips, and that hitboxes (`SkeletalHitboxes`), the
   back pack offset (core `back_pack_offset`, relative to what?), the head and arms follow.
4. Tests: `tools/godot/test_garage_swap.gd` (8 mixes) must check the gap: the core ball within a few cm of the legs
   socket in every mix, at rest and in walk. Run the usual set for SGG and `MECH=haliya` (see "Checks" below).
   Render the mixes again (`render_hly_mixes.gd`) and look at them: no float, no overlap at the waist.

## Done since 2026-11-01 (oldest first; details in DESIGN.md)

- Shotgun 2 and 3 are pulse weapons (heat, `WeaponData.heat_gun`), electric pellets, arcs, hits; screen disruption when
  their pellets hit the player; Shotgun 3 fires in the left hand and snaps its heads.
- Pile Bunker: fixed charge pose with walking; Shift+1 (leap) and Shift+2 removed (default clip 3); new user clips for
  Shift+3 (Flying Knee) and Shift+5 (Uppercut); Hook and Uppercut swapped so the Pile Bunker arm strikes; clip 3 cut after
  the hit with a soft landing; 60% shorter run (6.4 m); stake aims at the crosshair and the body turns toward the target;
  no other-arm twitch.
- Hit reactions 50% smaller, only a full stagger bar interrupts.
- Beam rifles: BR4 fires on release (6 s cool down, small auto crosshair return), BR3 rings light in sequence, BR2 coil
  heat colors, BR1 recoil and crosshair drift through the beam.
- Drones: saucer flight, rim barrel port, synced 4.5 m random hops after each burst, return path around the body, no
  cool down and unlimited use for now, 50 m lock.
- Boosters: gust wind, rocket plume, nozzle heat, petals in the jump charge; Boost Pack light blue panel fire; no fire on a
  dodge step. Light, Aux and Heavy Packs removed.
- Mech: Ctrl kneel pose, steady head (parallel to the barrel in ADS), kneeling Auto Cannon lines up with the crosshair,
  green crosshair in optimal range, Auto Cannon tap fire, vertical mouse aim 50% slower, torso twist 2x.
- Skeleton comparison SGG vs HLY (`tools/godot/compare_skeletons.gd`, `docs/skeleton_compare_sgg_hly.png`).
- Haliya: a full refit onto SGG's skeleton was tried and rejected by the user ("giraffe" neck, long arms, wide hips).
  Now "legs only": SGG's leg chain (pelvis 6.10, thigh 2.75, shin 2.18, ankle 1.05 with ankle blocks), Haliya's own
  offsets and shapes above the pelvis and in the arms. Part weights from volume, rule A (`measure_part_volumes.gd`
  WRITE=1): Haliya 28.9 t, SGG 48 t.

## How it works (Haliya pipeline)

Blender 4.0.2 here cannot open the Blender 5 .blend files, so the Haliya refit runs in Godot tools:
`haliya_ref_build.py` -> `haliya_rig_light.py` -> `export_mech_parts.py` into `models/mechs/haliya/source_light_rig/`
(the original light-rig export, input only) -> `tools/godot/refit_haliya_parts.gd` (uses `haliya_legs_aligned_rest.gd`,
`haliya_connectors.gd` for the ankle blocks, `haliya_mesh_kit.gd`) -> `tools/godot/make_haliya_rig.gd` (SGG clips + Haliya
arm carry and walk lean) -> `godot --headless --path . --import` -> `MECH=haliya godot --headless --path . --script
res://tools/godot/build_sanggigilid.gd` -> `write_arm_hand_data.gd` -> `measure_part_volumes.gd` WRITE=1. Do not export
from Blender straight into `models/mechs/haliya/` (it undoes the refit).

## Open (see DESIGN "Reminders for the user")

1. First step above: the waist ball joint for garage mixes.
2. Decision: the new Shift+3 jump lifts 3.4 m (old 1.8 m); lower it (`air_share` 0.25)?
3. Play test everything built since 2026-11-01 (list in the reminders and `docs/PLAYTEST_CHECKLIST_2026-11-04.md`).
4. Known issues: 20 m Pile Bunker targets out of reach; clips put the empty arm into the body in places; the Hook miss
   case; head follows a steep one-hand aim only a few degrees; kneeling rifle muzzle touches the ground; AI holds the BR4
   trigger at drones; two drone test checks flake; Haliya's pelvis reads as a flat bar.
5. Drones: restore the round 5 limits (10 s cool down, 6 drones, one launch at a time) when the user says so.
6. Older: thumb grip, PS1 look off, broken-part look.

## Checks

Godot is not in a fresh container: download 4.7.2 (allowed by the user):
`https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`, link
`/usr/local/bin/godot`, then `git lfs pull` and `godot --headless --path . --import`. If a model under
`models/mechs/haliya` loads as invalid (`valid=false` in its .import), the import ran on LFS pointers: delete
`.godot/imported/haliya_*` and import again.
Usual set (`godot --headless --path . --fixed-fps 60 --script res://tools/godot/<name>.gd`, with `MECH=haliya` for
Haliya where supported): test_garage_swap, test_weapon_hands, test_stability, test_kneel_pose, test_head_clip,
test_clip_self (CASES=rest), test_pile_bunker_hit (NUMBER=3), test_melee_combo; measure_foot_slide.gd. Some tests
measure real time and must run without `--fixed-fps` (test_shotgun_2, test_shotgun_3). Long tests: run them in the
background. Agents in parallel share the CPU: AI timing checks can flake under load; rerun alone.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, docs/HANDOFF_haliya_refit_and_rounds_2026-11-08.md. Remind me of the open reminders, then
> start the first step: join the torso to the legs at the hip ball joint for garage mixes.
