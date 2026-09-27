# Mechagame Design Spec

Third-person mecha action game.
Engine: Godot 4.7 (latest stable). Language: GDScript only. Platform: PC, keyboard and mouse.
Art style: realistic. Use placeholder shapes (boxes, capsules, cylinders) until Phase 8.

## Status

| Phase | Content | Status |
|---|---|---|
| 1 | Mech controller and third-person camera on a test map | Revision 2 built, waiting for test |
| 2 | Part resources, sockets, assembler, stat calculator, weight-to-speed formula, debug HUD | Not started |
| 3 | Weapons: guns, lock-on missiles, sniper zoom, melee blade, energy use | Not started |
| 4 | Per-part HP, hitboxes, destruction, target dummies, enemy AI, greybox urban map with destructible props | Not started |
| 5 | Garage screen: swap parts, add plates, live stat preview. Graphics settings menu (low, medium, high) | Not started |
| 6 | Pilot creation and skill tree | Not started |
| 7 | Save/load builds (JSON) and 4 preset archetype loadouts | Not started |
| 8 | Realistic graphics pass | Not started |

## Controls

| Input | Action | Input map name |
|---|---|---|
| WASD | Move | `move_forward`, `move_back`, `move_left`, `move_right` |
| Mouse | Aim (camera) | |
| Space | Jump. Hold in the air for jump jets | `jump` |
| Shift | Boost | `boost` |
| LMB | Right arm weapon | `fire_right_arm` |
| RMB | Left arm weapon | `fire_left_arm` |
| Q / E | Left / right back weapon | `fire_back_left`, `fire_back_right` |
| Tab | Lock-on | `lock_on` |
| Esc | Free the mouse (click to capture again) | `ui_cancel` |

## Scale and maps

- 1 unit = 1 meter. Mech height is about 10 m.
- Speed, jump, boost, and camera are tuned for this size.
- Maps: small to medium urban arenas.
- Greybox all maps with simple shapes. Include human-scale props: cars (4.5 m), doors (2 m), lampposts (6 m), people (1.8 m).
- Camera: over-the-shoulder, low height, small shake on each heavy footstep.
- Movement has weight: gradual acceleration and deceleration.
- Performance: OccluderInstance3D for buildings, LightmapGI for static lighting, mesh LOD.

### Current movement tuning (Phase 1)

All values are exports on `Mech` (Inspector). Phase 2 will compute them from parts.

| Value | Current | Result |
|---|---|---|
| Walk speed | 14 m/s (50 km/h) | about 1.4 s to full speed |
| Acceleration / deceleration | 10 / 14 m/s² | heavy start and stop |
| Boost speed | 36 m/s (130 km/h) | about 0.5 s to full speed |
| Boost energy use | 30 per second, capacity 100 | about 3.3 s of boost |
| Energy recharge | 35 per second after 0.6 s delay | empty energy locks boost until 30% |
| Jump | 17 m/s, gravity x2.2 | about 6.7 m high |
| Jump jets | hold Space, start 0.25 s after jump | energy use 2x boost (60 per second), rise up to 8 m/s, about 19 m high on a full tank |
| Air control | 35% | boost gives full control in air |
| Body turn speed | 140°/s | body turns toward the camera direction |
| Footstep stride | 7 m | one camera shake per stride, none while boosting |

### Current camera tuning (Phase 1)

All values are exports on `MechCameraRig` and the `SpringArm` node.

| Value | Current |
|---|---|
| Distance behind mech (spring length) | 8.5 m |
| Shoulder offset | 4.5 m right |
| Pivot height | 7 m |
| Tilt limits | 27.5° down, 15° up |
| Aim spring | 2.5 Hz, damping 0.5: a fast 30° flick overshoots by about 4°, then settles |
| Max aim lag | 25° |

### Collision layers

| Layer | Name | Used by |
|---|---|---|
| 1 | world | ground, buildings, platforms |
| 2 | mechs | mech bodies |
| 3 | props | cars, lampposts, people (mechs pass through them until Phase 4 destruction) |

## Mech parts (all interchangeable)

- Head: HP, weight, sensor range, lock-on speed
- Core: HP, weight, energy capacity. Core destroyed = mech destroyed
- Arms (L/R): HP, weight, recoil control, melee bonus. Each arm holds one weapon
- Legs: HP, weight, load capacity, base speed, jump. Types: biped, reverse-joint, tank, quad
- Back units (L/R): missile pods, cannons, shields
- Booster: thrust, energy use
- Generator: energy output, recharge rate
- FCS (computer): lock-on range, max lock targets, aim assist
- Mod slots: small stat changes (example: +10% reload, -5% weight)

