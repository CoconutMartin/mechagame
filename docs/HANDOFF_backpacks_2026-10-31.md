# Handoff: Pile Bunkers 2 to 5, backpacks, ammo packs, finite ammo (next session: more backpacks)

Written 2026-10-31. Branch: `ccr-3b56e290-ed99te` (all work committed and pushed). Read CLAUDE.md, AGENTS.md, this
file, `docs/backpack_research.md`, and in DESIGN.md the sections "Backpacks", "Pile Bunker 2 model" to "Pile
Bunker 5, the Shield Bunker", the decisions log entries of 2026-10-31 and "Reminders for the user". The previous
handoff is `docs/HANDOFF_playtest_rounds_2026-10-25.md`.

## Done this session (commits, oldest first)

- 2026-10-30 batch: charging clip and hold-to-charge fists, forearm twitch fix, Shift+3 tempered, part collisions
  (head limit, fist hits by the hand's box, arm keep-off), two Pile Bunkers, knuckle row, smooth crosshair return,
  War Hammer and Baton swing like fists.
- `e5ae168` Pile Bunker 2 (drill; spins from the power-up until the hit or miss). `b96953f`, `c68579d` Pile Bunker 3
  (one spike, in line with the forearm: mount tool `ALIGN=axis`). `7b5b0b3` Pile Bunker 4 (three claws open after a
  hit or miss). `a05f0f1` / `1378bfe` Pile Bunker 4B added and removed (user: not good). `86c1c54`, `1c2c619` Shield
  Bunker (Pile Bunker 5, 1000 HP, blocks with its body like the shields).
- `f2a6f5c` Backpacks replace the FCS: lock range and max locks on the missile pods; `BackPackPart` bonus; garage
  Backpack picker; Light, Aux and Heavy packs; `BackPackMount` (model on the `torso` bone, own HP part
  "Back Pack").
- `061c69b` Ammo Pack (6 canisters, every ammo weapon). `63e24bd` Missile Pack (4 canisters, missile pods only).
- `95349d3` Finite ammo: `WeaponData.reserve_magazines`, `MechWeapon.reserve_ammo`; an empty reserve takes a pack
  canister (one magazine); HUD "[reserve]" and "EMPTY".

## User decisions this session

- Backpack takes the FCS slot. "Assign max missile range and locks to missile equipment." Aim assist dropped.
- A backpack gives aux slots and one bonus (boost, energy or part HP). One Blender script builds every type.
- Ammo backpacks: "finite ammo, the pack is the reserve"; a used canister drops to the ground.
- New backpacks come from the user's pictures (front, side, top, back views), like the Pile Bunkers.

## How to build the next backpack (the pattern)

1. Copy the picture to `models/guides/backpack_<name>_ref.png`. Read the views: FRONT = the outer face (away from the
   mech), BACK = the face on the torso (the mount side).
2. In `tools/blender/backpack_build.py` add a `TYPES` entry (`kind="<name>"` and its numbers) and a
   `build_<name>_pack(t)` function; register it in `main()` (`builders`). Axes: Blender +Y = forward, the origin
   (`Mount`) is the center of the face on the torso, the pack goes back along -Y. Keep it under 8.8 m (the shoulder
   weapons) and inside |x| 1.15 m. Name consumable parts `Canister1..N` (empties at their centers, in use order),
   hardpoints `Aux1..N`, the glow mesh `Lamp`.
3. Build: `blender -b --python tools/blender/backpack_build.py -- <name>`; delete `*.blend1`. Render with
   `/tmp`-side scripts like this session's (Cycles CPU, `use_denoising = False`; EEVEE has no EGL here): 3/4 back,
   mount side, side, back, top. Compare with the picture, fix, render again (at most 3 passes).
4. Data: `data/parts/backpacks/backpack_<name>.tres` (`BackPackPart`: weight, HP, `aux_slots` 0 to 4, `bonus`,
   `bonus_percent`, `ammo_canisters`, `canister_kinds`, `scene` = the .glb). Add it by hand to
   `data/garage_catalog.tres` (`back_packs`) and to `BACK_PACKS` / `AMMO_CANISTERS` / `CANISTER_KINDS` in
   `tools/data_gen/garage_data.py` (do NOT run garage_data.py: its output no longer matches the hand-edited files).
5. `godot --headless --path . --import`, then in-game pictures:
   `RIFLE_OUT=<dir> RIFLE_RIGHT=- RIFLE_LEFT=- RIFLE_PACK=backpack_<name> RIFLE_PACK_USE=<n>
   RIFLE_BACK=missile_pod_l/missile_pod_r RIFLE_VIEWS=side,p_back xvfb-run -a -s "-screen 0 1280x720x24" godot
   --path . --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_rifle.gd`.
6. Tests: extend `tools/godot/test_ammo_pack.gd` for a canister pack; run `test_ammo_pack`, `test_ammo_reserve`,
   `test_stability`, `test_pulse_scan`, `test_weapon_hands`. Update DESIGN.md "Backpacks" and the reminders; commit.

## Open (see DESIGN "Reminders for the user")

1. Play tests: Ammo Pack, Missile Pack and finite ammo (tune `reserve_magazines`); backpacks; Shield Bunker and Pile
   Bunkers 2 to 4; the 2026-10-30 batch; Auto Cannon grip; Phase 3 items.
2. Arm clipping in the guard and punch clips needs a user decision (push the arms out more, a smaller chest
   collision, or keep). `test_pile_bunker_clip.gd` fails 4 cases (the charging clip pushes the Pile Bunker into the
   upper arm); `test_clip_self.gd` reports arm points in the chest. Both were open before the ammo work.
3. Cross Punch FBX upload was empty (clip slot 2). Clip 3 left hand misses at 12 m.
4. Thumb grip in Blender; `test_thumb_wrap` Beam Sniper left thumb fails (older).
5. Test mode on (`data/test/test_mode.tres`: `free_energy`, `free_scan`); turn off after the tests.
6. Pixel-art option not started.
7. Backpack later work: thruster flames at `Thruster1..2`, equipment models on the `Aux` hardpoints, a break effect,
   a HUD count of the canisters left (`BackPackMount.canisters_left`).

## Known small issues

- The missile pod calls `take_canister` every physics frame while it is empty (a cheap lookup).
- The garage backpack picker has no "none"; a loadout with no pack opens with the Light Pack selected.
- Enemies have finite ammo and no pack: they stop firing when empty.

## Tools added this session

- `compute_pile_bunker_mount.gd` (`MODEL`, `MIRROR`, `ALIGN=axis`), `measure_back.gd` (torso back face, back pack
  HP), `test_shield_bunker_block.gd`, `test_ammo_pack.gd`, `test_ammo_reserve.gd`; `test_pile_bunker_hit.gd`
  (`BUNKER`, miss case, drill and claw checks); `render_rifle.gd` (`RIFLE_PACK`, `RIFLE_PACK_USE`).

## How to work here

- Godot 4.7.2: `/tmp/claude-0/godot/Godot_v4.7.2-stable_linux.x86_64` (symlink `/usr/local/bin/godot`); if missing,
  download it (see the previous handoff), `git lfs pull`, then `godot --headless --path . --import` (about 3 min).
  Run the import again after adding a `class_name` script or a new model.
- Blender 4.0.2 headless (`blender -b`).
- The user's PC: `git fetch origin`, `git checkout ccr-3b56e290-ed99te`, `git pull origin ccr-3b56e290-ed99te`,
  `git lfs pull`.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, docs/HANDOFF_backpacks_2026-10-31.md and docs/backpack_research.md. Remind me of the
> open reminders, then continue building backpacks: I will send the next backpack picture.
