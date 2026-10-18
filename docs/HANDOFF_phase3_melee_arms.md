# Handoff: phase 3, melee combos, arms and fixes (next session)

Written 2026-10-18. Branch: `ccr-92705f90-hb34ka` (all work committed and pushed; it holds all of
`claude/fervent-fermi-kwyj0n` plus 22 commits since `1a80cfa`). Read CLAUDE.md, AGENTS.md, this file, the
DESIGN.md bullets just above "## Reminders for the user" (this session's work is at the end of that list, and
in the bullets before "Pile Bunker cooldown 6 s") and the reminders. The previous handoff
(`docs/HANDOFF_stagger_ranges_fixes.md`) is done except the items carried over below.

## Done this session (user approved where a look was involved, unless marked "not tested by the user")

- Stagger review: knock-down only from one big shot (`MechStability.single_shot_knock`); small flinch clip
  2.5 x faster; stagger clip 1.5 x faster.
- Shoulder Cannon: damage 200, stagger 35, spread 0.15, recoil half of the hand Auto Cannon.
- Graphics: TAA only on Forward+ (FXAA on Mobile / Compatibility; the tablet warned).
- Phase 3: Tab weapon drop and pick-up (hold LMB/RMB then Tab = drop; hold Tab then LMB/RMB = pick up
  within 3 m), every empty hand is a fist, HP part moves with the weapon, ground weapons despawn (60 s, 30 m,
  max 8). The unused `lock_on` action is gone. Test: `tools/godot/test_weapon_hands.gd`.
- Crash fixes: `CameraWallSeeThrough` and freed building pieces (two places).
- Weapon ranges: a quarter of MWO's; the AI fires only inside its weapon's range.
- Freeze fixes (from the user's Profiler screenshots): respawn (`SkeletalHitboxes` top-bone cache, 175 ms ->
  13 ms) and part break (shaders compiled at load by `BreakWarmup`, Forward+ 848 ms -> 1.9 ms).
- Melee chain combo (any order, up to 3 swings, S ends it, 0.6 s window, input buffer, 5 s cooldown); hammer
  swings 1-2 = 25 stagger, S and swing 3 = 45 (knock-down).
- Baton (two-hand melee, fast, W thrust; 15 / 45 stagger). Approved.
- Arms: hammer arms closer while moving, fist arms blend to the hang after a punch, free and fist arms swing
  with the user's clip `models/mixamo/library/Slow Run - arm swing.fbx`. Approved.
- SMG: one small flinch per 8 bullets.
- Long rifles: the left hand holds the forestock further forward in ADS and slides back when aiming down.
  Approved.

## Not tested by the user yet (ask when the session starts)

- Phase 3 drop / pick-up in play, the respawn and part-break freeze fixes, the hammer combo with the input
  buffer, the SMG flinch count, the Shoulder Cannon values, the quarter weapon ranges (the AI with an SMG keeps
  40 to 80 m away, outside the SMG's 65 m: watch for it).

## Next pipeline

1. Phase 4: jump and landing with `models/mixamo/library/Jumping_Up.fbx` and `Landing.fbx`, speed and
   momentum for a 10 m mech, keep the charge (hold to power up) before the jump. User notes 2026-10-18: the
   jump off the ground is stiff and straight; falling after a jump plays 2 animations (remove the second, final
   one); add a dynamic pose while rising. Ask the user for more notes first.
2. Carried over:
   - Jump clips: falls under 1 m not tested; the hard landing crouch may push the thighs into missile pods, a
     shield or the Pile Bunker; the waist aim twist is off while a clip is at full weight; the feet hover 0.1 to
     0.16 m in the landing clips. (Phase 4 may replace these clips.)
   - Left hand: the left Auto Cannon not checked for clipping; the left Pile Bunker stake not seen in a clean
     side view.
   - Camera lead limit (15 degrees) and the torso turn speed: check the feel in play.
3. Small open points from this session:
   - Fist punch may show a small arm pop at swing start/end (`fist_hang_delay`); ask the user.
   - Combo mash: pressing RMB many times during a wind-up chains all 3 swings (`buffer_from` 0); offer a later
     buffer start if the user dislikes it.
   - AIMelee chains only plain presses (no keyed chain swings); its "fist/combo" label also counts hammer chains.
   - `tools/mech_gen/weapons.py` drift (not from this session): it writes zoom_fov 52.6 for the beam rifles (repo
     .tres 43.4) and no `blocks_dodge` for warden_shield. Do not run it in place; copy only the files you need.
   - `tools/data_gen/garage_data.py` writes ids r0, r1...; the checked-in catalog has hand-written ids.
   - `weapon_controller.gd` is about 1200 lines (against "small scripts"); a split (fist pool and ground weapons
     into their own node) is proposed for later.
4. Open reminders in DESIGN.md (remind the user at phase start and end).

## How to work here

- Everything in `docs/HANDOFF_stagger_ranges_fixes.md` "How to work here" still holds (Git LFS, Godot 4.7.2 in
  `/tmp/claude-0/godot/`, pip `bpy` 5.2.2 for Blender files, `skeleton_updated` for bone poses, never hand-edit
  `scenes/mech/sanggigilid.tscn`, xvfb renders, no `pkill -f` on your own pattern, the user approves looks
  from renders before commits).
- Headless runs here take about 60 ms per frame (15 FPS wall time); a full `render_melee.gd` run takes about
  30 min, so use `MELEE_ONLY=<case part>`.
- New tools this session: `test_weapon_hands.gd`, `test_break_time.gd` (headless), `render_arms.gd`
  (ARMS_CASE), `render_ads.gd` (ADS_WEAPON, ADS_PITCHES, ADS_RENDER=0), `make_baton_thrust.gd`,
  `retarget_mixamo.gd -- arms <fbx> <out.res>` (arms-only clips). `render_melee.gd` has CHECK / STAGGER lines.
- Forward+ timing can be checked headless-free with Vulkan lavapipe under xvfb
  (`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json`); the dummy renderer does not show shader compiles.
- Sub-agents: the Sonnet tier hit its weekly limit on 2026-10-18 (resets 2026-10-20); this session ran
  implementers and reviewers with `model: "opus"`. Split parallel agents by file ownership.
- The user's tablet: after a pull, delete `.godot` if Godot shows "Could not find type"; use
  `git --no-pager` in Termux. On the PC, Godot may change `project.godot`: `git restore project.godot` before a
  checkout if the user did not edit it.
- On the user's PC: `git fetch origin`, `git checkout ccr-92705f90-hb34ka`,
  `git pull origin ccr-92705f90-hb34ka`, `git lfs pull`.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md (the latest bullets and the reminders) and
> docs/HANDOFF_phase3_melee_arms.md. Then ask me about the untested items, and start phase 4 (jump and
> landing). Ask me for the details you need.
