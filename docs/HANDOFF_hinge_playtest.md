# Handoff: hinge arms, play test fixes, and the next play test round (next session)

Written 2026-10-24. Branch: `claude/compassionate-babbage-5blt9e` (all work committed and pushed; it holds all of
`claude/blissful-curie-9w50m7` too). Read CLAUDE.md, AGENTS.md, this file, and in DESIGN.md the sections "Hinge arms",
"Play test fixes 2026-10-24" and "Reminders for the user".

## Done this session (commits, oldest first)

- `107aebf`, `c60f973` Hinge arms (user drawings: no shoulder block turn about the up axis; level shoulders; right
  arm straight down, elbow out with the two-hand rifle). `SkeletalArmRig.hinge_arms`: the upper arm only pitches
  about the side axis; the forearm turns about its hang axis at the elbow and bends forward (`_hinge_solve`,
  `_hinge_turns`, `_hinge_joints`). Elbow tuck, block yaw, elbow hints and the elbow speed limit are off with it.
- `aebcdbd` Play test fixes: `max_swing_deg` 70 (the right arm stopped at aim); `MechHandControl.reach_gain` 0.3,
  once per frame (the reach overshot every frame: rifle and finger twitch); the short charge jump no longer plays
  its crouch in the air (`JumpClipDirector._update_rise`); combo window 1.0 s with `hold_for_combo`; empty hand
  swing higher (`FreeArmSwing`: more bend on the forward swing, `elbow_raise_deg`); the recoil kick moves the
  crosshair (`FreeAim._kick_offset`, `crosshair_return_speed`); push back as its own velocity part
  (`Mech._push_velocity`), W does not cancel it.
- `37f29b6` Pulse scan wave starts at the mech (the effect took its shader origin before it was placed).
- Tests after the last commit, all 0 failures: test_weapon_hands, test_melee_combo, test_thumb_wrap,
  test_stability (67), test_hit_reactions, test_shoulder_stop, test_dodge_exit, test_stagger_rules (36),
  test_pulse_scan, test_aim_behind.
- New tool: `tools/godot/measure_arm_twitch.gd` (hinge angle steps, finger fit and curl, reach offsets per frame).

## User play test results 2026-10-24

Status: items 1, 3, 5, 7, 8 and 9 were built on 2026-10-24 (branch `claude/cool-maxwell-v2wd3v`), see DESIGN.md
"Play test fixes 2026-10-24, round 2". Item 3: the user said "50% slower" means half the speed. The notes below are
the plans as written before the build.

### 1. Right forearm twitches very fast in ADS and in charged firing (or both)
The finger twitch is fixed. Likely causes, check in this order with `measure_arm_twitch.gd` (STEPS as in its
header; look at the R "jump" lines and the R elbow turn):
- The right elbow turn is about -83 deg at aim (`side.hinge.y`), near the place where the forearm direction is
  close to the hang axis v: there a small target move turns the forearm a lot, and the hand reach loop
  (`MechHandControl`, `reach_gain` 0.3) can still swing. Measured last session at aim with 4 shots: about +-0.1 deg
  at gain 0.3 (headless); in play the frame rate differs, and the charged beam shakes the torso (`torso_shake`,
  every `tick_time` 0.1 s), which moves the grip.
- Fix options: (a) a dead band and a speed limit on the elbow turn (`max_elbow_turn_speed_deg`, like the old
  `max_elbow_speed_deg`), applied in `_hinge_solve` from the last frame's angle (keep the hand on the target: the
  weapon moves to the hand as with the swing limit); (b) a low pass on the reach offset (`state.offset`) instead of
  the plain step; (c) take the beam's torso shake out of the arm target (shake the camera and the weapon model only).
  Measure first: print R `hinge` per frame and the beam's torso shake; pick the smallest fix that holds.
- Done when: no R hinge step over 0.5 deg per frame at steady ADS, while charging and while the beam fires, at
  60 and at 144 render fps (`--fixed-fps 144`).

### 2. Combo time 1 s: ok

