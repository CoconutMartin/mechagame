# Handoff: melee approval and weapon bug fixes (next session)

Written 2026-10-15. Branch: `ccr-e0d521dd-6ijish` (all work committed and pushed). Read CLAUDE.md,
AGENTS.md and the DESIGN.md sections named below first. The previous handoff
(`docs/HANDOFF_animations.md`) is done: all Mixamo library groups are in the game.

## Done this session (commits on the branch)

- `dd1f1bc` Hit reactions: small / medium / large by the damage of one hit (75 / 150), full body,
  joint limits (`JointLimits`). DESIGN.md "Hit reactions".
- `7c1f8a6` Death clips replace the tree fall (user table). Hit direction: `on_hit(damage, from, kind)`
  and `MechHealth.damage(key, amount, from, kind)`. DESIGN.md "Death animations".
- `8f42d6a` Stuns (standing stagger) and knock-downs with get-up (2x speed); `Mech.start_fall` blocks
  moving and firing. DESIGN.md "Stuns and knock-downs".
- `be6a773` Melee weapons: Fist (per arm) and War Hammer, placeholder models; environment flinch at
  4%; camera values moved into `tools/godot/build_sanggigilid.gd` (`_set_camera`): side offset
  6.75 m, camera tilt -5 degrees. DESIGN.md "Melee weapons", "Current camera tuning".
- `9393880` Weapon fixes: damage -25% (data and `tools/mech_gen`), charged beam aim kick after the
  beam ends, bullet tracers grow out of the muzzle.

## Open: what the user asked to continue with

1. **Melee look not approved yet.** The user agreed to the rules and the code is committed (user said
   "commit"), but has not seen melee renders. Render all attacks (fists: straight, W uppercut, S swipe,
   A left hook, D right hook; hammer: no key, S, A then D combo, A only) and ask for approval.
   - The render test at `/tmp/.../scratchpad/m/render_melee.gd` is lost with the container. Rebuild
     it: load `res://maps/urban_small/urban_small.tscn`, give the player fists or the hammer with
     `LoadoutSwitcher.rebuild(duplicated current_loadout, transform)`, spawn your own target from
     `res://scenes/mech/sanggigilid.tscn` (remove it from the `player` group; disable its MechInput and
     CameraRig) 7 m in front of the player along `mech.get_aim_yaw()`, set its HP high, press the
     mouse button and move key with `Input.action_press`, and log `MechHealth.damaged` on the target.
   - Do not use the spawner enemies from the `lockable` group as targets: in tests they took no damage
     (probably inactive until the spawner activates them).
   - Hide trees between the camera and the mechs before each capture (a tree blocked many renders).
2. **Bug: heavy rifle bullet hits the own mech and it flinches.** Not reproduced: bullets exclude all
   own hit boxes (`Mech.get_hit_exclude()`, checked with 6 loadouts) and own shots never damaged the
   player in headless tests. Questions sent to the user (waiting for answers): what was shot at and
   how far; did an HP indicator drop at the flinch. Candidates: debris or a building collapse blast
   from the own shots (`DebrisHurt` is now "environment" at 4%; `Blast` from buildings is not), the
   heavy rifle recoil read as a flinch, or the old tracer that reached back through the mech.
3. **Bug: flinches "buffered" during ADS and played after ADS ends.** Not reproduced: with hits
   during ADS (beam rifle, RMB held) `SkeletalHitAnimation` started the clip at once and queued
   nothing. Questions sent to the user: which weapon, charging or firing during ADS, how many flinches
   after RMB release, was the enemy still shooting. Check `CameraAds`, `WeaponPose` and the camera
   free look if the answers point there.
4. Melee review items left open (decided defaults, tell the user if asked): while an attack plays,
   normal hits play no hit reaction (stuns and knock-downs still end it); a kneeling mech is not
   stunned; melee damage was not cut by 25%.

## Open reminders (DESIGN.md "Reminders for the user")

- Recheck the hit clips, thresholds, cooldown and steady auto cannon fire; check the hit restart snap.
- Research a basic hammer strike (no key or W is a weaker downward strike for now).
- The straight punch and the Fist / War Hammer models are placeholders.
- Torso L HP indicator hidden from the camera; balance shoulder vs hand-held weapons; pulse scan;
  test with keyboard and mouse (the user now has a PC and pulled the branch); cars as shields.

## How to work here

- **Git LFS:** the mech model is LFS. A plain anonymous clone gets pointer files and Godot hangs on
  the model. Attach the repo with push access (`add_repo` access "push"), clone to
  `/home/user/mechagame`, then `git lfs pull`.
- **Godot:** download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
  to `/tmp/claude-0/godot/`, then `--headless --path . --import` once (a few minutes).
- **Scene:** never edit `scenes/mech/sanggigilid.tscn` by hand. Change `tools/godot/build_sanggigilid.gd`
  and run it (`--headless --path . --script res://tools/godot/build_sanggigilid.gd`). Hand edits
  are lost on the next rebuild (this happened to the camera values once).
- **Clip tools:** `tools/godot/retarget_mixamo.gd` (Mixamo FBX to the mech), `mirror_clip.gd` (left
  and right), `make_straight_punch.gd` (keyframed placeholder).
- **Renders:** `xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . --rendering-driver opengl3
  --resolution 1280x720 --fixed-fps 60 --script <script.gd>`. A side camera that follows the mech and
  a strip of 7 to 10 frames per clip worked well.
- **Do not `pkill -f` a pattern that is also in your own command line:** it kills your own shell.
- **Reviews:** use the `reviewer` agent for animation, damage and input changes (AGENTS.md). Reviews
  found real bugs every time (stuck triggers while down, enemy wreck timing, aim frame of the keys).
- `git --no-pager` for the user's Termux (no `less`). On the user's PC: `git fetch origin`,
  `git checkout ccr-e0d521dd-6ijish`, `git pull origin ccr-e0d521dd-6ijish`, `git lfs pull`.
- The user approves looks before commits (renders first), except when the user says "commit".

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, DESIGN.md and docs/HANDOFF_melee_and_fixes.md. Then render the melee
> attacks for my approval, and continue the weapon bug fixes (self-hit with the heavy rifle, flinches
> buffered during ADS). Ask me for the details you need.
