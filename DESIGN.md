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
| Ctrl | Kneel (toggle, 2 s down, 2 s up): right knee on the ground, left foot forward. No movement while kneeling | `crouch` |
| Shift | Boost (hold). Walk 2 steps, run 5 steps, then boost. Stops when released | `boost` |
| RMB | One-hand weapons: use the right arm weapon. Two-hand firearm: aim down sight (hold) | `use_right_arm`, `aim` |
| LMB | One-hand weapons: use the left arm weapon. Two-hand firearm: shoot | `use_left_arm` |
| Q / E | Left / right back weapon | `fire_back_left`, `fire_back_right` |
| Tab | Lock-on | `lock_on` |
| Esc | Free the mouse (click to capture again) | `ui_cancel` |

## Scale and maps

- 1 unit = 1 meter. Mech height is about 10 m.
- Speed, jump, boost, and camera are tuned for this size.
- Maps: small to medium urban arenas.
- Test map: about 58 small buildings (6 to 8 m), 8 medium (10 to 16 m), 3 tall (30, 34, 40 m). Platforms: steps 3, 6, 9, 12 m, a 15° ramp to a 13 m deck, a 2.5 m loading dock, a 5 m plaza, a 3 m wall.
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
| Boost start | Shift held: 2 walking steps, then 5 running steps (run speed 1.25x walk = 11.4 m/s, 12° torso lean), then boost | HUD shows "Boost ready in N steps" |
| Boost speed | 1.5x walk = 13.65 m/s (49 km/h) | boost acceleration 20 m/s². Boost ends when Shift is released |
| Boost exit | one big hop on one leg (7.5 m/s up, about 9.5 m forward), then 3 smaller steps down to walk speed. With no key: hop, then 3 steps to a stop | if all keys are released: hop, then 4 steps to a stop |
| Boost energy use | 30 per second (50% of jump jets), capacity 100 | about 3.3 s of boost |
| Energy recharge | 17.5 per second after 2 s delay | empty energy locks boost until 30% |
| Jump jet charge | hold Space on the ground. 1 s = 33%, 2 s = 63%, 3 s = 100% of 9 m | the mech stops and crouches while it charges. Charge uses 33.3 energy per second (full charge = full tank). Charges below 10% cancel |
| Directional jump | hold a move key while charging | length 10 m at full charge, 6.3 m at 2 s, 3.3 m at 1 s (same fraction as height). A move key released up to 0.25 s before launch still counts |
| Gravity | x2.2 (21.6 m/s²) | launch speed is set so the jump reaches the charged height |
| Free air steering | a move key in the air moves the landing point up to 5 m, no energy | the steering speed is spread over the flight time. No key = momentum only |
| Air boost | Shift + a move key in the air: 25% of ground boost acceleration (5 m/s²) and top speed (3.41 m/s), added to the jump momentum. Energy use 84 per second (2.8x ground boost) | with no energy there is no air boost |
| Landing steps | a landing with sideways speed: the mech walks out 3 steps to a stop | no control during the landing delay, but the momentum carries on |
| Landing recovery | falls below 1 m: 0.5 s. Higher: 1.5 s x (weight / 60 t) x (fall height / 9 m), minimum 0.5 s | no movement, jump charge, or boost. Legs crouch. Falls below 0.2 m and the boost exit hop give no delay |
| Torso twist limits | 20° to the left, 160° to the right of the legs | the legs turn (60°/s) only to follow movement or when the aim goes past a limit |
| Torso aim turn | 58.8°/s max, 252°/s² acceleration | in the last 25% of each turn the body turns at 50% speed. Turns above 5° end with a settle: 2° past the aim, 2° to the other side, then a snap onto the aim (about 0.55 s) |
| Footstep stride | 6 m at walk speed and above, down to 30% (1.8 m) near standstill | one camera shake per stride, none while boosting |

### Aim

