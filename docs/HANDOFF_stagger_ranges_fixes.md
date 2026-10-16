# Handoff: stagger, weapon ranges and fixes (next session)

Written 2026-10-16. Branch: `claude/fervent-fermi-kwyj0n` (all work committed and pushed; it holds all
of `claude/modest-goodall-mft3bs`, merged as a fast-forward, plus 9 commits since `54cc3cc`). Read
CLAUDE.md, AGENTS.md, this file and the DESIGN.md bullets just above "## Reminders for the user" (this
session's work is at the end of that list) and the reminders. The previous handoff
(`docs/HANDOFF_weapons_melee_animation.md`) is done except the items carried over below.

## Done this session (user approved where a look was involved, unless marked "not tested by the user")

- Building collapse blast off: falling chunks do no damage (`fall_damage` 0). Contact damage stays
  1 HP per smashed chunk.
- Broken arm: the jointed hand falls with the arm (`MechHandControl.take_hand`). Not tested by the user.
- Camera: building chunks between the camera and the mech are hidden (`CameraWallSeeThrough`). Not
  tested by the user.
- Foot "double bounce": gait option `settle` in `tools/blender/new_mech_gaits.py` (Jog, Slow_Run);
  clips rebuilt with Blender 5.2 and the model exported again. Not tested by the user.
- Weapon ranges: MechWarrior Online figures (optimal / max, full damage to optimal, 0 at max, the round
  ends at max): Shotgun = LB 10-X 540/1080, SMG = Machine Gun 130/260, Heavy Rifle = AC/5 620/1240,
  Auto Cannon = AC/10 450/900, Beam Rifle = Large Laser 450/900, Beam Sniper = ER Large Laser
  675/1350, Missile Pods = LRM 1000. The user dropped an earlier falloff spec and the MW5 values.
- Crosshair: HP color only inside the active weapon's max range, else white; a stability bar under
  the brackets.
- One-hand gun hold (SMG, Shotgun, Heavy Rifle) close to the body; approved by the user.
- Stagger system (arcade spec "B" + crouch brace + stability bar, no suppression): `MechStability`,
  stagger points per weapon, flinch by stagger points, knock-down for 45 points in 0.3 s. Replaces the
  damage-based stun and knock-down. Not tested by the user.
- Fire cooldowns set by the user (Heavy Rifle 3 s, Auto Cannon 4 s, Shoulder Cannon 5 s and both
  shoulders fire together, Beam Rifle 4 s, Beam Sniper 6 s, Shotgun 2.25 s, SMG 0.33 s).
- The user's jump clips are in the repo: `models/mixamo/library/Jumping_Up.fbx` and `Landing.fbx`
  (not used yet; phase 4).

## Next pipeline (user order 2026-10-16)

1. Review the flinching in play, and these three stagger items (decide with the user):
   - Two Auto Cannon hits at the same moment (28 + 28 within 0.3 s) knock a mech down. That includes
     one mech that fires an Auto Cannon from each hand. Keep, or raise `MechStability.knock_points`,
     or only count big single hits?
   - SMG flinch: the small flinch clip lasts 1.05 s, so at 3 shots per second only about 1 bullet in
     3 starts a flinch (no restart while a clip plays). Keep, or a shorter clip / partial restart?
   - The stagger plays the old stun clip ("Receive torso punch"), longer than the spec's 0.55 s.
     Shorten (speed up the ActionClip) or keep?
2. Open reminders (DESIGN.md): balance the stop-to-fire shoulder weapons against the hand-held versions
   (recoil, damage, sway).
3. Phase 3: pick up weapons when one hand is free; every open (empty) hand is a fist. Empty left hand
   punches on LMB, empty right hand on RMB (user, 2026-10-16; LMB = use_left_arm, RMB = use_right_arm).
4. Phase 4: use `Jumping_Up.fbx` and `Landing.fbx` for the jump and landing, with speed and momentum
   for a 10 m mech. Keep the charge (hold to power up) before the jump (user, 2026-10-16).
5. Carried over from the previous handoff:
   - 6. Jump clips: falls under 1 m not tested; the hard landing crouch may push the thighs into missile
     pods, a shield or the Pile Bunker; the waist aim twist is off while a clip is at full weight; the
     feet hover 0.1 to 0.16 m in the landing clips. (Phase 4 may replace these clips.)
   - 9. Left hand: the left Auto Cannon not checked for clipping; the left Pile Bunker stake not seen in
     a clean side view.
   - 13. Camera lead limit (15 degrees) and the torso turn speed: check the feel in play.

## How to work here

- Git LFS: the mech model and .blend files are LFS. Clone, then `git lfs pull` before Godot opens the
  project. Do not `git stash` an LFS file: the pop wrote back the pointer, not the file (fix: copy the
  object from `.git/lfs/objects/<oid>`).
- Godot 4.7.2: `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
  to `/tmp/claude-0/godot/`, then `--headless --path . --import` once. Run `--import` again after a new
  `class_name` script or a new model file.
- Blender: the .blend files are saved by Blender 5.2; the Ubuntu Blender 4.0 cannot open them. Use pip
  `bpy` 5.2.2 (Python 3.13): `uv venv -p 3.13 /tmp/claude-0/bpy5env`, `uv pip install -p
  /tmp/claude-0/bpy5env/bin/python bpy==5.2.2 numpy`, then run a Python script that calls
  `bpy.ops.wm.open_mainfile` and the tools in `tools/blender/`. Blender's download site is blocked; PyPI
  works.
- Bone poses with the skeleton modifiers applied exist only inside `Skeleton3D.skeleton_updated`
  (outside it the skeleton shows the plain animation pose). Measure there (see `render_grip.gd`).
- Never hand-edit `scenes/mech/sanggigilid.tscn`; change `tools/godot/build_sanggigilid.gd`, or add
  nodes at runtime (this session: `CameraWallSeeThrough` from `MechCameraRig`, `MechStability` from
  `SkeletalStaggerAnimation`).
- Weapon data: the rifles, pods and Pile Bunker are written by `tools/mech_gen/weapons.py`; keep it in
  step with the `.tres` files when you change values (this session did).
- Test tools (all in `tools/godot/`, run headless unless noted):
  `test_stability.gd` (stagger meter unit test), `test_hit_reactions.gd` (flinch, stagger, knock-down in
  game), `test_weapon_ranges.gd`, `test_range.gd` (bullets into a part hitbox), `render_range_cue.gd`
  (crosshair color and stability bar; needs xvfb; `CUE_WEAPON`, `CUE_DISTANCES`, `CUE_STAGGER`),
  `render_grip.gd` (one-hand grip gaps and pictures; xvfb), `render_walk.gd` (foot heights),
  `render_wall_view.gd` (camera and walls; xvfb), `render_break.gd` (part breaking; xvfb),
  `render_melee.gd`, `render_jump.gd`.
- Renders: `xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . --rendering-driver opengl3
  --resolution 1280x720 --fixed-fps 60 --script <script.gd>`. Some map tools stall headless when they
  save viewport pictures; use xvfb.
- Do not `pkill -f` a pattern that is also in your own command line (it killed this session's shell).
- Web: sarna.net, steamcommunity.com and mwo.fandom.com are blocked for fetch; web search snippets work.
- The user approves looks before commits (renders first), except when the user says "commit".
- On the user's PC: `git fetch origin`, `git checkout claude/fervent-fermi-kwyj0n`,
  `git pull origin claude/fervent-fermi-kwyj0n`, `git lfs pull`. Use `git --no-pager` in Termux.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md (the latest bullets and the reminders) and
> docs/HANDOFF_stagger_ranges_fixes.md. Then start the next pipeline: review the flinching and the
> three stagger items with me, then the open reminders. Ask me for the details you need.
