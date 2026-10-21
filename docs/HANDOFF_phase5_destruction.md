# Handoff: phase 4 jump and phase 5 building destruction (next session)

Written 2026-10-21. Branch: `ccr-7a73ea4b-jwqirv` (all work committed and pushed; it holds all of
`ccr-92705f90-hb34ka` plus this session's commits). Read CLAUDE.md, AGENTS.md, this file, the DESIGN.md
bullets "Phase 4: jump and landing clips" and "Phase 5: building destruction improvements" (just above
"## Reminders for the user") and the reminders.

## Done this session

- Phase 4 (jump and landing), user approved the look from renders; in-game test still open (reminder):
  - Jumping_Up drives the charge crouch, the rise and the tuck (full charge = the start of the push,
    no "cannon ball" tuck); launch at the release (no ground push, user choice); Jumping_Down for the fall;
    Landing.fbx replaces Falling_To_Landing and Landing_position (a cut at 0.61 to 0.77 s with a cross-fade).
  - Jump guard: during the charge, the jump and the landing the weapon frame turns level, moves 2 m forward
    and rises to 6.5 m above the feet; free and fist hands go to a guard place; it goes off 0.5 s before
    the landing ends (the rifle back in its hold as the mech stands up). Beam Rifle: no contact with the
    legs or body in the clearance check. The shield in the guard turns high and flat: open question.
- Phase 5 (building destruction improvements; destruction itself existed since 2026-10-12):
  - 5a performance: one support check per physics frame, a shared rubble mesh, a shared dust look, caps
    per frame (dust 12, rebar 12). The 44-chunks-at-once case went from 77.5 ms to about 23 to 31 ms (CPU).
  - 5b break look, approved: cracks (strong dark lines, darker chunk below 50% HP), scorch marks (missiles,
    shells of 150 damage or more), rebar on concrete break edges, rough rubble in the wall's own material.
  - 5c collapse feel, pose approved: a large loose group (10+ chunks) leans and sinks as one mass, then stops
    (the office at about 12 degrees, the tower at about 20 degrees, 8 m sunk) and stays a normal breakable
    building; big dust cloud and camera shake when it stops; no damage to mechs.
- Tests: all six headless test tools passed after phase 4 (stability 67 checks, hit reactions, weapon
  hands, weapon ranges 54050 checks, range, break time). Not run again after phase 5 (it does not touch
  their code paths, but run them before the next commit that does).

## Next pipeline

1. User note (2026-10-21): small rubble pieces must disappear the moment they hit the ground (for
   performance). Now `Rubble` (`scripts/world/rubble.gd`) lies `life` 14 s, sinks 1.5 s, at most 220.
   Ideas: free on the first contact with the ground (contact_monitor, or a ray down each physics frame
   while falling), keep a short dust puff there; check `CollapseMass` impact rubble and `FallingChunk`
   shatter still read well. Measure with `test_building_perf.gd` before and after.
2. 5d: a camera shake when a mech goes through a building (`MechBuildingContact` breaks the chunks; add
   a shake per smashed chunk, or a steady shake while inside). Falling debris stays harmless (user choice).
3. Open questions for the user: the shield in the jump guard (stay in front of the body?); the reminders
   in DESIGN.md (phase 3 items, phase 4 and phase 5 play tests, camera lead and torso turn).
4. Carried over from `docs/HANDOFF_phase3_melee_arms.md` "Small open points" (fist arm pop, combo mash
   buffer, AIMelee chain keys, `weapons.py` drift, `garage_data.py` ids, `weapon_controller.gd` size).

## How to work here

- Everything in `docs/HANDOFF_stagger_ranges_fixes.md` "How to work here" still holds (Git LFS, Godot
  4.7.2 in `/tmp/claude-0/godot/` from the GitHub release zip, then `--headless --path . --import`; xvfb
  renders; never hand-edit `scenes/mech/sanggigilid.tscn`).
- Never `pkill -f` or `pgrep -f` a pattern that is also in your own command line (it killed the shell
  twice this session). To stop Godot: `pgrep -f '^/tmp/claude-0/godot/Godot' | xargs -r kill`.
- Render tools that await `RenderingServer.frame_post_draw` hang in `--headless`; run them under xvfb.
- New tools this session (all in `tools/godot/`, header comments list the env options):
  - `render_jump.gd`: JUMP_WEAPONS (slot=weapon pairs), JUMP_VIEW (side, front, front_left, game),
    JUMP_CAM_DIST, JUMP_FOV, clearance check (CLEAR lines: hand and weapon points inside leg, pelvis,
    torso and head armor boxes; approximate), JUMP_CLEAR=0, JUMP_CLEAR_EVERY, JUMP_STOP_AT, JUMP_TAIL,
    JUMP_GUARD_HEIGHT, JUMP_GUARD_FORWARD.
  - `test_building_perf.gd` (PERF_CASE office, tower, shoot, walk; PERF_FRAMES, PERF_OUT). Frame times
    vary a lot between runs on the cloud machine; run twice and look at the log (PERF_OUT) before acting.
  - `render_wear.gd` (cracks, scorch, rebar, rubble on Office5F), `render_collapse.gd` (COLLAPSE_BUILDING,
    COLLAPSE_DISTANCE, COLLAPSE_SECONDS, COLLAPSE_STEP; hides the other buildings).
  - `tools/map_gen/wear_textures.py` writes `scorch.png` and `crack_overlay.png`.
- GitHub push: on 2026-10-19 pushes failed with 403 ("Claude doesn't have GitHub access ... for your
  organization") while reads worked; it came back after the user fixed the app's repository access. If it
  happens again, read the `github.access` documentation page and tell the user; keep the commits local.
- The user's PC: `git fetch origin`, `git checkout ccr-7a73ea4b-jwqirv`, `git pull origin
  ccr-7a73ea4b-jwqirv`, `git lfs pull`. If Git refuses because of an untracked `*.import` file, delete that
  file (Godot makes it again).

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md (the latest bullets and the reminders) and
> docs/HANDOFF_phase5_destruction.md. Then make small rubble disappear when it hits the ground, and go on
> with 5d. Ask me for the details you need.
