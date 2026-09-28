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
| W / S | Walk forward / back along the legs (MechWarrior style) | `move_forward`, `move_back` |
| A / D | Turn the legs at a steady speed (60°/s moving, 30°/s standing). The legs turn only with A / D and keep their heading when the mech stops | `move_left`, `move_right` |
| Middle mouse / X (hold) | Re-center: moves the mech aim (blue ring) back onto the camera crosshair after shot kicks, at 4°/s | `recenter_aim` |
| V (hold) | Front view: the camera swings around to the front of the mech (about 0.33 s). The mech aim stays on the torso direction and the crosshair hides | `front_view` |
| Mouse | Aim. Sets the torso target (up to 52° left and 64° right of the legs). The torso turns at its turn speed and the camera always stays behind the torso | |
| Space | Hold on the ground to charge the jump jets, release to jump. No plain jump | `jump` |
| Space x2 | Double tap (within 0.3 s): dodge hop. A / D = side, W = forward, S or no key = back | `jump` |
| Ctrl | Kneel (toggle, 1.25 s down, 1.25 s up, camera moves down and up with it). W also stands the mech up: right knee on the ground, left foot forward. No movement while kneeling | `crouch` |
| Shift | Boost (hold with a move key). Walk 2 steps (skipped if already walking), then always 2 run steps, then boost. Stops when released | `boost` |
| RMB | One-hand weapons: use the right arm weapon. Two-hand firearm: aim down sight (hold) | `use_right_arm`, `aim` |
| LMB | One-hand weapons: use the left arm weapon. Two-hand firearm: shoot | `use_left_arm` |
| Q / E | Left / right back weapon | `fire_back_left`, `fire_back_right` |
| Tab | Lock-on | `lock_on` |
| Esc | Free the mouse (click to capture again) | `ui_cancel` |

## Scale and maps

- 1 unit = 1 meter. Mech height is about 10 m.
- Speed, jump, boost, and camera are tuned for this size.
- Maps: small to medium urban arenas.
- Test map: 206 x 206 m (walls at ±102.6 m, 30% more area since revision 47). 5 small buildings (6 to 8 m), 5 medium (10 to 16 m), 3 tall (30, 34, 40 m). Platforms: steps 3, 6, 9, 12 m, a 15° ramp to a 13 m deck, a 2.5 m loading dock, a 5 m plaza, a 3 m wall. Main street about 68 m wide with lampposts.
- Greybox all maps with simple shapes. Include human-scale props: cars (4.5 m), doors (2 m), lampposts (6 m), people (1.8 m).
- Camera: over-the-shoulder, low height, small shake on each heavy footstep.
- Movement has weight: gradual acceleration and deceleration.
- Performance: OccluderInstance3D for buildings, LightmapGI for static lighting, mesh LOD.

### Current movement tuning (Phase 1)

All values are exports on `Mech` (Inspector). Phase 2 will compute them from parts.

