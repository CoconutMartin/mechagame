# Handoff: animation pipeline (next session)

Written 2026-10-15. Branch: `ccr-e0d521dd-6ijish` (all work committed and pushed; it holds the
`ccr-04329fbb-pi985o` and `ccr-bc134419-5cji96` work too).

## Task

The next pipeline is **animations** for SGG-101 Sagigilid (`scenes/mech/sanggigilid.tscn`, built by
`tools/godot/build_sanggigilid.gd`). The open DESIGN.md reminder: "add the Mixamo animation library
(`models/mixamo/library/`, 25 clips): hit reactions, deaths, getting up, melee attacks and stuns. The
file names say what each clip is for. The user will say when to add them." The user has now said it
is next. Ask the user which group to start with and how each clip is triggered before you build.

## Before you build (ask the user)

- Which group first: hit reactions, deaths, getting up, melee, stuns.
- Triggers: which hit size plays which clip (damage thresholds?), which death clip per cause
  (`MechHealth.destroyed(cause)` gives the part key), when "getting up" plays (after a knock down?
  there is no knock down state yet), melee input (no melee key yet; see Controls in DESIGN.md).
- Blend rules: does a hit reaction play over walking (upper body only) or stop the legs?
- Show the result as renders (xvfb, below) and let the user approve before you commit. The user
  approves looks before commits (this session: an unapproved commit had to be reverted).

## Clips in `models/mixamo/library/` (FBX, the name says the use)

- Hit reactions: "Hit Reaction - small / medium / large hit", "Reaction - small hits / medium hit /
  large hit, not knocked down - align arm and hand position with hand socket", "Hit while kneeling,
  on back", "Receive torso punch or uncharged pile bunker", "Standing React Large From Left -
  staggered animation".
- Stuns: "Stunned - when punched in the head or central torso".
- Deaths: "Crouch Death", "Dying - 2 legs destroyed", "Dying - central torso destroyed", "Dying -
  destroyed from behind", "Dying - head destroyed", "Rifle Death - destroyed head or torso + heavily
  damaged side", "Rifle Run To Dying - mech destroyed while running", "Walking To Dying - head
  destroyed or mech destroyed from the back".
- Getting up: "Getting Up - standing from face down position", "Getting Up - standing up from
  laying down position".
- Melee: "Hook Punch", "Uppercut", "Mutant Swiping - overhead swing, left arm", "Standing Melee
  Attack Downward", "Standing Melee Combo Attack Ver 1 - 2 hand hammer swing".
- "align arm and hand position with hand socket" in a name: the hands must stay on the weapon grip
  sockets (MechHandControl, grip sockets; DESIGN.md "Grip sockets").

## What exists (reuse it)

- Retarget: `tools/godot/retarget_mixamo.gd` (header says how to run it headless). It writes
  `data/animations/<clip>.res` (rotation tracks for pelvis, torso, head, legs, arms, hands; a pelvis
  height track) and `<clip>_travel.tres` (root travel). Used for the 4 dodge clips (DESIGN.md "Dodge
  animations"); read that section first.
- Playing a clip over the body: `SkeletalDodgeAnimation` (`scripts/animation/skeletal_dodge_animation.gd`,
  `Visual/DodgeAnimation`, a SkeletonModifier3D after the arm rig): picks a clip, blends in and out,
  root motion via `Mech.root_motion_velocity`. A good model for a hit or melee player.
- Locomotion tree: `SkeletalLocomotion` builds the AnimationTree in code (Idle, Walk, Slow_Run, Jog,
  biped_run_full by speed). Blender actions are in `models/new_mech/new_mech_exploded.glb` (Git LFS,
  run `git lfs pull`).
- Modifier order on the skeleton matters: SkeletalHipTurn, AimStance, ArmRig, DodgeAnimation, ...
  (see DESIGN.md "Sanggigilid").
- Procedural hit kick: `HitReaction` (old part-built mechs; check whether the skeletal mech has an
  equivalent before you add clips on top).
- Death now: `SkeletalDeath` stops the AnimationTree (pose freezes) and topples the body like a tree.
  It calls `WeaponController.relax_free_left_arm()` so a free left arm takes the relaxed hang. Death
  clips would replace or come before the topple.
- Part breaking: `SkeletalPartBreaker` (arms fall off, legs smoke, one-leg speed). Part HP signals:
  `MechHealth.damaged(key, amount)`, `part_destroyed(key)`, `destroyed(cause)`.
- Arms after a break (2026-10-15): a broken two-hand weapon or shield gives the left arm no IK
  target, so the animation moves it, like the right arm after its weapon breaks.

## Rules to keep

- CLAUDE.md and AGENTS.md (routing policy; use the `reviewer` agent for multi-file or risky changes:
  animation, damage, input).
- PS1 skin rule; keep the model's own colors.
- Add new nodes in `tools/godot/build_sanggigilid.gd` too, or the next build removes them.
- Tuning values are `@export` with a `##` comment; data as `.tres` in `/data`.

## Test and render

- Godot: `/tmp/claude-0/godot/Godot_v4.7.2-stable_linux.x86_64` (download again in a new container:
  `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`),
  then `--headless --path . --import` once.
- Check: `--headless --path . --check-only --script <file>`.
- Render: `xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . --rendering-driver opengl3
  --resolution 1280x720 --script <script.gd>`. A SceneTree script that loads
  `res://maps/urban_small/urban_small.tscn`, finds the mech with `get_nodes_in_group(&"player")`,
  and saves `root.get_viewport().get_texture().get_image()` works. `Input.action_press("move_forward")`
  makes it walk. Do not `await` inside `_process` of a SceneTree script; count frames.
- The `less` pager is missing in the user's Termux: tell them `git --no-pager ...` or `pkg install less`.

## Other open reminders (DESIGN.md "Reminders for the user")

- The left torso HP indicator (Torso L) is hidden from the game camera angle; fix later.
- Balance the stop-to-fire shoulder weapons against the hand-held versions.
- Pulse scan equipment (back unit, ring wave, grades 1 to 3).
- Test on a computer with a working keyboard and mouse.
- Mechs that pick up small cars as a shield or a throwable.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md and docs/HANDOFF_animations.md. Then start the animation
> pipeline: add the Mixamo clips to SGG-101 Sagigilid. Ask me which group to start with and how the
> clips are triggered, and show me renders before you commit.
