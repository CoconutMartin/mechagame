# Handoff: weapons, melee, animation and fixes (next session)

Written 2026-10-16. Branch: `claude/modest-goodall-mft3bs` (all work committed and pushed, 19 commits
since `88d9099`). Read CLAUDE.md, AGENTS.md, this file and the DESIGN.md sections named below first.
DESIGN.md is about 150 KB: read the bullets just above "## Reminders for the user" (this session's
work, newest first) and the reminders list. The previous handoff (`docs/HANDOFF_melee_and_fixes.md`)
is done.

## Done this session (all user approved where a look was involved)

- Hitboxes follow walking mechs (`PartHitbox.sync_to_physics = false`). This was why AI enemies took
  no damage and were not a target (white brackets).
- AI fires two-hand rifles on LMB and charges the beam rifle. Garage dropdowns for the AI enemy's and
  the dummy's weapon.
- Mechs collide (`Mech.collides_with_mechs`); wrecks and replaced mechs leave layer 2. Melee keeps a
  distance (`MeleeAttack.keep_away_distance`, 6 m, hammer swings 8 m).
- Left hand: one-hand guns, Pile Bunker, Fist, shields; two-hand weapons grey out the left picker;
  no doubled melee except the Fist. Left weapons have their own HP part "Weapon L".
- Shotgun (8 pellets, `WeaponData.pellets`). SMG spread 3.5 degrees.
- Melee rework: fist 3-swing combo (0.5 s after a hit), 5 s cooldown, aim-cone targeting with turn
  and glide, War Hammer RMB only with full A/D swings, feet kept on the ground (legs free of joint
  limits during melee). Pile Bunker 1 punch per 6 s.
- Jump and landing Mixamo clips (`JumpClipDirector`, `AirClipBody`), ankle pitch (`SkeletalAnklePitch`),
  empty hand swing (`FreeArmSwing`), relaxed arms after a weapon breaks.
- Face-down knock-down drops hand guns and rifles; get-up and pick-up (`WeaponDrop`, `WeaponPickup`).
  All mechs drop hand weapons on death.
- Dodge: damaged leg strain (`MechLegStrain`), quick step slow steps (3 steps at 0.4x), Hex Shield
  blocks the dodge. The new roll FBX was tried and reverted (the file stays in the library).
- Aim by weight class (`AimClassTuning`), camera aim leads the torso by 15 degrees at most.
- Environment damage: 1 HP per smashed chunk only; collapse blast 125 (was 250).
- Fixes: sparks, explosions and dust bursts spawned at the world origin; `Mech._ready` lost its
  footstep connection for a few commits (boost start steps); plating removed from the garage.

## Open: not in the DESIGN.md reminders (the pipeline)

See the list in the chat answer of 2026-10-16; the same items are below so they survive the session.

Waiting on the user:
1. ADS flinch "buffered" bug: not reproduced (hit clips start at once in ADS). The stale hitbox bug
   may have caused it. User to retest with the new build.
2. Heavy rifle self-hit: user said "skip for now". Not investigated further.
3. R reload: R is bound and reloads both hand guns and the pods. User to say which weapon fails.
4. UAL1/UAL2 GLB clips (`Shield_Dash` and others): need a new bone map in `retarget_mixamo.gd`
   (Unreal skeleton). User to choose a use for `Shield_Dash` (Pile Bunker charge or a shield dash).
5. Leg strain never destroys a leg (stops at 1 HP, `MechLegStrain.can_destroy_leg`): agent's choice,
   not confirmed by the user.

Known gaps and risks (not tested or not done):
6. Jump clips: the falls under 1 m (coded landing) were not tested in a run; the hard landing crouch
   may push the thighs into missile pods, a shield or the Pile Bunker; the waist aim twist is off
   while a clip is at full weight; feet hover 0.1 to 0.16 m in the landing clips.
7. Weapon pick-up: a long rifle may lie partly under the body; a small pop of the Auto Cannon model
   at the end of the lift; a charged beam rifle knocked on the back still fires on release; not
   checked: a mech that dies during the pick-up (the weapon on the ground).
8. A knocked-down (fallen, not wrecked) mech keeps its upright collision capsule: an invisible wall
   for about 2 to 5 s.
9. Left hand: the left Auto Cannon was not checked for clipping; the left Pile Bunker stake was not
   seen in a clean side view; the gun model is not mirrored (intended).
10. AI: it cannot use melee weapons or the Pile Bunker (excluded from its dropdown); it never fires a
    left hand weapon.
11. Melee: with no target the hammer swing carries the mech about 6 m; the HUD shows no melee cooldown
    (proposal: `MeleeWeapon.get_status_text()` returns `SkeletalMeleeAnimation.get_cooldown_left()`);
    `weapon_controller.gd` still maps LMB to the hammer (harmless: the melee node ignores it).
12. Weapons ("Weapon R", "Weapon L", "Shield", backs) have no HP indicator lamps.
13. Camera lead limit (15 degrees) and the torso turn speed: user to check the feel in play.
14. Unused files to clean up with the user's OK: `data/melee/hammer_combo_a.tres`,
    `hammer_combo_d.tres` (old `split_time`), plate data and `PlateMounter` (plating removed from the
    UI), `models/mixamo/library/New_dodge_roll_animation.fbx` (reverted roll).

## How to work here

- Git LFS: the mech model is LFS. Clone, then `git lfs pull` before Godot opens the project.
- Godot 4.7.2: `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
  to `/tmp/claude-0/godot/`, then `--headless --path . --import` once (a few minutes). Run `--import`
  again after adding a script with a new `class_name`.
- Never hand-edit `scenes/mech/sanggigilid.tscn`; change `tools/godot/build_sanggigilid.gd`. This
  session created new nodes at runtime instead (AnklePitch, FreeArmSwing, WeaponPickup, JumpClipDirector,
  left WeaponPose/Recoil/view).
- Test tools in the repo: `tools/godot/render_melee.gd` (all melee cases, hits, combos, cooldown, feet;
  renders with xvfb), `tools/godot/render_jump.gd` (jump and drop strips and logs).
- Renders: `xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . --rendering-driver opengl3
  --resolution 1280x720 --fixed-fps 60 --script <script.gd>`.
- Agents: the `implementer`, `reviewer` and other types in `.claude/agents/` load only in a session
  that started with them on disk. If missing, use `general-purpose` with model sonnet and tell it to
  follow `.claude/agents/implementer.md`. Give each agent its own files. A usage limit stopped agents
  once; SendMessage resumed them.
- Do not `pkill -f` a pattern that is also in your own command line.
- The user approves looks before commits (renders first), except when the user says "commit".
- On the user's PC: `git fetch origin`, `git checkout claude/modest-goodall-mft3bs`,
  `git pull origin claude/modest-goodall-mft3bs`, `git lfs pull`. Use `git --no-pager` in Termux.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md (the latest bullets and the reminders) and
> docs/HANDOFF_weapons_melee_animation.md. Then continue with the open items I pick from the
> handoff list. Ask me for the details you need.