| Value | Current | Result |
|---|---|---|
| Weight | 60 t (`mass_tons`) | fixed until Phase 2 computes it from parts |
| Walk speed | 9.1 m/s (33 km/h) forward and back (no strafe) | top speed in 1.75 s (acceleration 5.2 m/s²) |
| Walk stop | 2 steps from full walk speed | slower speeds take fewer steps |
| Boost start | Shift held: 3 walking steps (skipped if the mech already walked 3 steps), then always 4 running steps (run speed 1.25x walk = 11.4 m/s, 12° torso lean), then boost | HUD shows "Boost ready in N steps" |
| Boost speed | 1.5x walk = 13.65 m/s (49 km/h) | boost acceleration 20 m/s². Boost ends when Shift is released |
| Boost exit (SKID, current) | feet plant and slide (6.7 m/s² slowdown, about 12.4 m in 1.4 s, down to 4 m/s, 40% longer since revision 47), knees bent, torso leans 15° back, dust from the feet, camera shake. Then 2 short heavy steps (0.45 m, 0.35 m, about 0.4 s) to a stop, or walking again with W held. The torso sways forward and back on a spring (0.9 Hz, damping 0.3) and is upright after about 2 s. It also rolls to a random side (3° to 7°) and sways back. The whole body turns 15° to 30° to the same side during the slide (like a drift) and turns back to center in the recovery (`SkidBodyTurn`, visual only) | `Mech.boost_exit_style` = SKID |
| Boost exit (LEAP, "revert 1") | one low leap forward (5 m/s up, about 6 m) that lands on one leg, then 2 medium steps (4.8 m) and 2 small steps (3.4 m) | `Mech.boost_exit_style` = LEAP. Also saved as commit f51bd42 | if all keys are released: hop, then 4 steps to a stop |
| Boost energy use | 30 per second (50% of jump jets), capacity 100 | about 3.3 s of boost |
| Energy recharge | 17.5 per second after 2 s delay | empty energy locks boost until 30% |
| Jump jet charge | hold Space on the ground. 1 s = 33%, 2 s = 63%, 3 s = 100% of 9 m | the mech stops and crouches while it charges. Charge uses 33.3 energy per second (full charge = full tank). Charges below 10% cancel |
| Directional jump | hold a move key while charging | length 10 m at full charge, 6.3 m at 2 s, 3.3 m at 1 s (same fraction as height). A move key released up to 0.25 s before launch still counts |
| Gravity | x2.2 (21.6 m/s²) | launch speed is set so the jump reaches the charged height |
| Free air steering | a move key in the air moves the landing point up to 5 m, no energy | the steering speed is spread over the flight time. No key = momentum only |
| Air boost | Shift + a move key in the air: 25% of ground boost acceleration (5 m/s²) and top speed (3.41 m/s), added to the jump momentum. Energy use 84 per second (2.8x ground boost) | with no energy there is no air boost |
| Landing steps | a landing with sideways speed: the mech walks out 3 steps to a stop | no control during the landing delay, but the momentum carries on |
| Landing shake | camera shake 0.045 per m/s of fall speed, camera drop 0.05 m per m/s (a 9 m fall: about 1.2 m drop, then recovers) |
| Landing recovery | falls below 1 m: 0.5 s. Higher: 1.5 s x (weight / 60 t) x (fall height / 9 m), minimum 0.5 s | no movement, jump charge, or boost. Legs crouch. Falls below 0.2 m and the boost exit hop give no delay |
| Torso twist limits | 52° left, 64° right of the legs (20% less since revision 50) | the camera stays behind the torso and turns with it. The legs turn only with A / D. Lower-leg twist (pelvis down) up to 60° each side |
| Wall bump | into a wall faster than 3 m/s | restitution (bounce-back speed / impact speed) grows with impact speed: 0.4 at 3 m/s to 0.9 at 13.65 m/s. Then an extra slowdown of up to 30% (less at low speed). Walk 9.1 m/s bounces back at about 5 m/s; boost 13.65 m/s at about 8.6 m/s. Camera shake |
| Walk sway | body roll 0.63° (walk) to 0.84° (run), side shift 0.063 m toward the planted leg, for a 10 m mech (30% less since revision 45) | scales with `Mech.height_m` (taller mechs sway more) |
| Footstep shake | camera kick 0.117 m, trauma 0.2, for a 10 m mech | scales with `Mech.height_m` |
| Shake overall | `CameraShake.intensity` 0.75, noise speed 21, final offset smoothing 100. Kicks return on a spring (2.2 Hz, damping 0.45) with a small bounce | |
| Movement start kicks | camera drop 0.2 m (0.267 before intensity) at boost start, skid start, takeoff, the top of a jump, and each wall bump | |
| Dodge hop | double tap Space (within 0.3 s). While boosting: always forward, and the boost goes on after the first tap: a low hop (1.5 m high) of 11.9 m (50% of the old dodge roll) in about 0.77 s. A / D = side, W = forward, S or no key = back. The mech leans into the hop (up to 10° toward the hop direction) and tucks its legs a little. It lands with 10 m/s left, in a small crouch, springs upright (1.2 Hz, damping 0.45), skids with two brake thrusters firing (5.3 m, down to 4 m/s), then takes 2 steps (1.5 m each) to a stop. A dodge from a boost keeps its momentum: it hops at about 20.9 m/s (about 15.6 m) and skids 28 m in 2.25 s. No landing delay (unless it falls off an edge). 25 energy, 0.2 s recovery, camera kicks at start and landing. The inertia sway pauses during the hop and its recovery | `MechDodge` |
| Inertia sway | `InertiaSway`: the torso leans 1.2° per m/s² of speed change (slowing = forward), rolls 1° per m/s² sideways, lags 0.1 s behind leg turns (max 10°). Springs at 1.3 Hz, damping 0.35, so movements end with a sway. 40% less while boosting | |
| Turning steps | standing still with the legs turning: one step every 20° of leg turn, knee lift 60% of the walk lift, light footstep shake | the feet do not slide |
| Torso aim turn | 44.1°/s max, 189°/s² acceleration | in the last 25% of each turn the torso turns at 50% speed, then stops exactly on the aim (no overshoot, no settle swings) |
| Footstep stride | 6 m at walk speed and above, down to 30% (1.8 m) near standstill | one camera shake per stride, none while boosting |

