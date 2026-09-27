# Mechagame Design Spec

Third-person mecha action game.
Engine: Godot 4.7 (latest stable). Language: GDScript only. Platform: PC, keyboard and mouse.
Art style: realistic. Use placeholder shapes (boxes, capsules, cylinders) until Phase 8.

## Status

| Phase | Content | Status |
|---|---|---|
| 1 | Mech controller and third-person camera on a test map | Done |
| 2 | Part resources, sockets, assembler, stat calculator, weight-to-speed formula, debug HUD | Not started |
| 3 | Weapons: guns, lock-on missiles, sniper zoom, melee blade, energy use | Not started |
| 4 | Per-part HP, hitboxes, destruction, target dummies, enemy AI, greybox urban map with destructible props | Not started |
| 5 | Garage screen: swap parts, add plates, live stat preview. Graphics settings menu (low, medium, high) | Not started |
| 6 | Pilot creation and skill tree | Not started |
| 7 | Save/load builds (JSON) and 4 preset archetype loadouts | Not started |
| 8 | Realistic graphics pass and complete mech animation | Not started |

## Controls

| Input | Action | Input map name |
|---|---|---|
| WASD | Move | `move_forward`, `move_back`, `move_left`, `move_right` |
| Mouse | Aim (camera) | |
| Space | Hold on the ground to charge the jump jets, release to jump. No plain jump | `jump` |
| Shift | Boost (hold). Starts after 2 walking steps. Stops when released | `boost` |
| RMB | One-hand weapons: use the right arm weapon. Two-hand firearm: aim down sight (hold) | `use_right_arm`, `aim` |
| LMB | One-hand weapons: use the left arm weapon. Two-hand firearm: shoot | `use_left_arm` |
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
| Weight | 60 t (`mass_tons`) | fixed until Phase 2 computes it from parts |
| Walk speed | 9.1 m/s (33 km/h) forward, 90% to the side (8.19 m/s) | top speed in 1.75 s (acceleration 5.2 m/s²) |
| Walk stop | 2 steps from full walk speed | slower speeds take fewer steps |
| Boost start | only after 2 walking steps | HUD shows "Boost ready in N steps" |
| Boost speed | 1.5x walk = 13.65 m/s (49 km/h) | boost acceleration 20 m/s². Boost ends when Shift is released |
| Boost exit | small hop (6 m/s up), then 2 steps down to walk speed | if all keys are released: hop, then 4 steps to a stop |
| Boost energy use | 30 per second (50% of jump jets), capacity 100 | about 3.3 s of boost |
| Energy recharge | 17.5 per second after 2 s delay | empty energy locks boost until 30% |
| Jump jet charge | hold Space on the ground. 1 s = 33%, 2 s = 63%, 3 s = 100% of 9 m | the mech stops and crouches while it charges. Charge uses 33.3 energy per second (full charge = full tank). Charges below 10% cancel |
| Directional jump | hold a move key while charging | length 10 m at full charge, 6.3 m at 2 s, 3.3 m at 1 s (same fraction as height). A move key released up to 0.25 s before launch still counts |
| Gravity | x2.2 (21.6 m/s²) | launch speed is set so the jump reaches the charged height |
| Free air steering | a move key in the air moves the landing point up to 5 m, no energy | the steering speed is spread over the flight time. No key = momentum only |
| Air boost | Shift + a move key in the air: 25% of ground boost acceleration (5 m/s²) and top speed (3.41 m/s), added to the jump momentum. Boost energy use | with no energy there is no air boost |
| Landing steps | a landing with sideways speed: the mech walks out 3 steps to a stop | no control during the landing delay, but the momentum carries on |
| Landing recovery | falls below 1 m: 0.5 s. Higher: 1.5 s x (weight / 60 t) x (fall height / 9 m), minimum 0.5 s | no movement, jump charge, or boost. Legs crouch. Falls below 0.2 m and the boost exit hop give no delay |
| Body turn | 58.8°/s max, 252°/s² acceleration | in the last 25% of each turn the body turns at 50% speed. Turns above 5° end with a settle: 2° past the aim, 2° to the other side, then a snap onto the aim (about 0.55 s) |
| Footstep stride | 6 m at walk speed and above, down to 30% (1.8 m) near standstill | one camera shake per stride, none while boosting |

### Aim

| Value | Current |
|---|---|
| Camera crosshair | yellow dot at screen center |
| Mech aim reticle | blue ring. It shows where the weapon really points: body turn lag plus jitter |
| Aim jitter | 0.6° at full walk speed, 1.2° while boosting (2x), 2.4° in the air (2x boost) |
| Aim down sight (RMB) | FOV 70° to 35°, camera distance 8.5 m to 6 m, mouse sensitivity 50%. Rifle goes from high ready to the shoulder and points at the mech aim |

### Current camera tuning (Phase 1)

All values are exports on `MechCameraRig` and the `SpringArm` node.

| Value | Current |
|---|---|
| Distance behind mech (spring length) | 8.5 m |
| Shoulder offset | 4.5 m right |
| Pivot height | 7 m |
| Tilt limits | 27.5° down, 15° up |
| Boost shake | steady shake while boosting (trauma 0.4) |
| Aim spring | 1.75 Hz, damping 0.5: a fast 30° flick overshoots by about 4°, then settles |
| Max aim lag | 25° |

### Collision layers

| Layer | Name | Used by |
|---|---|---|
| 1 | world | ground, buildings, platforms |
| 2 | mechs | mech bodies |
| 3 | props | cars, lampposts, people (mechs pass through them until Phase 4 destruction) |