### 3. After a punch the hands lower slowly (about half as fast), no snap
Cause (from this session's change): `SkeletalMeleeAnimation.hold_for_combo` holds the last punch pose while the
1 s combo window is open, then `_finish(true)` fades it in `MeleeAttack.blend_out` 0.25 s: the hands drop fast.
Before, the fist arm went back to the hang 0.35 s after the attack (`WeaponController.fist_hang_delay`).
Plan: during the hold, blend the punch pose toward the hang slowly (the arm is already solved to the hang under the
clip: `fist_hang_target`), so the fist lowers while the window is open; then the end fade over a longer time.
Exports: `hold_lower_share` (the part of the way down during the hold, 0.5 = halfway, the "-50%") and
`hold_blend_out` (s, e.g. 0.5, twice the 0.25). Check `_weight()` (the clip weight) and `_fade_left`. Ask the user
if "-50%" means half the speed or halfway down; build halfway down at half speed first and show a picture strip
(`tools/godot/render_arms.gd` ARMS_CASE=fist_combo).

### 4. Empty hand arm swing: ok

### 5. Crosshair recoil: SMG kick 25% less; no automatic return to the center
- SMG: `data/weapons/smg.tres` `recoil_up_deg` 0.5 to 0.375, `recoil_side_deg` 0.2 to 0.15.
- No return: `FreeAim.crosshair_return_speed` 0 means the old camera kick, so do not use 0. Change the code: with
  no box the kick stays on the crosshair (`_kick_offset`, no move into `_camera_kick`), and the player's mouse
  brings it back: in `FreeAim.take_motion` a mouse move first takes the crosshair back toward the center (the part
  of the motion against `_kick_offset`), and only the rest turns the camera. Then the aim (`aim_offset`) stays where
  the player puts it. Keep a limit (e.g. `max_kick_offset_deg` 8) so a long SMG burst does not push the crosshair
  off the screen. Update the FreeAim header and DESIGN "Play test fixes 2026-10-24".
- Check: MechAim ring place (`get_ring_screen_point`) and the brackets follow `aim_offset`; ADS (`camera_ads.gd`)
  scales the mouse, so the pull back is slower in ADS; ask the user if that is right.

### 6. Recoil with W: ok

### 7. Pulse scan: no visible second wave
Now: `shaders/pulse_scan_wire.gdshader` draws a front ring and an end ring (`end_ring_strength` 0.45) wire_time behind
it, and the wire frame goes out in a 40 m band ahead of the end ring (`end_band`). User: no second ring; the first
wave fades slowly, from the mech outward, the same way the second wave wiped it.
Plan: `PulseScanEffect.end_ring_strength` 0 (or take the tail ring out of the shader), and a wider, softer fade band
(`end_band_m` from 40 to about 150 m, smoothstep) so each place fades out over a longer time after wire_time; the
fade still starts at the mech and moves out at ring_speed. Check that the effect frees itself after the last fade
(`_process`: range / speed + wireframe_time; add the band time). Test: `test_pulse_scan.gd`; picture strip under
xvfb (the old `render_pulse_scan.gd`).

### 8. Thin smoke when a foot touches the ground
Events: `SkeletalLocomotion.footstep(strength)` (phase 0 = the left foot lands, 0.5 = the right foot), and the jump
landing (`Mech.landed` / `MechLandingRecovery` start) for both feet; the dodge and the Akira slide have no steps.
Effect: reuse `DustBurst.create(world, point, size, alpha)` (`scripts/effects/dust_burst.gd`; per frame cap) with a
small, thin puff: a new data file or exports (`foot_dust_alpha` about 0.25, size about 2 x 0.3 x 2 m, more on a
landing scaled by the fall height). Place: the foot bone (`foot_L` / `foot_R`) at the ground (FootPlanter's locked
sole point). Make it a small script `FootDust` (one job), added by `build_sanggigilid.gd` (never hand-edit
`scenes/mech/sanggigilid.tscn`). PS1 skin rule: the smoke look should match the existing dust (PixelSmoke).

### 9. Double the horizontal mouse sensitivity (SGG-101 Sagigilid)
`MechCameraRig.yaw_sensitivity_scale` 1.5 to 3.0 (`scripts/camera/mech_camera_rig.gd`; check for a scene override
in `scenes/mech/sanggigilid.tscn` / the player scene and in `build_sanggigilid.gd`). Pitch stays
(`pitch_sensitivity_scale` 0.3). The class factor (`AimClassTuning`) and ADS scale still stack. Update the DESIGN
line about the +50% (2026-10-22).

## Known small issues (from before, still open)

- Pile Bunker: fist miss up to 0.55 m in the jump guard and 0.6 m while boosting (pitch limit).
- Auto Cannon: fist 0.18 m off the handle (move the handle about 0.16 m toward the wrist).
- Beam Sniper ADS stutter (user: on hold).
- Clip-driven arms (melee, hits, death, dodge) are not hinge arms yet (user decision open).
- `scripts/ui/debug_hud.gd:83` Nil error every frame headless; `shaders/pulse_scan_converge.gdshader` and
  `data/animations/arm_swing_run.res` unused (ask before deleting).

## How to work here

- Godot 4.7.2: download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
  to `/tmp/claude-0/godot/`, then `--headless --path . --import` once (about 3 min). `git lfs pull` first.
- Pictures: `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720
  --fixed-fps 60 --script res://tools/godot/render_rifle.gd` (RIFLE_RIGHT, RIFLE_ACTIONS, RIFLE_FRAMES, RIFLE_VIEWS
  front,top,side,p_back). The front view is dark in a deep crouch.
- Arm numbers: `measure_arms.gd` (block tilt, roll, pitch, yaw), `measure_wrist_pin.gd` (fist miss, reach),
  `measure_arms_swing.gd` (stride swing), `measure_arm_twitch.gd` (per frame steps).
- Skeleton updates can come more than once per frame: count per `Engine.get_process_frames()`, not per signal.
- Do not edit a script while a background test run uses it (each test loads the files at its start).
- The user's PC: `git fetch origin`, `git checkout claude/compassionate-babbage-5blt9e`, `git pull origin
  claude/compassionate-babbage-5blt9e`, `git lfs pull`. If Git refuses because of an untracked `*.uid` or `*.import`
  file, delete that file (Godot makes it again).

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md ("Hinge arms", "Play test fixes 2026-10-24", the reminders) and
> docs/HANDOFF_hinge_playtest.md. Remind me of the open reminders, then build the play test items 1, 3, 5, 7, 8 and
> 9 of the handoff one at a time, test each, and stop for my play test.