### Aim

| Value | Current |
|---|---|
| Camera crosshair | yellow dot 13.5% of the screen height above the center (matches the reference screenshot). `MechAim.screen_offset_up` |
| Mech aim reticle | blue ring, placed from the torso angle (no shake, no jitter). The camera follows the torso, so it sits on the yellow dot |
| Aim jitter | removed (0°). The code and exports stay in `MechAim` for later use |
| Vertical aim | mouse pitch speed 30% of horizontal |
| Aim down sight (RMB) | camera moves in along the aim line (10.3 m to 4 m) and zooms FOV 70° to 35°, same target, mouse sensitivity 50%. Rifle butt on the right shoulder, torso turns 30° right and tilts 6°, left hand under the handguard near the muzzle |

### Current camera tuning (Phase 1)

All values are exports on `MechCameraRig` and the `SpringArm` node.

| Value | Current |
|---|---|
| Distance behind the pivot (spring length) | 10.3 m. RMB moves it to 4 m and zooms (FOV 35°) |
| Shoulder offset | 3 m right (right side of the head) |
| Pivot height | 11.5 m (above the head). The camera sits on the aim line behind the pivot and tilts down by the crosshair angle (about 10.7° at FOV 70°), so it looks down over the head |
| Start view | aim pitch starts at -10° (set by the user); with the crosshair tilt the view is about 21° down over the head. `MechCameraRig.start_pitch_deg` |
| Same target in ADS | the camera stays on the aim line and its tilt follows the FOV, so the crosshair points at the same spot with and without RMB |
| Tilt limits | 27.5° down, 15° up |
| Boost shake | steady shake while boosting (trauma 0.4) |
| Air shake | steady shake in the air: rising 0.44, falling 0.28 (50% less than before). Aim jitter moves only the blue ring |
| Aim spring | 1.75 Hz, damping 1.0 (no overshoot) |
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
- Now (revision 47): the Warden rifle is a one-hand weapon. Hold RMB: hip fire, 1 shot every 2 seconds, no zoom (one-hand weapons never zoom). Each shot moves the mech aim (blue ring) 1.5° off the crosshair in a random direction. It stays there until the next shot (no automatic return). Re-center with the mouse: the blue ring stays still in the world, so moving the view toward it brings the crosshair onto it. Moves in other directions move both together. Or hold the re-center key (middle mouse button or X): the ring moves back onto the crosshair at 4°/s. Hold LMB: the shield on the left arm lifts in front of the chest. Two-hand weapons keep the ADS zoom on RMB.
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
  - `TorsoPose`: torso (above the waist) twists toward the mech aim inside the twist limits, leans forward after a landing in proportion to the fall height (30° at 9 m, fades with the landing delay), leans 21° forward while boosting on the ground, turns 30° right and tilts 6° when aiming, leans 8° when kneeling.
  - Crouch: 14° hip bend and 28° knee bend while boosting on the ground. Landing crouch 8° (short fall) to 40° (9 m fall or higher).
  - `MechKneel`: Ctrl toggles the kneel pose (0.13 s down or up), body drops 1.74 m.
  - Walk: forward leg knee bend 60° and hip lift 20.4°. Run: hip swing 40°, knee bend 70°, hip lift 20°.
