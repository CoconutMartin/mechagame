# Handoff: play test rounds 2 to 4, Auto Cannon grip, plan clean-up (next session)

Written 2026-10-25. Branch: `claude/cool-maxwell-v2wd3v` (all work committed and pushed; it holds all of
`claude/compassionate-babbage-5blt9e`). Read CLAUDE.md, AGENTS.md, this file, and in DESIGN.md the sections
"Play test fixes 2026-10-24, round 2", "round 3", "round 4", "Auto Cannon grip fix" and "Reminders for the user".
The previous handoff is `docs/HANDOFF_hinge_playtest.md` (its six items are built and play tested).

## Done this session (commits, oldest first)

- `827e9e7` Round 2: frame-rate scaled hand reach with a soft dead band (`MechHandControl.reach_gain_fps`,
  `reach_dead_band`); punch lowering at half speed (`SkeletalMeleeAnimation.lower_time_scale`); crosshair kick stays
  on the crosshair, the mouse pulls it back (`FreeAim.kick_moves_crosshair`, `max_kick_offset_deg`); SMG kick -25%;
  pulse scan without the second ring (`PulseScanEffect.end_band_m` 150); `FootDust`; mouse yaw x2.
- `252ebe2` `test_thumb_wrap.gd` runs at 60 fps (`Engine.max_fps`): the reach is scaled to the frame time.
- `05a5716` Pile Bunker arm lowers at half speed (`PileBunkerWeapon.lower_time_scale`; busy time unchanged).
- `44af518` Round 3: fist arm stays free while the punch fades (`is_fading()`); hips turn slowly after melee
  (`SkeletalHipTurn.after_melee_turn_speed_deg` 90, `after_melee_time` 1 s); crosshair kick rise 12; mouse yaw 2.0;
  torso turn and acceleration +70% (core 145.1 deg/s, `Mech.turn_acceleration_deg` 321.3); the beam stops when its
  arm breaks (`BeamRifleWeapon._stop_beam`); `WeaponRecoil.kick_rise_time` 0.12 s (every hand weapon).
- `71c8a0f` Round 4: Beam Rifle `aim_anchor` (2.3, 1.6025, -1.0555): ADS hold like the Beam Sniper (the right forearm
  no longer turns); `BorrowedHold` + `WeaponData.shoulder_guns_hold`: the Beam Sniper with a shoulder gun on both
  back slots is held with the Beam Rifle's arm and hand places (`WeaponPose.aim_shift`).
- `92f6bbb` DESIGN: 14 play tests closed (user confirmed).
- This commit: Auto Cannon grip (`ForearmGunWeapon.handle_offset`, `handle_offset_left`), phases 6 and 7 removed
  from the plan (with the Pilot and Archetypes sections and the "skills" data mentions), this handoff.

## User decisions this session

- "Hands lower 50% slower" = half the speed.
- Item 2 of round 4: copy the Beam Rifle's arm and hand places to the Beam Sniper (with 2 shoulder cannons).
- No hinge arms for clip-driven arms (melee attacks, hit reactions, death, dodge).
- Phases 6 and 7 removed.
- The Pile Bunker gets a better model (not started).

## Open (see DESIGN "Reminders for the user")

1. Play test the Auto Cannon grip in both hands.
2. Phase 3 play test (not done by the user): Tab drop and pick-up, respawn and part-break freeze fixes, hammer combo
   input buffer, SMG flinch count, Shoulder Cannon values, AI weapon ranges.
3. Pile Bunker: a better model. Ask the user for the source (Blender build script like `tools/blender/beam_rifle_build.py`,
   or an uploaded model). Then the PS1 skin (CLAUDE.md rule), the forearm mount (`scripts/weapons/pile_bunker_weapon.gd`
   `_attach_to_forearm`, the grip and the poses), and the fist miss (up to 0.6 m in the jump guard and while boosting).
4. Thumb grip: fix in Blender (`tools/blender/mech_hand_build.py`, `models/mech_hand/`), then re-tune `MechHand`.
5. Test mode is on (`data/test/test_mode.tres`: `free_energy`, `free_scan`). Turn both off after the tests.
6. Pixel-art graphics option (not started). Ideas: hammer strike, real punch animation and hammer model, Mixamo
   clips, cars as shields or throwables.

## Known small issues

- Auto Cannon: right fist up to 0.07 m off the handle while firing, 0.06 m while boosting.
- Beam Sniper ADS stutter (user: on hold).
- `tools/mech_gen/weapons.py` writes `data/weapons/beam_sniper.tres`; running it again drops `shoulder_guns_hold`.
  The Beam Rifle `aim_anchor` is a hand edit in `data/weapons/beam_rifle.tres`.
- `scripts/ui/debug_hud.gd:83` Nil error every frame headless; `shaders/pulse_scan_converge.gdshader` and
  `data/animations/arm_swing_run.res` unused (ask before deleting).
- `test_melee_combo.gd` missed one hit in 2 of 7 runs this session (different cases); 0 failures in the others.

## Tests (last full run, 0 failures)

test_weapon_hands, test_thumb_wrap, test_aim_behind, test_beam_arm_break, test_stability (67), test_hit_reactions,
test_melee_combo, test_dodge_exit, test_stagger_rules (36), test_shoulder_stop, test_pulse_scan, test_crosshair_kick,
test_foot_dust. New this session: `test_crosshair_kick.gd`, `test_foot_dust.gd`, `test_beam_arm_break.gd`.

## Tools added or changed

- `measure_arm_twitch.gd`: THRESH=<deg>, WEAPON=<file>; the Beam Rifle fires on `use_left_arm` (`use_right_arm`
  is the ADS key: the round 2 "firing" measure fired nothing).
- `measure_fist_lower.gd`: hand steps after a punch (MOVE, HOLD=1, TRACE=1).
- `measure_forearm_grip.gd`: forearm gun fist miss and the handle offset to try (SIDE, OFFSET).
- `render_rifle.gd`: RIFLE_BACK=left/right back weapons.

## How to work here

- Godot 4.7.2: download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
  to `/tmp/claude-0/godot/`, `git lfs pull`, then `--headless --path . --import` once (about 3 min). Run the import
  again after adding a new `class_name` script.
- Run frame-counting tests near 60 fps (`--fixed-fps 60` or `Engine.max_fps = 60`): the reach is frame-time scaled.
- Pictures: `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720
  --fixed-fps 60 --script res://tools/godot/render_rifle.gd`.
- The user's PC: `git fetch origin`, `git checkout claude/cool-maxwell-v2wd3v`, `git pull origin
  claude/cool-maxwell-v2wd3v`, `git lfs pull`. Delete an untracked `*.uid` or `*.import` file if Git refuses.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md (the reminders, "Auto Cannon grip fix") and
> docs/HANDOFF_playtest_rounds_2026-10-25.md. Remind me of the open reminders, then ask me how I want to make the
> new Pile Bunker model.
