# Handoff: swappable mech parts, Haliya (removed), SGGv2 (removed, kept for later)

Written 2026-11-01. Branch: `ccr-4df8074c-yr96fd` (all work committed and pushed; it continues from
`claude/backpacks-handoff-docs-nwe0op`, `docs/HANDOFF_drones_2026-10-31.md`). Read CLAUDE.md, AGENTS.md, this file,
and in DESIGN.md the sections "Swappable mech parts", "SGGv2 look" and "Reminders for the user".

## Done this session (commits, oldest first)

- Swappable parts phase 1: SGG split into a rig file and 5 part files; `SkeletalPartModels` puts the loadout's part
  meshes on the shared skeleton. Compared with the old one-file scene: all 27 mesh boxes, 18 hitboxes, bind poses
  and vertices match exactly.
- `render_part_models.gd`: pictures of the player mech (4 views, rest and walk; `TINT=1`, `SKIN`, `LOADOUT`,
  `PREFIX`, `CAM_HEIGHT`, `CAM_DIST`).
- Haliya HLY-101 built from the user picture as a second mech on the SGG joints, with accessory bones (skirt,
  sleeves) and `AccessoryBoneFollow`; then removed on the user's request (the user uploads the model). Kept: the
  accessory bones, the follow modifier, the hit part bones, `models/guides/haliya_ref.png`.
- SGGv2: paint skin (Black Red, then Navy Orange with orange eyes), more body and added armor
  (`tools/blender/sggv2_build.py`); set aside, then removed from the game on the user's request. Kept for later,
  not used: `sggv2_build.py`, `models/sggv2/sggv2.blend`, `MechPaint`, `MechPaintSkin`, `shaders/mech_paint.gdshader`,
  `data/skins/paint_navy_orange.tres`.

## User decisions this session

- Slots: head, core, left arm, right arm, legs. Parts come from every mech; each mech has 1 variant.
- Every mech uses the SGG-101 joints (rig `MechRig`, 56 bones + 8 accessory bones), so all animations play.
- Rigid parenting (one bone per mesh at full weight; fingers on their bones). The child part owns the joint piece:
  head = neck, core = waist joint, arm = shoulder ball, elbow, hand, legs = pelvis, hips, knees.
- Collision: simple boxes per bone as before (SkeletalHitboxes).
- Skirt and sleeves move with follow scripts (AccessoryBoneFollow).
- A test part to try the swap (not built yet; phase 2).
- Haliya: the user uploads the model. SGGv2: out of the game, kept for later.

## How the part system works

- Blender: `tools/blender/export_mech_parts.py -- <blend> <prefix> <out folder> [all|rig|parts]` exports
  `<prefix>_rig.glb` (rig and all actions, a 1-triangle `RigAnchor`) and `<prefix>_<head|core|arm_l|arm_r|legs>.glb`
  from the part collections Head, Core, Arm_L, Arm_R, Legs. `mech_rig_standard.py` holds the accessory bones and
  adds them to a rig that has none (the .blend is not saved). SGG: `models/mechs/sgg/` from
  `models/new_mech/new_mech_exploded.blend` (the user's file, not changed).
- Data: `PartData.scene` of each part points at its .glb (`data/parts/sanggigilid/*.tres`).
- Game: `SkeletalPartModels` (node `PartModels`, the mech's first child) works in `_enter_tree`, before the other
  nodes read the meshes in `_ready`; it reads `WeaponMount.loadout` (set before `add_child` by LoadoutSwitcher and
  MechSpawner); an empty slot uses the default SGG part. The skin binds by bone name.
- `build_sanggigilid.gd`: rig file `sgg_rig.glb`; puts the parts on only to measure the wrist pins, takes them off
  before it saves; adds `Visual/AccessoryFollow` last (it must be the last skeleton modifier).
- Hit parts (`sanggigilid_hit_parts.tres`): sleeve bones in Arm L / R, skirt bones in the Groin.
- Tests: `test_part_models.gd` (slots, skin binds, hitboxes; `OLD_SCENE=` compares with an older scene;
  `LOADOUT=2` checks a mech with a skirt on key 2). Last runs: 0 failures; `test_stability`, `test_weapon_hands`,
  `test_break_time`, `test_hit_reactions`, `test_pulse_scan`, `test_boost_pack`, `test_beam_arm_break` 0 failures.
  `test_clip_self` fails 5 cases with the same numbers as before the split (the open arm clipping).

## Open (see DESIGN "Reminders for the user")

1. The user uploads the Haliya model (parts on `MechRig`, collections Head, Core, Arm_L, Arm_R, Legs; skirt and
   sleeve meshes on the accessory bones). Then: export with `export_mech_parts.py -- <file> hly models/mechs/hly parts`,
   add `data/parts/haliya/*.tres` and a key 2 loadout (git history: commit "Haliya HLY-101: second mech").
2. Swappable parts phase 2: garage pickers for the 5 slots and a test part; phase 3: a Blender part kit (template,
   check script, guide). Per-arm hand scenes and wrist pins (now SGG's) and the mech name per loadout are open.
3. SGGv2 paused: run `test_clip_self` on the last build, play test it, add the PAINT skin style again.
4. Play test SGG after the split; the Drone Pack, drone mods and cool down; the other backpacks; the older items.
5. Arm clipping in the guard and punch clips needs a user decision.
6. Cross Punch FBX upload was empty; the thumb grip in Blender.
7. Test mode on (`free_energy`, `free_scan`); PS1 look off (`ps1_skin.tres` `enabled = false`).
8. Pixel-art option not started; backpack later work (equipment models, break effect, canister count).

## Known small issues

- The git tag `sggv2` exists only in this container: the tag push failed ("remote end hung up"). The state is the
  commit "Swappable parts phase 1" (plus "DESIGN: test results after the part split").
- `git checkout <commit> -- <LFS file>` left LFS pointers here; fix: `git show :<file> | git lfs smudge > <file>`.
- `models/mechs/sgg/*.png` (textures per part) are LFS files; each part file holds its own copy of the textures.

## How to work here

- Godot 4.7.2 to `/tmp/claude-0/godot/` (see `docs/HANDOFF_drones_2026-10-31.md`), `git lfs pull`,
  `godot --headless --path . --import`.
- The .blend files are Blender 5.2: use pip `bpy` 5.2.2 (`uv venv -p 3.13 /tmp/claude-0/bpy5env`,
  `uv pip install -p /tmp/claude-0/bpy5env/bin/python bpy==5.2.2 numpy`); import `bpy` before `bmesh`.
- Pictures in Godot: xvfb with `--rendering-driver opengl3` (`render_part_models.gd`).
- Skeleton modifier poses exist only inside `Skeleton3D.skeleton_updated`; measure there.
- The user's PC: `git fetch origin`, `git checkout ccr-4df8074c-yr96fd`, `git pull`, `git lfs pull`.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, docs/HANDOFF_swappable_parts_2026-11-01.md. Remind me of the open reminders, then
> continue: I will upload the Haliya model or send play test results.
