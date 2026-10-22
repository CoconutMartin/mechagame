# Handoff: phase 5 end, pulse scan, play-test fixes (next session)

Written 2026-10-22. Branch: `ccr-495597aa-87iw0a` (all work committed and pushed; it holds all of
`ccr-7a73ea4b-jwqirv` plus this session's commits). Read CLAUDE.md, AGENTS.md, this file, and in DESIGN.md
the sections named below and "Reminders for the user".

## Done this session (commits, oldest first)

- `ebdeb5d` Phase 5: rubble pieces are removed when they touch the ground (DESIGN "Rubble on the ground").
- `89672cf` Phase 5d: camera shake for each building chunk a mech smashes. Phase 5 closed.
- `de52551` `tools/mech_gen/weapons.py` matches the checked-in data (zoom FOV 43.4, shield blocks_dodge).
- `58f094c` Pulse scan: back pack part with aux slots, grade 1 to 3 data, key X, wire frame pass, highlight
  through walls, HUD line (DESIGN "Pulse scan").
- Fixes from the user's play test (2026-10-22, 11 items, then more):
  - `4385290` Garage camera: free look (full turn, up and down), zoom to 2 m, middle mouse pan.
  - `2111e41` Dodge: the 2026-10-15 quick step slow-down removed; smooth hand-over to the walk speed.
  - `6fdb5d8` Melee: the combo chains after a miss, ordered input buffer; bare jointed hands (no fist block).
  - `366cfbf` Part HP labels above dummy and enemy mechs hidden (`MechSpawner.show_label`).
  - `fa1c51c` Beam Rifle: 3 charge lamps on the stock (Blender, `ChargeLights`).
  - `26f05f9` Walk: the ankle pitch sign was wrong (toes dug in, two contacts per step).
  - `1f82eb8` Stagger rules (full Beam Rifle beam, 3 Auto Cannon hits, 85% of an SMG magazine) and a
    recoil and shake table for all guns (DESIGN "Stagger rules and recoil").
  - `a83eb64` ADS look-down limit (-14 deg), rifle grip fingers, head on the rifle line in ADS, heavy free
    left arm, SMG / Heavy Rifle / Shotgun along the forearm with level shoulders (DESIGN "Arm and head fixes").
  - `b638ed2` Shield guard on LMB; Shoulder Cannon braces 0.4 s before firing; every shoulder weapon stops
    the mech on the ground while it fires (DESIGN "Shield guard", "Shoulder weapon stop to fire").
  - `e13f30e` Jump: athletic charge crouch, small guard (no "offering"), eased clip blends, smooth change
    from the top of the jump into the fall (DESIGN "Jump fixes", under "Phase 4").
  - `2e46088` Horizontal mouse aim +50% (`MechCameraRig.yaw_sensitivity_scale` 1.5).
- Tests after the last code change: test_stability (67), test_hit_reactions, test_weapon_hands,
  test_shoulder_stop all 0 failures. Earlier in the session also: test_weapon_ranges (54050), test_range,
  test_break_time, test_pulse_scan (19), test_melee_combo (61), test_dodge_exit, test_stagger_rules (36).
  Nothing was played by hand: all checks are headless runs and software renders.

## Open points (for the next session)

1. User decisions:
   - Walk: the default walk speed (7.74 m/s) plays the Jog clip (a run with flight, 0.24 m bob), and the
     clips land the foot at body speed (0.3 m heel slide). Fix by a new walk clip in Blender, or a leg IK
     foot plant (about 100 lines). Ask which.
   - SMG elbow: level shoulders were chosen; a vertical elbow tilts the shoulder block again. Confirm.
   - Shoulder Cannon while boosting: it waits for the mech to stop ("STOP TO FIRE"). Option: Q cancels the
     boost and stops the mech.
   - Pixel-art look as a graphics option (the user asked about pxl and reference-asset-compiler: neither
     fits; a Godot low-resolution + palette + outline pass would). Not started.
2. Known small issues:
   - A single-frame 9 to 11 deg roll of the right upper arm during a jump (`measure_jump_apex.gd`, frames 42
     and 99; the elbow does not move; not the swing limit search). Cause not found.
   - The take-off frame turns the legs 25 deg in one frame (the push straightens them).
   - One-hand gun stocks overlap the right forearm armor 0.15 to 0.46 m (approximate hull check).
   - ADS look-down limit is global (the Beam Sniper gets it too; it has no clipping there).
   - Beam Rifle lamps are only a few pixels wide from the game camera.
   - Beam Rifle beam ticks (5.1 points) now cause small flinches on the target.
3. Pulse scan "later" list (DESIGN "Pulse scan"): back pack model and HP, garage lists, warning sound and
   screen, AI use.
4. Carried over: `docs/HANDOFF_phase3_melee_arms.md` small points (fist arm pop, AIMelee chain keys,
   `garage_data.py` ids, `weapon_controller.gd` size).

## How to work here

- Everything in `docs/HANDOFF_stagger_ranges_fixes.md` and `docs/HANDOFF_phase5_destruction.md` "How to
  work here" still holds (Git LFS, Godot 4.7.2 in `/tmp/claude-0/godot/`, `--import` after a new
  class_name or model, xvfb renders, never hand-edit `scenes/mech/sanggigilid.tscn`).
- Parallel agents (AGENTS.md) worked well with strict file ownership. Lessons:
  - Never kill Godot by name (`pkill -x Godot` hit other agents' runs); use `timeout`.
  - Render logs can grow to GB (a per-frame error in `graphics_settings.gd:56` under xvfb): redirect to
    a file, grep it, delete frame PNGs after making contact sheets. The disk filled once (16 GB).
  - Agents stop at the usage limit; resume them with SendMessage after the reset.
  - Shared `.tres` files: stage only your own lines when several agents edit one file.
- New tools this session (`tools/godot/`): test_pulse_scan, render_pulse_scan, test_dodge_exit,
  measure_dodge_blend, test_melee_combo, render_bare_hand, test_stagger_rules, test_shoulder_stop,
  render_shield, measure_jump_apex (APEX_CHARGE, APEX_VERBOSE, APEX_BONE); render_walk rewritten (WALK_CSV,
  WALK_LEGACY, WALK_OFF=all); `tools/blender/beam_rifle_indicators.py`.
- The user's PC: `git fetch origin`, `git checkout ccr-495597aa-87iw0a`, `git pull origin
  ccr-495597aa-87iw0a`, `git lfs pull`. If Git refuses because of an untracked `*.import` file, delete that
  file (Godot makes it again).

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md (the latest bullets and the reminders) and
> docs/HANDOFF_pulse_scan_and_fixes.md. Remind me of the open reminders and the decisions in "Open points",
> then wait for my play-test results.