## Weapon controls (Phase 3)

- One-hand weapons: RMB uses the right arm weapon, LMB uses the left arm weapon.
- Two-hand firearm: RMB aims down sight, LMB shoots.
- "Use" means fire for guns and activate for shields and melee weapons.

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

## Animation

- Now (Phase 1): placeholder animation on box parts.
  - `MechLegSwing`: hip swing, knee bend, body bob, sway.
  - `MechLegTwist`: legs and pelvis turn toward the move direction (up to 75°). Walking backward keeps the legs forward and steps in reverse.
  - `TwoBoneIK`: arms reach grip markers on the weapon. The long rifle is held with two hands in a high ready position: stock low at the right chest, muzzle up 45° and 20° to the left.
  - `WeaponPose`: blends the rifle between high ready and the aim pose (RMB).
- Phase 8: complete animation on rigged .glb models. Walk cycles for biped, reverse-joint, tank, and quad legs. Leg IK so feet stay on slopes and steps. Torso twist toward the aim. Weapon recoil. Boost and jump jet poses.

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
scripts/mech/       mech.gd (movement), mech_input.gd (player input), mech_energy.gd, mech_footsteps.gd,
                    mech_jump_charge.gd, mech_air_steer.gd, mech_landing_recovery.gd, mech_aim.gd (camera target and real mech aim with jitter).
scripts/animation/  mech_leg_swing.gd, mech_leg_twist.gd, two_bone_ik.gd, weapon_pose.gd (placeholder animation).
scenes/weapons/     long_rifle.tscn (markers: GripRight, GripLeft, Muzzle).
scripts/camera/     mech_camera_rig.gd (follow and mouse look), aim_spring.gd (aim overshoot), camera_shake.gd, camera_ads.gd (aim down sight zoom).
scripts/world/      greybox_block.gd (box with collision, set size in Inspector).
scripts/ui/         debug_hud.gd, aim_reticle.gd.
scripts/core/       mouse_capture.gd.
```

### Phase 1 structure

- `Mech` (CharacterBody3D) does physics movement only. It reads intent from `MechInput`.
- `MechInput` reads keyboard and mouse. An AI input node can replace it in Phase 4.
- `MechEnergy` stores energy. Boost uses it now. Weapons use it in Phase 3.
- Mech visual tree: `Visual > Upper` (torso, head, arms, rifle) `> Lower` (pelvis, legs). Upper faces the aim. Lower twists toward the move direction.
- `MechLegSwing` is placeholder walk animation: hip swing, knee bend, body bob, and sway. Legs trail back while boosting and bend in the air. It reads the walk cycle from `MechFootsteps`, so each foot strike matches a footstep shake.
- `MechFootsteps` emits a `footstep` signal per stride. `CameraShake` listens to it and to `Mech.landed`.
- `MechCameraRig` is `top_level`, so it does not rotate with the mech. The mech body turns toward the camera yaw.
- Physics interpolation is on, so movement is smooth on high refresh rate monitors.
- Physics engine: Jolt.

## Decisions log

- Phase 1: Space was a jump plus hold-in-air jets. Replaced in revision 5 by charged jump jets.
- Phase 1: test map ground is 400 x 400 m with invisible walls at the edge. Distance fog hides the edge.
- Phase 1: the camera follows the mouse on a damped spring, so fast aim moves overshoot a little.
- Graphics settings menu goes in Phase 5.
- Phase 1: walk speed 9.1 m/s, boost 1.5x walk, hop and 2 steps when boost stops, 4 s energy recharge delay, body turn overshoot 10°.
- Phase 1: weapon is a 9 m long rifle held with two hands in high ready. RMB raises it to the shoulder (aim down sight).
- Phase 1 revision 4: walk accel for 2.25 s to top speed, strafe 90%, turn 84°/s, jets about 9 m, 2 s recharge delay at 17.5 per second, boost only after 2 steps, stop in 2 steps (walk) or 4 steps (boost), landing recovery by height and weight.
- Phase 1 revision 5: no plain jump. Hold Space to charge the jump jets (4 s = 9 m). Move keys in the air fire the boosters. No energy = no air steering.
- Landing delay: 0.5 s below 1 m, the height and weight formula above 1 m (minimum 0.5 s so a higher fall is never shorter).
- Phase 1 revision 6: walk top speed in 1.75 s. Jump charge 1 s = 33%, 2 s = 63%, 3 s = 100%. Free air steering 5 m, Shift + move key for air boost. 3 steps after a directional landing. Turn overshoot 3° with no return. Strides shorter at low speed.
- Phase 1 revision 7: directional jumps (move key while charging). Air boost at 25% power. Mech crosshair overshoot removed; the last 25% of a turn is at half speed.
- Phase 1 revision 8: directional jump 10 m at full charge. Air boost top speed 25%. Air jitter 2x boost jitter. Camera aim spring and body turn 30% slower. Body turn settle swings (2° each side) before lock-in.
- Weapon controls decided: RMB right arm, LMB left arm. Two-hand firearm: RMB aim, LMB shoot.
- Note for .tscn files: Transform3D text is row by row (basis rows, then origin).
- Phase 1: placeholder leg swing on the box mech. Phase 8 adds complete animation: walk cycles per leg type, leg IK on slopes, torso twist toward aim, weapon recoil, boost and jump jet poses.
- Phase 1: mechs pass through cars, lampposts, and people. Phase 4 makes these destructible.
