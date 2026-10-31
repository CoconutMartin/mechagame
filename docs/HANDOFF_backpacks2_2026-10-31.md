# Handoff: eight new backpacks, outlets, flaps, petals, energy lights, PS1 lifted (next: more backpacks or play tests)

Written 2026-10-31. Branch: `ccr-4ae7246e-df2g54` (all work committed and pushed; it continues from
`ccr-3b56e290-ed99te`). Read CLAUDE.md, AGENTS.md, this file, `docs/backpack_research.md`, and in DESIGN.md the
section "Backpacks" (every pack, with the user's words), the "Mech texture picker" entry (PS1 lifted) and
"Reminders for the user". The previous handoff is `docs/HANDOFF_backpacks_2026-10-31.md`.

## Done this session (commits, oldest first)

- Boost Pack (`7e5abe3` .. `75d4cc9`): winged pack from the user's picture; fins shaped as an inverted K in the side
  view; recessed fin grilles with louver flaps that open to 90 degrees while boosting; glow and wind from the fin
  outlets; an energy bar on the box vent that dims with the energy, blinks twice at empty and brightens while
  recharging. More body later (`cc2db81`).
- Quad Booster (`25e43d5` .. `a5bb106`): four thruster pods with big nozzles; jet nozzle petals that open while
  boosting; a deeper tan center keel; one solid energy bar in a bezel.
- Belt Pack (`a5bb106`, `1d3d4bb`): ballistic support, an ammo belt whose rounds leave two at a time as guns refill
  (8 canisters, guns only).
- Power Pack (`d589863`, `8c70d36`): energy support (energy +25%), cells, towers, radiator, cables that glow with
  the energy level.
- Ammo Pack and Missile Pack more body (`c2ffe0b`).
- Field Pack and Jet Pack (`2190191`, `e6ae010`, `2439eda`): Field = 2 aux slots, part HP +6%; Jet = boost +10%,
  redesigned (the first looked like a smiley face), jet petals semi closed at rest, an energy gauge.
- PS1 look lifted (`2439eda`): `data/skins/ps1_skin.tres` `enabled = false`.

## User decisions and preferences this session

- Boost outlets glow and expel wind while boosting; on the Boost Pack the fin grilles are the outlets (the lower box
  vent is not).
- Outlets open while boosting: louver flaps open fully (right angle); jet petals are semi closed at rest and open
  fully while boosting.
- Energy indicator: bright light blue at full, color and brightness fade toward empty, two blinks at empty, slowly
  brighter while recharging. One solid bar (no segments).
- Every new pack: "beautify and add a bit more body". Avoid layouts that read as a face (two small slots over a
  line).
- Jobs and values of the packs were chosen by Claude and wait for the user's play test (DESIGN reminders).

## How the backpack features work (for the next pack)

- Builder: `tools/blender/backpack_build.py` (`TYPES` entry + `build_<kind>_pack`, registered in `main()`), run
  `blender -b --python tools/blender/backpack_build.py -- <kind>`, delete `*.blend1`. Helpers: `block`, `prism`,
  `cyl_z`, `loft` (tilted cross sections), `face_plate` (plates on a tilted face), `grille` (louvers, optional
  Boolean recess `cut`/`depth`, optional `flaps`), `nozzle_petal` (optional `axis`), `tube` (cables).
- Node names the game reads: `Mount`, `Aux1..N`, `Lamp`, `Canister1..N` (ammo), `Outlet1..N` (+Y in Godot = the
  wind direction) with `OutletGlow1..N` (glow plates), `OutletFlap*` and `NozzlePetal*` (turn about their own X
  axis), `EnergyBar` and `EnergyCable*` (energy light).
- Game scripts, all added by `BackPackMount` when the model has the nodes: `BackPackOutlets` (glow + wind while
  `Mech.is_boosting`), `BackPackFlaps` (`open_angle_deg` 90 flaps, `petal_open_deg` 30 petals),
  `BackPackEnergyBar` (bar unshaded, cables emissive; colors, blink and curve are exports).
- Data: `data/parts/backpacks/backpack_<name>.tres`, added by hand to `data/garage_catalog.tres` and to
  `tools/data_gen/garage_data.py` (do not run it).
- Pictures: Blender with `/tmp` Cycles scripts (see the previous handoff); in game `render_rifle.gd` with
  `RIFLE_PACK`; boosting pictures from `test_boost_pack.gd` (`BOOST_SHOT`, `QUAD_SHOT`, `JET_SHOT`, `POWER_SHOT`).
- Tests: `test_boost_pack.gd` (all boost, power, field and jet packs, PS1 off), `test_ammo_pack.gd` (ammo, missile,
  belt), `test_ammo_reserve`, `test_stability`, `test_pulse_scan`, `test_weapon_hands`: all 0 failures at the end.

## Open (see DESIGN "Reminders for the user")

1. Play tests: Jet, Field, Power, Belt, Quad and Boost Packs (jobs and values), Ammo and Missile Packs, finite ammo,
   the first three packs, the Pile Bunkers and Shield Bunker, the 2026-10-30 batch, the Auto Cannon grip, Phase 3.
2. Arm clipping in the guard and punch clips needs a user decision (`test_pile_bunker_clip` fails 4 cases).
3. Cross Punch FBX upload was empty; clip 3 left hand misses at 12 m.
4. Thumb grip in Blender.
5. Test mode on (`free_energy`, `free_scan`): with `free_energy` on the energy bars never fade.
6. Pixel-art option not started.
7. PS1 look lifted: set `enabled = true` in `data/skins/ps1_skin.tres` to bring it back.
8. Backpack later work: equipment models on `Aux` hardpoints, a break effect, a HUD canister count.

## Known small issues

- From the side, open Boost Pack flaps hide the glowing plate behind them.
- The garage skin picker still lists PS1 while it is lifted (it shows Basic).
- `backpack_build.py` has some lines over 120 characters from earlier sessions.

## How to work here

- Godot 4.7.2: download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
  to `/tmp/claude-0/godot/`, link `/usr/local/bin/godot`, `git lfs pull`, `godot --headless --path . --import`.
- Blender 4.0.2 headless (`blender -b`).
- The user's PC: `git fetch origin`, `git checkout ccr-4ae7246e-df2g54`, `git pull`, `git lfs pull`.

## Prompt for the new session

> Read CLAUDE.md, AGENTS.md, docs/HANDOFF_backpacks2_2026-10-31.md and docs/backpack_research.md. Remind me of the
> open reminders, then continue: I will send the next backpack picture or play test results.