- Player mech look (revision 42, changed in 43): "Warden", from reference image 9. No missile rack (removed in revision 43). Weathered grey armor plates. The head is built into the center torso, with a red eye, two round sensor ports below it and a fin on top. Emblem on the right torso. Big pauldrons. Hex shield with a chevron on the left forearm. Square hip plates, round knee joints, claw feet (3 toes and a heel). Legs 20% thicker since revision 44. No blade antenna since revision 44. Heavy rifle (`heavy_rifle.tscn`, 5.3 m since revision 43) with a straight barrel on the bore line. Colors are in `materials/warden/`. Hips are 1.5 m from the center.
- Saved model "Granpa Gundam" (revision 41): RX-78-2 style, in `scenes/mech/granpa_gundam.tscn` with `beam_rifle.tscn` and `materials/rx78/`. It is a complete player mech scene. The Gundam design belongs to Sunrise and Bandai, so a public release needs an original design.
- Models are built from box, cylinder, sphere and prism shapes by Python scripts in `tools/mech_gen/` (run from the project root). `mech_scene.py` holds the shared skeleton and logic nodes. `warden.py` writes `player_mech.tscn`. `granpa_gundam.py` writes `granpa_gundam.tscn`. Give another path as the first argument to write somewhere else. Placeholders until Phase 8.
  - One-hand rifle (revision 43): the rifle is 60% of its old size (5.3 m). Rest pose is one-hand high ready (reference image 10): grip in the right hand in front of the right shoulder, elbow down, muzzle up. The left arm hangs at the side with the shield (20% larger) on the outside. `LeftHand` markers on the torso replace the left grip on the rifle.
  - Hip fire (revision 44): the stock goes to the right hip (AimAnchor) and the rifle points at the mech aim point. No torso twist, no zoom.
  - Rifle rest (revision 47): ready to fire, level at the right hip, muzzle forward and 5° down.
  - Left arm (revision 47, drawing 11): shield down = upper arm down, forearm forward and 20° down, shield on the outside along the forearm. Shield up (LMB) = shield diagonal (40°) across the front of the torso, top toward the right shoulder, hand behind it. `ShieldMount` blends the shield between the two places after the arm IK. The shield takes 0.5 s to come up (60% slower).
  - `WeaponFire`: bullets with tracers (400 m/s, 0.4° spread, tracer 0.25 m thick and 10.5 m long) fly to the mech aim point. Muzzle flash with a light, small camera shake. `Bullet` checks each step with a ray and makes `ImpactSpark` sparks where it hits. No damage yet (Phase 4).
  - `WeaponRecoil`: each shot kicks the rifle 0.7 m back, 10° up and up to 3° to the side, on a spring (5 Hz, damping 0.55). The hand IK follows the grip.
  - `BoosterFlames`: fire and an orange light from the two backpack thrusters while boosting (80% length on the ground), air boosting, rising on the jump jets and during a dodge hop (burst at the start).
  - Dodge hop ending (revision 46): at the landing a short skid starts (feet slide with dust, body turns) from 10 m/s down to 4 m/s in about 1.8 m (60% shorter than the boost skid), then 2 heavy steps (1.5 m each) to a stop.
  - After the dodge skid the torso sways exactly 8° forward (the push is solved from the lean at the skid end), then settles on the skid spring (`TorsoPose.dodge_exit_forward_sway_deg`).
  - `BrakeThrusters`: two small thruster pods on the pelvis sides fire during the dodge skid. The fire points the way the mech slides (a stabilizer and brake against the momentum). The legs face the body front in the air and turn toward the slide after the landing.
  - Shield up (LMB): top move speed = 6 m/s x 13.6 m² / shield area (`MechShield`). The Warden shield is 10.9 m² since revision 48 (20% narrower), so 7.5 m/s. A bigger shield is slower (limits 2 to 9.1 m/s).
  - Warden upper body (torso, head, arms) is 85% size since revision 45 (`UPPER_BODY_SCALE` in `tools/mech_gen/warden.py`). Arm IK lengths 2.295 m and 2.55 m. Rifle and shield keep their size.
  - `ShieldPose`: LMB moves the left hand from the side to a raised place in front of the left chest (forearm up, shield facing forward).
  - `SkirtFollow`: front waist plates turn with the thigh that swings forward (80%). The rear plate turns with the thigh that swings back.
