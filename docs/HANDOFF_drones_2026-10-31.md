# Handoff: Drone Pack, attack drones, drone aux mods, cool down (next: play tests or the next backpack)

Written 2026-10-31. Branch: `claude/backpacks-handoff-docs-nwe0op` (all work committed and pushed; it continues from
`ccr-4ae7246e-df2g54`, the commit of `docs/HANDOFF_backpacks2_2026-10-31.md`). Read CLAUDE.md, AGENTS.md, this file,
`docs/backpack_research.md`, and in DESIGN.md the sections "Backpacks" (the Drone Pack entry), "Attack drones" (every
user rule, rounds 1 to 5 and phase B, with the user's words) and "Reminders for the user".

## Done this session (commits, oldest first)

- `edb7e0b` Drone Pack from the user's picture (`models/guides/backpack_drone_ref.png`): gunmetal box, carry handles,
  detachable drone discs as `Drone<n>` nodes with `DroneDock<n>` empties.
- `685b847` More body, 3 drones per side; attack drones phase A (T lock and launch, pincer, bursts, shot down).
- `cac5f32` Round 2: drones stack on one axle per side; no flight through buildings; seek a firing place when the
  target hides; 20 m gun range; no move after the first shot; own weapons never hit own drones; AI launches drones,
  shoots enemy drones when efficient, else takes cover; garage "Enemy pack" picker.
- `09c4bef` Round 3: AI hits drones 75% with one-hit and charged shots (and uses the beam rifle on them); flight
  ceiling 12.5 m over the ground; over low buildings, around tall ones (grid path); never touches walls or corners.
- `830586a` Round 4: drones tilt up to 45 degrees, so they attack mechs on roofs above the ceiling; 1 aux slot kept.
- `7231b3f` Phase B: drone aux mods Drone Recall (back to the dock, 2 flights each) and Drone Swarm (all at once);
  garage "Aux" picker.
- `0713b8c` Round 5: one launch at a time; 10 s cool down from when the last drone is gone or docked.

## User decisions this session

- The Drone Pack has 1 aux slot and no stat bonus; its job is the 6 drones (3 stacked per side, outer first).
- T: hold to lock, release to launch a pair (one per side, opposite flanks: the pincer). 2 s to the target at 100 m,
  3 bursts of 0.5 s (one per second), 5 s flight in all, gun range 20 m, no move from the first shot.
- Drones fly at most 12.5 m over the ground (roofs do not count), over low buildings, around taller ones, never
  through or touching them; aim at most 45 degrees up.
- Own weapons never hit own drones. AI: launches drones, shoots enemy drones when its gun kills them fast (75% hit
  rate with one-hit and charged shots, for fairness), else takes cover.
- Aux mods are interchangeable aux equipment in the 1 aux slot (in place of the pulse scan).
- No launch while drones are active; 10 s cool down after (Claude chose "from when the last drone is gone or
  docked"; the user can ask for "from the launch").
- Claude's open choices (DESIGN "Attack drones"): a pair per launch; bullets already in the air at a launch can still
  hit a drone; the 75% applies only to AI shots at drones.

## How the drone code works

- Model: `tools/blender/backpack_build.py -- drone` (`build_drone_pack`, `build_drone`; helpers `cyl_x`, `seam`).
  Nodes: `Drone1..6` (all disc meshes under one node, X = disc axis), `DroneMuzzle<n>` (hub), `DroneDock1..6`, `Aux1`.
- Data: `data/parts/backpacks/backpack_drone.tres` (`BackPackPart.drone`), `data/equipment/attack_drone.tres`
  (`DroneData`: lock, flight, ceiling, tilt, path grid, attack, HP 60, cool down), `data/weapons/drone_gun.tres`,
  `data/equipment/drone_recall.tres` and `drone_swarm.tres` (`DroneModData`).
- Scripts: `DroneLauncher` (T, lock, launch, cool down, docking; added by `BackPackMount`), `AttackDrone` (phases
  LAUNCH, APPROACH, FIRE, RETURN), `DroneNavigator` (sphere sweeps, ceiling, AStarGrid2D path around tall buildings,
  firing places), `DroneMod` (aux device), `AIDroneTactics` (made by `AIPilot`), `DroneStatus` (HUD line),
  `AimReticle` (lock brackets), `Mech.get_hit_exclude` (adds own drones), `Missile.shooter_mech`.
- Garage: "Aux" picker under Backpack (`GarageCatalog.aux_items`), "Enemy pack" picker for the AI test target
  (`MechSpawner.set_back_pack`). `tools/data_gen/garage_data.py` knows the aux list (do not run it: it does not
  write the drone fields).
- Tests: `test_drone_pack.gd` (model, open field, low wall, tall wall, cover U, roof, no touch, ceiling, AI with a
  heavy rifle, an SMG and a beam rifle, the 75% roll; `DRONE_TRACE=1`, `AI_TRACE=1`, `DRONE_SHOT=<png>`) and
  `test_drone_mods.gd` (swarm, recall, cool down). Both 0 failures at the end; `test_boost_pack`, `test_ammo_pack`,
  `test_ammo_reserve`, `test_stability`, `test_pulse_scan`, `test_weapon_hands` 0 failures.
- A full `test_drone_pack` run takes about 3 minutes headless. With a window (xvfb) it takes over 10 minutes.

## Open (see DESIGN "Reminders for the user")

1. Play tests: the Drone Pack (look, stack, flight, seek, ceiling, roof attack, AI with each weapon), the drone mods,
   the cool down; then the earlier ones (Jet, Field, Power, Belt, Quad, Boost, Ammo, Missile and the first three
   packs, finite ammo, Pile Bunkers 2 to 5 and the Shield Bunker, the 2026-10-30 batch, the Auto Cannon grip,
   Phase 3).
2. Arm clipping in the guard and punch clips needs a user decision (`test_pile_bunker_clip` fails 4 cases).
3. Cross Punch FBX upload was empty; clip 3 left hand misses at 12 m.
4. Thumb grip in Blender.
5. Test mode on (`free_energy`, `free_scan`).
6. Pixel-art option not started.
7. PS1 look lifted (`data/skins/ps1_skin.tres` `enabled = false`).
8. Backpack later work: equipment models on `Aux` hardpoints, a break effect, a HUD canister count.

## Known small issues

- The AI with a heavy rifle (one round each 3 s) often cannot fire at drones in time; when buildings hide them it
  takes cover. Balance in play.
- The headless dummy renderer prints "Parameter material is null" now and then (engine, not game code).
- `backpack_build.py` has some lines over 120 characters from earlier sessions.

## How to work here

- Godot 4.7.2: download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
  to `/tmp/claude-0/godot/`, link `/usr/local/bin/godot`, `git lfs pull`, `godot --headless --path . --import`.
- Blender 4.0.2 headless (`blender -b`); Eevee does not run here (no EGL), use Cycles for pictures.
- Do not wait on a process with `while pgrep -f <name>`: the loop matches its own command line and never ends.
- The user's PC: `git fetch origin`, `git checkout claude/backpacks-handoff-docs-nwe0op`, `git pull`, `git lfs pull`.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, docs/HANDOFF_drones_2026-10-31.md and docs/backpack_research.md. Remind me of the open
> reminders, then continue: I will send play test results or the next backpack picture.