| Value | Current |
|---|---|
| Camera crosshair | yellow dot at screen center |
| Mech aim reticle | blue ring. It shows where the weapon really points: body turn lag plus jitter |
| Aim jitter | 0.6° at full walk speed, 1.2° while boosting (2x), 2.4° in the air (2x boost), 75% less while kneeling |
| Aim down sight (RMB) | camera moves to the right side of the head (3 m right, 4 m back, head height 9.6 m), FOV 70° to 35°, mouse sensitivity 50%. Rifle butt on the right shoulder, torso turns 30° right and tilts 6°, left hand under the handguard near the muzzle |

### Current camera tuning (Phase 1)

All values are exports on `MechCameraRig` and the `SpringArm` node.

| Value | Current |
|---|---|
| Distance behind mech (spring length) | 8.5 m |
| Shoulder offset | 4.5 m right |
| Pivot height | 7 m |
| Tilt limits | 27.5° down, 15° up |
| Boost shake | steady shake while boosting (trauma 0.4) |
| Air shake | steady shake in the air: rising 0.44, falling 0.28 (50% less than before). Aim jitter moves only the blue ring |
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
  - `TwoBoneIK`: arms reach grip markers on the weapon. The long rifle rest pose follows stick figure reference 2: weapon low across the front, stock tucked under the right arm, muzzle down 18° toward the front left, right hand on the grip at mid body with the right elbow out, left hand under the front at hip level with the left elbow out.
  - `WeaponPose`: blends the rifle between the rest pose and the aim pose (RMB). It also moves the left grip (GripLeftRest / GripLeftAim) and the elbow directions.
  - `TorsoPose`: torso (above the waist) twists toward the mech aim inside the twist limits, leans 30° forward after a landing (fades with the landing delay), leans 35° forward while boosting on the ground, turns 30° right and tilts 6° when aiming, leans 8° when kneeling.
  - Crouch: 20° hip bend and 40° knee bend (inside knee angle 140°) while boosting on the ground. Landing crouch 8° (short fall) to 40° (9 m fall or higher).
  - `MechKneel`: Ctrl toggles the kneel pose (0.13 s down or up), body drops 1.74 m.
  - Walk: forward leg knee bend 60° and hip lift 20.4°. Run: hip swing 40°, knee bend 70°, hip lift 20°.
- Mech visual tree update: `Visual > Upper > Torso` (pivot at the waist, 5.4 m) holds the core, head, arms, and rifle. `Upper > Lower` holds the pelvis and legs.
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
- Phase 1 revision 9: air boost energy use +300% (120 per second). Camera shake in the air.
- Phase 1 revision 10: crouch while ground boosting, landing crouch depth by fall height, ADS camera at the side of the head, rifle held across the chest with the muzzle up (text requirements; the reference image shows the muzzle down).
- Phase 1 revision 11: rifle rest pose follows the reference image. ADS camera 3 m right and 4 m behind the head, stock on the right shoulder with a torso turn. Rising air shake 4x. Ground boost crouch with 35° torso lean. Ctrl kneel.
- Phase 1 revision 12: one-leg boost exit hop, run phase before boost, air boost energy 84 per second, rising air shake 40% less, kneel toggle 3x faster with 75% less jitter, higher knees, stick figure rifle pose. Landing delay also for falls off edges during the boost exit hop. Map: most buildings 35 m, towers 85 m, 90 m and 120 m, step tower 8/16/24/32 m to a 35 m deck next to a 35 m rooftop.
- Mech height stays 10 m (decided).
- Phase 1 revision 13: torso twist limits (20° left, 160° right) with legs turning only past the limits or to follow movement. Run 5 steps before boost. Boost exit: big one-leg hop and 3 steps. Kneel 2 s. Landing torso lean 30°. Knee lift +70%. Air shake 50% less. New rifle rest pose. New city: mostly small buildings.
- Weapon controls decided: RMB right arm, LMB left arm. Two-hand firearm: RMB aim, LMB shoot.
- Note for .tscn files: Transform3D text is row by row (basis rows, then origin).
- Phase 1: placeholder leg swing on the box mech. Phase 8 adds complete animation: walk cycles per leg type, leg IK on slopes, torso twist toward aim, weapon recoil, boost and jump jet poses.
- Phase 1: mechs pass through cars, lampposts, and people. Phase 4 makes these destructible.