## Armor plating

Head, core, arms, and legs accept armor plates. Each plate adds HP and weight.

## Weight and speed

```
total_weight = sum of parts, weapons, plates
load_ratio = total_weight / legs.load_capacity
if load_ratio <= 1.0: speed = legs.base_speed * (1.0 - 0.3 * load_ratio)
if load_ratio >  1.0: speed = legs.base_speed * 0.7 / (load_ratio * load_ratio)
```

Boost power and turn speed also drop with weight.
All of this logic lives in one function so it is easy to tune.

## Destructible parts

Each part has its own HP and its own hitbox. Damage goes to the part that is hit.

- Head destroyed: lock-on range and HUD accuracy drop
- Arm destroyed: weapon on that arm is lost
- Legs destroyed: speed drops 60%, no jump
- Back unit destroyed: that weapon is lost
- Core destroyed: mech is destroyed

## Archetypes (preset loadouts; player can mix any parts)

- Melee: light, fast, blade arms, strong boost
- Gunner: medium weight, rifles and machine guns
- Missile: heavy back units, multi-lock FCS
- Sniper: long-range rifle, high-zoom head, slow

## Pilot

Name, callsign, portrait, skill tree.
Skills give passive bonuses (example: faster lock-on, less recoil, more boost energy).
One active skill slot (example: Overdrive, +30% speed for 8 seconds).

## Architecture rules

- Parts, weapons, mods, plates, and skills are Godot Resources (.tres) in `/data`. New parts need no code changes.
- Each part is its own scene with Marker3D sockets (example: `socket_head`, `socket_arm_L`, `socket_weapon`). MechAssembler attaches parts by socket. Placeholder meshes are replaced with .glb models later, with no code changes.
- MechAssembler builds a mech from a Loadout resource.
- StatCalculator computes final stats from parts, plates, mods, and pilot skills.
- Small scripts, one job per script.
- Debug HUD: total weight, load ratio, speed, HP of each part.
- Rendering: Forward+ renderer. PBR StandardMaterial3D, SDFGI, SSAO, SSR, volumetric fog, glow, AgX tonemap, TAA.
- Graphics settings menu (low, medium, high). Built in Phase 5.
- After each phase, explain in plain English what was built.

## Project layout

```
data/               Part, weapon, mod, plate, skill resources (.tres). From Phase 2.
materials/          Shared materials.
shaders/            greybox_grid.gdshader (1 m and 10 m grid lines).
scenes/levels/      test_map.tscn (main scene).
scenes/mech/        player_mech.tscn.
scenes/props/       greybox_block, car, lamppost, person, box_truck (8 m), semi_truck (16.5 m).
scenes/ui/          debug_hud.tscn.
scripts/mech/       mech.gd (movement), mech_input.gd (player input), mech_energy.gd, mech_footsteps.gd.
scripts/camera/     mech_camera_rig.gd (follow and mouse look), aim_spring.gd (aim overshoot), camera_shake.gd.
scripts/world/      greybox_block.gd (box with collision, set size in Inspector).
scripts/ui/         debug_hud.gd.
scripts/core/       mouse_capture.gd.
```

### Phase 1 structure

- `Mech` (CharacterBody3D) does physics movement only. It reads intent from `MechInput`.
- `MechInput` reads keyboard and mouse. An AI input node can replace it in Phase 4.
- `MechEnergy` stores energy. Boost uses it now. Weapons use it in Phase 3.
- `MechFootsteps` emits a `footstep` signal per stride. `CameraShake` listens to it and to `Mech.landed`.
- `MechCameraRig` is `top_level`, so it does not rotate with the mech. The mech body turns toward the camera yaw.
- Physics interpolation is on, so movement is smooth on high refresh rate monitors.
- Physics engine: Jolt.

## Decisions log

- Phase 1: Space is a jump. Holding Space in the air fires jump jets (MechWarrior 5 style). Jets use 2x the boost energy.
- Phase 1: test map ground is 400 x 400 m with invisible walls at the edge. Distance fog hides the edge.
- Phase 1: the camera follows the mouse on a damped spring, so fast aim moves overshoot a little.
- Graphics settings menu goes in Phase 5.
- Phase 1: mechs pass through cars, lampposts, and people. Phase 4 makes these destructible.