- Mech visual tree: `Visual > Roll > Upper` (Roll is free for future whole-body moves; the dodge roll was removed). `Visual > Roll > Upper > Torso` (pivot at the waist, 5.4 m) holds the core, head, arms, and rifle. `Upper > Lower` holds the pelvis and legs.
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
materials/          Shared materials. warden/ and rx78/ hold the mech colors.
shaders/            greybox_grid.gdshader (1 m and 10 m grid lines).
scenes/levels/      test_map.tscn (main scene).
scenes/mech/        player_mech.tscn (Warden), granpa_gundam.tscn (saved RX-78-2 style model).
tools/mech_gen/     Python generators for the mech models and rifles (Godot ignores this folder).
scenes/props/       greybox_block, car, lamppost, person, box_truck (8 m), semi_truck (16.5 m).
scenes/ui/          debug_hud.tscn.
scripts/mech/       mech.gd (movement), mech_shield.gd (shield lift and speed limit), mech_input.gd (player input), mech_energy.gd, mech_footsteps.gd,
                    mech_jump_charge.gd, mech_air_steer.gd, mech_landing_recovery.gd, mech_aim.gd (camera target and real mech aim with jitter).
scripts/animation/  shield_pose.gd, shield_mount.gd, mech_leg_swing.gd, mech_leg_twist.gd, two_bone_ik.gd, weapon_pose.gd, torso_pose.gd,
                    inertia_sway.gd, skid_body_turn.gd, skirt_follow.gd (placeholder animation).
scripts/weapons/    weapon_fire.gd, weapon_recoil.gd, bullet.gd. Scenes: scenes/weapons/bullet.tscn, scenes/effects/impact_spark.tscn.
scenes/weapons/     heavy_rifle.tscn (Warden), beam_rifle.tscn (Granpa Gundam), long_rifle.tscn (old box rifle). Markers: GripRight, GripLeft, GripLeftRest, GripLeftAim, Muzzle.
scripts/camera/     mech_camera_rig.gd (follow and mouse look), aim_spring.gd (aim overshoot), camera_shake.gd, camera_ads.gd (aim down sight zoom).
scripts/world/      greybox_block.gd (box with collision, set size in Inspector).
scripts/ui/         debug_hud.gd, aim_reticle.gd.
scripts/effects/    skid_dust.gd (dust while skidding), brake_thrusters.gd, booster_flames.gd, muzzle_flash.gd, impact_spark.gd.
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

## Reminders for the user

