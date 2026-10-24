# Handoff: wrist, arms, jump strength, brace snap and recoil (next session)

Written 2026-10-24. Branch: `claude/blissful-curie-9w50m7` (all work committed and pushed). Read CLAUDE.md,
AGENTS.md, this file, and in DESIGN.md the sections named below and "Reminders for the user".

## Done since docs/HANDOFF_pulse_scan_and_fixes.md (commits, oldest first)

- `1365724` Garage rebuild settles the mech pose (hands hung off the wrists in the paused garage); Q/E cancel
  the boost; small shield guard higher; pulse scan ends as a wave.
- `d345942`, `bafd104` Jump fall one smooth cross-fade; arm swing limit takes the least-lean elbow turn (no Beam
  Sniper flicker, hands stay on the grips); thumb wraps the grip (DESIGN "Thumb over the grip").
- `e0d0486` Q/E snap the mech to the brace at once (stance = 2 s jump charge crouch); shields inactive on LMB
  (`MechShield.lmb_raises`); pulse ring 70 m/s, wire frame halved, no converge sphere; test mode
  (`data/test/test_mode.tres`: free energy, free scans).
- `9469df5` Aim: camera rays start at the mech (a wall behind the mech is never the target).
- `e39e04a` Jump strength follows the jump height (calm short hops); feet at standing width on landing.
- `0e46049` Torso twist by weight class (light 70, medium 45, heavy 25 deg each side); shoulder cannons push the
  mech back 0.5 m per shot, missiles 0.25 m each; brace feet 0.5 m wider per armed cannon.
- `fb78331` Wrist: the hand model's wrist roller sits on the forearm's wrist pin (DESIGN "Wrist on the forearm").
- `f256c12` Arms: one-hand guns along the forearm, level shoulders with one weapon, Beam Sniper elbow out in
  ADS, stride arm swing (DESIGN "Arm fixes 2026-10-24").
- Tests after the last commit, all 0 failures: test_weapon_hands, test_melee_combo, test_thumb_wrap,
  test_stability (67), test_hit_reactions, test_shoulder_stop, test_dodge_exit, test_stagger_rules (36),
  test_pulse_scan, test_aim_behind. Nothing was played by hand.

## Open points (for the next session)

1. Waiting for the user's play test of all the above.
2. Known small issues:
   - Beam Sniper ADS stutter (user: on hold).
   - Beam Sniper: left shoulder block pitched 39 deg at ADS; stock overlaps the forearm armor box 0.30 m at
     aim, 0.21 m at rest; at rest and in the jump guard the right block rolls 10 deg (elbow out and up).
   - One-hand guns at aim: shoulder block tops differ 0.11 m; left-hand gun stocks overlap the forearm armor
     about 0.2 m while walking.
   - Auto Cannon: fist 0.18 m off the handle (the handle is 0.94 m from the wrist pin, the hand reaches
     0.78 m; move the handle about 0.16 m toward the wrist).
   - Pile Bunker while boosting: the arm hits its length limit, fist lag up to 0.42 m. Weapon hand markers
     were tuned for the old hand place: moving them toward the reach (0.37 to 0.65 m) would help.
   - Jump launch frame: a one-frame pop scaled by strength (41 deg at a full charge).
   - Two single-frame arm jerks of 6 to 9 deg in a full-charge fall with the Beam Sniper.
   - `scripts/ui/debug_hud.gd:83` prints "Invalid access to property 'current' on Nil" every frame headless.
   - `shaders/pulse_scan_converge.gdshader` and `data/animations/arm_swing_run.res` are unused (ask before
     deleting).
3. Reminders (DESIGN "Reminders for the user"): thumb fix in Blender; turn the test mode off after the tests;
   pixel-art option; the older play-test items.

## How to work here

- Everything in `docs/HANDOFF_pulse_scan_and_fixes.md` "How to work here" still holds (Godot 4.7.2 in
  `/tmp/claude-0/godot/`, `--import` after a new class_name, xvfb renders, never hand-edit
  `scenes/mech/sanggigilid.tscn`: run `tools/godot/build_sanggigilid.gd`).
- Parallel agents with strict file ownership worked again. A rate limit stopped one agent; SendMessage resumed it.
- New tools this session (`tools/godot/`): measure_wrist_gap, measure_wrist_pin, measure_wrist_garage,
  render_wrist, render_garage_hands, measure_jump_fall, measure_jump_clips, measure_jump_scale, test_thumb_wrap,
  render_thumb, render_thumb_probe, test_aim_behind, measure_arms (and _probe, _solve, _search, _swing),
  render_rifle.
- The user's PC: `git fetch origin`, `git checkout claude/blissful-curie-9w50m7`, `git pull origin
  claude/blissful-curie-9w50m7`, `git lfs pull`. If Git refuses because of an untracked `*.uid` or `*.import`
  file, delete that file (Godot makes it again).

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md (the latest bullets and the reminders) and
> docs/HANDOFF_arms_wrist_brace.md. Remind me of the open reminders and the known issues, then wait for my
> play-test results.