- Update the dodge hop animation (requested after Phase 1 revision 40). Revision 43 added the landing ending; the hop itself is still the simple version. Bring this up before Phase 1 is closed, and again at the start of Phase 2 if still open.

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
- Phase 1 revision 14: MechWarrior 5 style controls (W / S walk, A / D turn legs, mouse twists the torso inside the limits). Map area 60% smaller. Kneel 1.25 s with camera height. Walk 3, run 4, then boost. Boost exit: hop, 2 medium steps, 2 small steps. Landing lean by fall height.
- Phase 1 revision 15: arcade controls (mouse aims, legs follow at a steady 60°/s, A / D strafe with leg twist). Torso twist 5° each side. Boost exit with no hop: big step, 2 medium, 2 small. Stronger landing shake. Small buildings 40% fewer.
- Phase 1 revision 16: camera limited by the torso twist, torso and legs turn separately, legs 30°/s standing. Walk sway. Wall bump bounce. Boost exit leap on one leg. Map area 50% smaller, small buildings 60% fewer.
- Phase 1 revision 17: torso twist 180° each side. Sway 85% less (base for 10 m; scale up for taller mechs in Phase 2). Turning steps in place. Boost always takes 4 run steps; the 3 walk steps are skipped if the mech is already walking.
- Phase 1 revision 18: back to MechWarrior controls (A / D turn legs at a steady speed, legs never follow the aim, no leg reset on stop). Speed-based wall bounce. Sway 0.9°. Footstep shake 35% less. Sway and footstep shake scale with mech height.
- Phase 1 revision 19: torso twist 85° each side. All camera shake 50% less and smoothed. W stands up from a kneel.
- Phase 1 revision 20: torso twist 80°. Camera stays behind the torso (no free orbit). Lower-leg twist up to 90°. Shake 40% sharper.
- Phase 1 revision 21: mech aim jitter and overshoot removed. Torso turn 50% slower. Vertical aim 70% slower. Lower-leg twist 60°. Shake intensity 0.75.
- Phase 1 revision 23: boost stop is a skid stop. "revert 1" = set `boost_exit_style` to LEAP (the version at commit f51bd42).
- Phase 1 revision 24: skid recovery 80% shorter, skid 50% longer, shake smoothing 100, crosshair and mech aim about 1 inch above the screen center.
- Phase 1 revision 25: default camera at the right side of the head (3 m right, 4 m back). Crosshair 22% above the screen center. Torso sways forward and back after a skid before it is upright.
- Phase 1 revision 29: camera pivot above the head, camera looks down over the head. Crosshair 13.5% above the center. Same crosshair target with and without ADS.
- Phase 1 revision 30: start view about 30° down over the head (start aim pitch -19°).
- Phase 1 revision 31: start pitch -10°. Random left or right torso sway when a boost skid starts.
- Phase 1 revision 32: body turns at an angle during a boost skid and centers in the recovery.
- Phase 1 revision 33: 0.2 m camera kicks at movement starts and wall bumps. Camera kicks bounce on a spring. Inertia sway on the torso after all movements.
- Phase 1 revision 34: dodge roll on a double tap of Space.
- Phase 1 revision 35: dodge animation is a dive and barrel roll (no somersault).
- Phase 1 revision 36: dodge is a dive and shoulder roll (Gundam Battle Operation 2 style), with a ground contact solver.
- Phase 1 revision 37: dodge distance +70% (23.8 m), speed -50% (2.55 s). Small buildings 5.
- Phase 1 revision 38: dodge 50% faster (1.7 s). Spring forward out of the roll.
- Phase 1 revision 39: dodge recovery fix: smooth height plan (no pop and drop), inertia sway paused during the dodge, recovery crouch and lean with one spring back to upright.
- Phase 1 revision 40: dodge roll replaced by a directional dodge hop (11.9 m, 50% of the roll).
- Phase 1 revision 41: player mech model replaced with an RX-78-2 Gundam style placeholder (same skeleton, same animation). Beam rifle and shield. Waist skirts follow the thighs.
- Phase 1 revision 50: torso twist 20% less (52° left, 64° right). Boost dodge skid 28 m in 2.25 s. Mouse re-center of the mech aim.
- Phase 1 revision 49: re-center key for the mech aim (middle mouse or X, hold). Dodge skid 5.3 m (+200%), 32 m after a boost dodge (+500%). Forward sway after the dodge 8°.
- Phase 1 revision 48: mech aim stays 1.5° off the crosshair after a shot. Shield 20% narrower (shield-up speed 7.5 m/s). Stronger forward sway after the dodge. Bullet tracers 75% bigger.
- Phase 1 revision 47: left arm and shield poses from drawing 11 (side when down, diagonal cover when up). Rifle rest = ready to fire. 1 shot per 2 s, recoil x2, 3° aim kick per shot. Boost skid 40% longer. Double tap while boosting = forward dodge. Shield lifts 60% slower. Map area +30% (objects spread 14%, ground 206 m, walls at ±102.6 m).
- Phase 1 revision 46: dodge skid 60% shorter with two brake thrusters. Shield up top speed 6 m/s from the shield size (bigger shield = slower). Hold V for a front view of the mech.
- Phase 1 revision 45: boost after 2 walk and 2 run steps. Shield up halves the speed. Left torso twist 65°. Boost lean 21° and boost inertia sway 40% less. Walk and run sway 30% less. Warden upper body 15% smaller. Dodge ending: skid first, then 2 steps.
- Phase 1 revision 44: dodge ending = 2 run-out steps, then the boost skid. Blade antenna removed. RMB hip fire with no zoom for one-hand weapons, LMB lifts the shield. Fire rate 2 per second. Legs 20% thicker. Boost crouch hip bend 20° to 14°.
- Phase 1 revision 43: missile rack removed. Rifle 40% smaller, one-hand high ready, fires bullets with recoil (RMB). Shield 20% larger. Booster flames. Dodge hop ending animation.
- Phase 1 revision 42: RX-78-2 model saved as Granpa Gundam. New player model Warden from reference image 9, with a straight rifle barrel. Model generators moved into `tools/mech_gen/`.
- Weapon controls decided: RMB right arm, LMB left arm. Two-hand firearm: RMB aim, LMB shoot.
- Note for .tscn files: Transform3D text is row by row (basis rows, then origin).
- Phase 1: placeholder leg swing on the box mech. Phase 8 adds complete animation: walk cycles per leg type, leg IK on slopes, torso twist toward aim, weapon recoil, boost and jump jet poses.
- Phase 1: mechs pass through cars, lampposts, and people. Phase 4 makes these destructible.
