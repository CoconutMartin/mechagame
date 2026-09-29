# Mechagame Design Spec

Third-person mecha action game.
Engine: Godot 4.7 (latest stable). Language: GDScript only. Platform: PC, keyboard and mouse.
Art style: realistic. Use placeholder shapes (boxes, capsules, cylinders) until Phase 8.

## Status

| Phase | Content | Status |
|---|---|---|
| 1 | Mech controller and third-person camera on a test map | Done |
| 2 | Part resources, sockets, assembler, stat calculator, weight-to-speed formula, debug HUD | Done |
| 3 | Weapons: guns, lock-on missiles, sniper zoom, melee blade, energy use | Done |
| 4 | Per-part HP, hitboxes, destruction, target dummies, enemy AI, greybox urban map with destructible props | In progress: 4a done (part HP, hitboxes, part breaks, respawn), 4b done (enemy AI gunner). Next 4c destructible city |
| 5 | Garage screen: swap parts, add plates, live stat preview. Graphics settings menu (low, medium, high) | Not started |
| 6 | Pilot creation and skill tree | Not started |
| 7 | Save/load builds (JSON) and 4 preset archetype loadouts | Not started |
| 8 | Realistic graphics pass and complete mech animation | Not started |

## Controls

| Input | Action | Input map name |
|---|---|---|
| W / S | Walk forward / back, relative to where the torso faces (since 4a.5) | `move_forward`, `move_back` |
| A / D | Strafe left / right, relative to where the torso faces (since 4a.5; before: turn the legs, MechWarrior tank style). Strafing is 90% of the walk speed and the pelvis turns up to 60° toward the motion (`MechLegTwist`). A / D also pick the dodge side and the slide side | `move_left`, `move_right` |
| Q / E (hold, release) | Missile pods: hold to lock targets, release to fire | `fire_back_left`, `fire_back_right` |
| R | Reload guns and missile pods | `reload` |
| 1 to 4 | Test loadouts: Gunner, Sniper, Melee, Missile | `loadout_1` to `loadout_4` |
| V (toggle since 4a.3) | Front view: press V once the camera swings around to the front of the mech (about 0.33 s); press V again to go back. The mech aim stays on the torso direction and the crosshair hides | `front_view` |
| Mouse | Aim. The torso turns toward the aim at its turn speed and the camera stays behind the torso. The legs follow the torso (since 4a.5) at a steady speed (90°/s moving, 45°/s standing): moving, they always follow; standing, they start when the torso is more than 25° off and then turn all the way (steps in place). The torso stays inside its twist limits (52° left, 64° right of the legs) while the legs catch up | |
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
- Test map (cleared in 4a.10, user request): 206 x 206 m ground with walls at ±102.6 m. The player starts at the center facing north (-Z). Content: 1 tall building (18 x 40 x 18 m, 38 m left and 75 m ahead), 1 medium building (18 x 16 x 15 m, 34 m right and 60 m ahead), 1 semi truck (18 m left, 28 m ahead), 1 car (16 m right, 22 m ahead), 1 dummy mech 40 m ahead facing the player, and 1 enemy mech (4b) 90 m ahead and 12 m right. Keep spawn points inside ±100 m, or the mech falls off the ground. (Before 4a.10: 13 buildings, platforms, lampposts, 7 cars, 4 trucks, 7 people and 6 box dummies.)
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
| Boost start | Moving at 1.5 m/s or faster: Shift boosts at once (since 4a.6). From a standstill: Shift held: 2 walking steps (skipped if the mech already walked 2 steps), then 2 running steps (run speed 1.25x walk = 11.4 m/s, 12° torso lean), then boost | HUD shows "Boost ready in N steps" |
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
| Torso aim turn | 66.2°/s max since 4a.4 (+50%, Warden core 85.35°/s times the weight factor), 189°/s² acceleration | in the last 25% of each turn the torso turns at 50% speed, then stops exactly on the aim (no overshoot, no settle swings) |
| Footstep stride | 6 m at walk speed and above, down to 30% (1.8 m) near standstill | one camera shake per stride, none while boosting |

### Aim

| Value | Current |
|---|---|
| Camera crosshair | yellow dot 13.5% of the screen height above the center (matches the reference screenshot). `MechAim.screen_offset_up` |
| Mech aim reticle | blue ring, placed from the torso angle (no shake, no jitter). The camera follows the torso, so it sits on the yellow dot |
| Aim jitter | removed (0°). The code and exports stay in `MechAim` for later use |
| Vertical aim | mouse pitch speed 30% of horizontal |
| Ring while down or in an Akira slide (4b.2) | the ring stays at its neutral place (crosshair plus free aim offset) and does not follow the torso. It blends back in 0.25 s after the get-up, or when the body turn after an Akira slide is below 3°. `MechAim.neutral_amount` |
| Hit marker (4b.1) | red X where a shot from the right weapon muzzle really hits |
| Two-hand weapon in one hand (4b.2) | left arm lost: the right hand holds the weapon low at the hip, like the one-hand rifle (`WeaponController` one-hand hold). The ring is unsteady: soft spring (1.6 Hz, damping 0.3, it swings past and comes back), slow sway 0.9°, recoil x1.6 (`FreeAim.unsteady`) |
| Aim down sight (RMB) | camera moves in along the aim line (to 8 m) and zooms from FOV 65° to the weapon zoom FOV (beam sniper 52.6°), same target, mouse sensitivity 50%. Rifle butt on the right shoulder, torso turns 30° right and tilts 6°, left hand under the handguard near the muzzle |

### Current camera tuning (Phase 1)

All values are exports on `MechCameraRig` and the `SpringArm` node.

| Value | Current |
|---|---|
| Distance behind the pivot (spring length) | 8.5 m since revision 54 (above the head, FOV 65° since revision 61). The feet are below the screen edge at the start pitch. RMB (two-hand weapons) moves it to 8 m and zooms to the weapon zoom FOV |
| Shoulder offset | 3 m right (right side of the head) |
| Crosshair height | 0.3 of the screen height above the center since revision 59 (was 0.135): the view is about 12° lower (more ground and the whole mech in view), as the user drew |
| Pivot height | 11.5 m (above the head). The camera sits on the aim line behind the pivot, 3 m to the right, and tilts down by the crosshair angle (about 21° at FOV 65°, crosshair 0.3 above center), so it looks down over the head |
| Start view | camera pitch -24.5°, FOV 65° (revision 61, set by the user): aim pitch starts at -3.6° and the crosshair tilt adds about 21°. `MechCameraRig.start_pitch_deg`. The debug HUD shows the camera angle: camera pitch, aim pitch, distance and FOV |
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
| 4 | hitboxes | mech part hitboxes (`PartHitbox`) and target dummies. Weapons, the aim ray and blasts hit layers 1, 3 and 4 (mask 13), not the mech bodies on layer 2 |

## Weapon controls (Phase 3)

Phase 3 decisions (user):
- Solid guns (rifle, missiles) use ammo and reloads. Beam weapons (beam sniper, beam blade) use a heat bar: each use adds heat; at full heat the weapon overheats and works again only after it cools to zero (the heat cooldown is the "reload"). The blade lunge and the pile bunker charge also use energy. The pile bunker uses ammo (stake cartridges).
- Missiles: hold Q (left pod) or E (right pod) to lock targets inside the lock box around the blue ring (one after another, up to the FCS max locks and the missiles left). Release to fire one missile per lock; no lock = one missile straight at the aim point.
- Pile bunker (revision 62, replaces the beam blade in the melee loadout): RMB = power up, then shield charge and punch. Since 4a.5: hold RMB to power up the stake (1.5 s to full, 30 energy per second, the fist pulls back to a guard, the stake cocks 0.8 m back into the housing, the drum and nose ring glow orange, a light camera shake); release RMB, or run out of energy, to attack. Damage, push-back, spark and shake scale from 50% (no power) to 100% (full power). The attack goes for the blue ring (since 4a.8): the mech aim point is locked when RMB is released; the charge goes toward it and stops 7 m short (flat distance, at most 16 m, 32 m/s); the punch goes along the line from the right shoulder to that point (fist 4.9 m from the shoulder, inside 60° of straight ahead) and the contact ray follows that line, so the stake hits the ring point. Before 4a.8 it went toward the nearest target in the aim cone (or 16 m along the aim, 32 m/s, 20 energy) with the shield up, like Captain America. Since revision 65 the charge is a simple boosted glide forward: the legs take no steps and hold the boost stance (low crouch, legs trail back), no footsteps. Since revision 66 the torso also copies the ground boost lean (21° forward, `TorsoPose`). The 2-leap version (revision 64) was removed. The lunge moves the mech, so the raised shield does not slow it down. The torso turns 30° right during the charge so the left shoulder (shield) leads. At the end of the charge the torso twists further (50°) and the right fist pulls back (0.18 s), then punches forward while the torso twists to 30° left (0.12 s). When the pile bunker nose touches something (a ray along the stake, 1.5 m past the nose), the stake (the "needle") shoots out 3.5 m in 0.05 s: 900 damage, big spark, heavy screen shake and aim kick, and the mech is pushed back at 7 m/s. No contact = no shot, no ammo used (status MISS). 3 stakes, 5 s reload, 1 punch every 3 s (hit or miss, revision 63). The stop point is 8 m in front of the target. `PileBunkerWeapon`, model `scenes/weapons/pile_bunker.tscn`. Since revision 63 the model is fixed to the right forearm like the shield on the left: its `Mount` node moves onto `ElbowR` (outer side, drum on top, clamps around the forearm) and the weapon root is only the fist target for the arm IK. The stake fires along the forearm.
- Beam blade (kept in data, not in a test loadout since revision 62): rest = upright in the right hand in front of the shoulder (reference image 12). RMB = charge slash: the mech charges toward the target in the aim cone (or 16 m along the aim) with the shield up and the blade lifted overhead, then swings the blade straight down, fast (0.18 s). The torso twists: left shoulder leads during the dash (45°), then the right shoulder comes forward during the down swing (35°), and the torso returns to center in the recovery (`TorsoPose.action_twist_deg`). The pauldrons turn with the raised arm (`PauldronFollow`: 55% of the arm angle past 35° from hanging down, up to 65°), so they lift when the blade goes overhead and come down with the swing.
- Only one weapon works at a time (the first pressed stays active until it is done). Melee weapons (pile bunker, blade) are the exception. The two missile pods count as one weapon: Q and E work together (free fire and locked fire), and each pod locks its own targets.
- A missile volley at locked targets entrenches the mech (it stops and crouches during the volley and 0.6 s after). A free shot (quick press, no lock) does not.
- Missile pods reload one missile at a time (1.5 s each), so they can lock and fire with the missiles they have.
- Beam sniper: hold LMB to charge (3 s to full), release to fire. The shot is a sustained beam (like a kamehameha): 2 s at full charge (shorter for a partial charge, at least 0.15 s). It follows the aim and hits every 0.1 s with a small kick and shake. The torso and shoulders shake while it fires (`TorsoPose.action_shake`). The torso and shoulder shake while the beam fires is 40% less since revision 66 (`torso_shake` 0.6, about 0.5° at full charge). The shake when the charge is released is small: `release_shake` 0.075 (50% less in revision 64, then 85% less in revision 65). The barrel lights up with the charge (`ChargeGlow`): the 3 coils light one after another from the back, then the flat emitter lens in the barrel face and a small muzzle light; fully lit at full charge and while the beam fires, then it fades. Since revision 63 all shake while it fires (screen, aim, torso) is 30% less (`BeamRifleWeapon.discharge_shake` 0.7, torso about 0.84° at full charge). Rate of fire: 1 shot per 2.5 s. A tap is a 25% shot. Damage, beam width, screen shake and aim jitter grow with the charge. While charging, the camera shakes a little (trauma 0.08 at the start to 0.22 at full charge, `CameraShake.hold_shake`). RMB zooms to FOV 52.6° (70% less zoom than before) at 8 m behind the pivot, so the head, weapon arm and gun stay in view (no scope overlay).
- Keys 1 to 4 switch test loadouts (until the garage in Phase 5): 1 Gunner (heavy rifle + shield), 2 Sniper (beam sniper, two hands), 3 Melee (pile bunker + shield), 4 Missile (heavy rifle + shield + two missile pods).

Weapons:
| Weapon | Slot | Keys | Values |
|---|---|---|---|
| Heavy rifle | right arm, one hand | RMB hip fire | 0.5 shots/s, 12 rounds, reload 3.5 s (R reloads early), bullets 400 m/s, recoil 2° up |
| Beam sniper | right arm, two hands | RMB zoom (FOV 52.6°), hold LMB charge (3 s), release fire | 1 shot per 2.5 s, instant beam 1500 m, heat 34/shot, cooling 10/s, overheated cooling 25/s (overheats on the 4th fast shot, about 4 s to recover), recoil 3.5° up |
| Pile bunker | right forearm | RMB shield charge + punch, the stake fires on contact | 1 punch per 3 s, charge 16 m at 32 m/s (boosted glide), 20 energy, 900 damage, 3 stakes, reload 5 s, push back 7 m/s |
| Beam blade (not in a loadout) | right arm | RMB charge slash (shield up, blade overhead, down swing) | lunge 16 m at 32 m/s, 20 energy, slash reach 11 m, heat 30/slash |
| Missile pod L / R | back | hold Q / E lock, release fire | 4 missiles, one reloaded every 1.5 s, terminal guidance near the target (up to 4x turn), lock box 7°, 0.5 s per lock (head lock-on speed), missiles 90 m/s, turn 110°/s |
| Hex shield | left arm | LMB lift | 10.9 m², 3 t |

- One-hand weapons: RMB uses the right arm weapon, LMB uses the left arm weapon.
- Two-hand firearm: RMB aims down sight, LMB shoots.
- Now (revision 47): the Warden rifle is a one-hand weapon. Hold RMB: hip fire, 1 shot every 2 seconds, no zoom (one-hand weapons never zoom). Free aim with a dead zone (revision 55, `FreeAim` under the camera rig): the mouse moves the mech aim (blue ring) inside a box around the camera crosshair (±4° left and right, ±3° up and down since revision 56). Only the mouse movement past the box edge turns the camera (and the torso target). Each shot kicks the ring 2° up and up to 1° to the side (muzzle climb), inside the box; the camera does not move. Smooth since revision 56: the kick rises in about 0.1 s, the ring follows the mouse and kicks at 14/s, and each shot adds 0.9° of jitter (noise, fades at 1°/s, up to 1.2°). Recoil and jitter x0.3 while kneeling, x1.6 with the shield up (revision 57, both blend with the kneel and shield amounts). While the boosters fire (boost, air boost, jump jets, dodge hop) the aim shakes up to 0.7° with the booster thrust (revision 58, `FreeAim.booster_jitter_deg`). The player pulls the ring back onto the target. No automatic return. Moves in other directions move both together. Camera shake per shot: trauma 0.052, kick 0.078 (30% more since revision 51). Hold LMB: the shield on the left arm lifts in front of the chest. Two-hand weapons keep the ADS zoom on RMB.
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
  - The mech aim turns with the whole body during slides (skid drift and Akira slide): `MechAim.get_body_turn()` adds the `Visual` turn. The blue ring moves off the crosshair and comes back with the body (revision 54).
  - Akira slide (revision 52): every slide ends with it (the dodge slide and the boost stop skid), except the slides after back, left and right dodges (revisions 61 and 63): only the forward dodge (and the dodge from a boost) and the boost stop end with it. Swing side: A = left, D = right when held, otherwise random. The recovery (turn back) is 40% slower: `SkidBodyTurn.akira_recover_speed` 1.2, `DodgeSlidePose.blend_out_speed` 1.2.
  - Bullet hits (revision 52): sparks, a dust puff and a light (`ImpactSpark`), and a 1.4 m dark bullet mark decal (`BulletMark`, stays 20 s, fades in 3 s, at most 60).
  - Dodge slide (revision 51, `DodgeSlidePose`): the mech slides in a deep crouch (front leg hip 40° knee 75°, back leg knee 85°, body 1.5 m lower). Akira slide end (`SkidBodyTurn`): from 50% to 90% of the slide the whole body swings until the legs are at 19° to the slide (revision 57: 65% less than 55°), and leans 2.8° back against the motion (the `Visual/Roll` node). The lead leg braces out 12° to the side, the other leg folds (knee 80°). The pose holds 0.4 s after the slide, then turns back during the steps.
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
- One leg destroyed: speed drops 60% (jump jets still work since 4a.7); both legs destroyed: the mech falls and dies
- Back unit destroyed: that weapon is lost
- Core destroyed: mech is destroyed

Phase 4a (user choices: parts fall off, respawn), revised in 4a.2 (user rules):
- Hit keys (`MechHealth`): Head, Torso C, Torso L, Torso R, Arm L, Arm R, Groin, Leg L, Leg R, Shield, Back L, Back R. The core part HP is split: center torso 60%, each side torso 40% (Warden: 960 / 640 / 640). The legs part HP is split: groin 40%, each leg 60% (560 / 840 / 840). Core meshes more than 0.9 m from the middle are side torso; leg meshes on HipL/KneeL are the left leg, on HipR/KneeR the right leg, on Lower the groin. The generator and FCS count as center torso. The booster (backpack) has its own HP (Warden 200) since 4a.3. Hits on the held weapon damage the arm that holds it.
- Alive while the head, the center torso, the groin and at least one leg are intact.
- Hitboxes: box `PartHitbox` bodies (layer 4) built from the part models: one box per container node (pauldron pivot, shield, weapon, pod, pile bunker mount) and one per socket and key for loose meshes. They move with the parts.
- Below 50% HP a part smokes (`DamageSmoke`).
- `PartBreaker` (part effects):
  - Arm destroyed: falls off (no explosion) with its weapon or shield.
  - Side torso destroyed: its armor is blown away (small explosion, smoke), its arm and the back unit on that side fall off (no explosion). The mech lives.
  - Leg destroyed: explodes at the knee, the armor is gone and the inner frame shows (thigh and shin frames, struts, foot frame, joints). One leg left: walk 60% slower with short limping steps (stride x0.4), boost speed stays the same, and the jump jets still work (since 4a.7; upward boost on one leg). When the boost stops the mech falls over (forward, leaning to the broken leg), slides, lies 1.5 s and gets up (1.5 s). After a full boost (85% of boost speed or more) it rolls over once along its length (180°/s, 75% slower than 720°/s), face down at the end (4a.3: was twice).
  - Shield, back unit destroyed: falls off.
  - Booster (backpack) destroyed (4a.3): it explodes, no more boost, flames off. The fuel blast does 20% of the mech's total max HP, split evenly over the center, left and right torso (`PartBreaker.fuel_damage` 0.2; Warden 7480 HP = 1496, about 499 per torso part). Before 4b.1: 5% of max energy (5 HP).
- Falls (4a.3, `MechFall` + `FallPose`):
  - Direction: the way the mech moves, or its front when it stands still (slower than 1.5 m/s).
  - One leg left, the mech falls over: when a ground boost stops (since 4a.7: no roll and no turn; it lies where it fell, and gets up from that pose as soon as the slide ends); after a dodge hop (in the hop direction); when it lands after the leg broke in the air, and (since 4a.8) after any landing from the air at 2 m/s or more down: these landing falls go toward the broken leg's side; when a pile bunker punch hits nothing (the moment the arm is fully out); when the leg breaks during a pile bunker attack (the attack stops).
  - Both legs broken in the air: the mech falls over when it lands, the way it moves, or backwards with no speed. A fall to the back crushes the backpack (it explodes); a fall to the front crushes the head.
  - Every fall damages every part by 5% of its max HP when the body hits the ground.
  - No boost while down. (A 1 s boost lock after the get-up was added in 4a.8 and removed in 4a.9.)
  - Boost with the legs: see Boost start (moving = boost at once since 4a.6).
  - Motion: a topple like a falling pole (1 s, slow then fast), a 4° bounce at impact, the body scrapes to a stop (14 m/s² extra, 2 m/s² while rolling; the Mech slide slowdown is 3 m/s²), rolls at 180°/s.
  - Camera (4a.5): while the mech is down (fallen or destroyed) the camera follows the mouse only (free look) and does not turn with the mech. After the get-up the torso turns back to the camera aim at its turn speed and the legs follow; the camera goes back behind the torso when the torso is within 3° of the aim.
  - Sequence after the impact (4a.6, all other falls of a living mech): the body rests 0.4 s, then rolls along its body until it is face down (after the full-boost roll if there is one). The roll starts and ends slowly (eased, average 180°/s, at least 0.9 s), and the body rides higher on its side (+1.4 m, wide shoulders) and on its back (+0.6 m, backpack) so it stays on top of the ground. Face down, the hands slide under the shoulders, the knees start to bend and the chest lifts 4° (0.8 s). Then the get-up. A front fall lies 0.8 s before this step. The mech then faces its head direction, so every get-up is a front get-up (4a.4).
  - Arms (living mech, 4a.4, `FallPose` with two-bone IK to world points): the knees buckle; as the body passes about 15° the hands reach for the ground ahead of the fall, a little wider than the shoulders (side fall: the arm on that side reaches out and the other arm comes in to the chest; back fall: both hands reach back for the ground). At impact the hands stay where they touched and the elbows bend as the chest comes down. During a roll the hands fold in front of the chest. Lying face down the hands are flat beside the chest, elbows back. Get up (2.4 s): the hands stay on the ground and the arms push the body up, one knee comes under the body, then the hands leave the ground and go back to the sides as the mech stands. The held weapon hangs from the right hand while down.
  - Legs: knees buckle in the fall, straight while lying and rolling, kneel then stand in the get-up.
- `MechDeath` (death, then `PowerDownPose`: legs crouched with hips 35° and knees 70°, torso sags 10°, blends in 1 s; limp arms since 4a.4: the hands hang toward the ground with gravity on a soft spring (1.1 Hz, damping 0.35, so they swing a little when the body moves or falls), elbows a little bent and pointing back, and a hand that would go into the ground rests on it; the held weapon drops from the hand to the ground):
  - Head destroyed: the head falls off, power down, standing.
  - Center torso destroyed, both side torsos above 50%: power down, standing.
  - Center torso destroyed, one side torso at or below 50% (or already gone): the center and that side explode (head, that arm and back unit fly off). The mech takes two steps toward the side that is left and falls over diagonally (forward and to that side).
  - Center torso destroyed, both side torsos at or below 50%: the whole upper body is blown off. The legs stay standing in power down.
  - Groin destroyed: the upper body comes off the legs as one piece, falls, and explodes 1.5 s later. The legs stay standing in power down.
  - Both legs destroyed: the mech falls forward and lands on its head, which is crushed (the head is on top at the front, so it hits first).
- `MechFall`: tips the Visual node over a foot edge (0.9 s, speeding up), with optional side steps, rolls and get-up. The Mech body slides to a stop (`Mech.fallen_slide_deceleration` 6 m/s²).
- Weapon damage: rifle bullet = weapon damage (120), beam = ticks, pile bunker 900, missiles = `Blast` (radius 8 m, full damage at the center to 30% at the edge, by distance to the nearest box; each body once). A mech's own weapons and aim skip its own hitboxes (`Mech.get_hit_exclude()`).
- Player death: `PlayerRespawner` rebuilds the mech 3 s after death, at the start point with full HP and the same loadout (`LoadoutSwitcher.rebuild()`).
- Target dummies: 3000 HP with a label above them, explode at 0 HP and come back after 6 s.
- Dummy mech (4a.10, `DummyMech` in the test map): a real mech built from the current player mech scene and the gunner loadout, standing still with no pilot (no input, no camera), facing the player. It has the full part damage (hitboxes, breaking parts, falls, death), missiles can lock it (`Mech.get_lock_point`, 7.5 m up), and a label above its head shows the HP of each part. It is built again 6 s after it dies.
- Enemy AI (4b, user choice "simple gunner"): `MechSpawner` (was `DummyMech`) builds a mech with `pilot` NONE (dummy) or AI. `AIPilot` disables `MechInput` and fills the same input values, so the enemy uses the same movement, boost, dodge, shield and weapon rules as the player. It targets the nearest living mech in group "player" (the player mech, set by `LoadoutSwitcher`). It needs a clear line of sight (ray on layer 1) for 0.8 s before it acts. It walks in when farther than 80 m (boosts past 130 m), backs off when nearer than 40 m, and strafes left or right between (side changes every 2 to 4.5 s). It fires when the target is within 180 m and its torso is within 6° of it; the aim point wanders up to 2.2 m around the target lock point (`MechAim.use_ai_target`). It lifts the shield now and then (0.12 per second, more when the center torso is hurt, 1.6 s) and does a dodge hop now and then (0.06 per second). Enemy missile pods skip their own mech. The enemy label is red. When the player respawns (`PlayerRespawner.respawned`), all spawners build their mech again with full HP.
- Test keys (`DebugDamage`): F1 head, F2 center torso, F3 left torso, F4 right torso, F5 left arm, F6 right arm, F7 groin, F8 left leg, F9 right leg, F10 shield, F11 back units, F12 booster. Each press takes 30% of max HP; Shift + key destroys the part at once.
- Debug HUD: current / max HP of each part, DESTROYED, MECH DESTROYED.

## Archetypes (preset loadouts; player can mix any parts)

- Melee: light, fast, blade arms, strong boost
- Gunner: medium weight, rifles and machine guns
- Missile: heavy back units, multi-lock FCS
- Sniper: long-range rifle, high-zoom head, slow

## Pilot

Name, callsign, portrait, skill tree.
Skills give passive bonuses (example: faster lock-on, less recoil, more boost energy).
One active skill slot (example: Overdrive, +30% speed for 8 seconds).

## Part system (Phase 2)

- Data classes (`scripts/data/`): `PartData` (name, weight, HP, model scene) with `HeadPart`, `CorePart`, `ArmPart`, `LegPart` (leg type, load capacity, base speed, jump, leg turn speeds), `BackUnitPart`, `BoosterPart` (thrust, boost speed multiplier, energy use), `GeneratorPart` (energy output, recharge delay), `FcsPart`, `WeaponData`. Also `PlateData` (slot, HP, weight), `ModData` (stat, percent) and `Loadout` (all parts, weapons, plates, mods).
- Data files: `data/parts/warden/`, `data/weapons/`, `data/plates/`, `data/mods/`, `data/loadouts/warden.tres`.
- Sockets: the frame nodes in the mech scene (Torso, ShoulderL/R, ElbowL/R, Lower, HipL/R, KneeL/R). A part scene has one child group per socket, named like the socket. `MechAssembler` (first node after the collision) moves each group's children onto the socket when the mech starts, then runs `StatCalculator.compute()` and `MechStatApplier.apply()`.
- Logic nodes find part nodes by group: `booster_flame`, `booster_light` (BoosterFlames), `brake_flame` (BrakeThrusters), `foot` (SkidDust).
- `StatCalculator.weight_factor(load_ratio)` holds the weight formula. Walk speed = legs base speed x factor. Boost acceleration = booster thrust / total weight. Torso and leg turn speeds x factor. Energy from the core (capacity) and generator (output, delay). Recoil from the right arm. Part HP = part HP + plates in its slot. Mods change these by percent.
- Warden parts (60 t total): head 4 t / 400 HP, core 18 t / 1600 HP, arms 5 t / 600 HP each, legs 16 t / 1400 HP (load capacity 80 t, base speed 11.742 m/s), booster 3 t (thrust 1200), generator 3 t, FCS 1 t, heavy rifle 2 t, hex shield 3 t. Load ratio 0.75, factor 0.775, walk 9.1 m/s, boost acceleration 20: the same feel as Phase 1.
- Weapons (rifle, shield) stay in the mech scene until Phase 3 makes them parts. Their weight counts already.
- Mech height stays 10 m (one frame). It will come from the frame or the parts when other frames exist.
- Debug HUD build panel: total weight / load capacity, load ratio, walk and boost speed, boost acceleration, turn speeds, jump, HP of each part.

## Weapon system (Phase 3)

- `WeaponData` (`scripts/data/weapon_data.gd`): kind (gun, beam rifle, blade, missile pod, shield, pile bunker), slot (arm, back), two-handed, firing, recoil, ammo, heat, lock-on, blade and pose values. The pose values (rest transform, aim anchor, elbow directions, torso twist, zoom FOV) are for the Warden frame and come from `tools/mech_gen/warden_weapons.py`.
- Weapon models are scenes whose root has a `MechWeapon` script: `GunWeapon`, `BeamRifleWeapon`, `BladeWeapon`, `PileBunkerWeapon`, `MissilePodWeapon`. `MechWeapon.is_melee()` marks the melee weapons. The shield is a socket-group scene (`scenes/weapons/warden_shield.tscn`).
- `WeaponController` (mech node): MechAssembler calls `mount()`. It adds the weapons from the loadout under the torso, wires WeaponPose, the arm IK targets, WeaponRecoil, CameraAds (zoom only for two-hand weapons with a zoom FOV), TorsoPose (aim twist), and the shield nodes (MechShield, ShieldPose, ShieldMount are off without a shield). Each physics frame it sends the buttons to the weapons.
- Effects: `Missile` (homing, explodes on contact or near the target), `Explosion`, `BeamShot`, bullet `ImpactSpark` and `BulletMark`. Hits call `on_hit(damage)` on the target (Phase 4 adds HP).
- `TargetDummy` (`scenes/world/target_dummy.tscn`): lockable (group "lockable"), flashes on hits. Six in the test map (two on raised platforms). Not in the test map since 4a.10 (the dummy mech replaces them).
- HUD: weapon panel at the bottom right (ammo, reload, heat, overheat, charge, lock count), lock box and target brackets.
- The aim ray (MechAim) hits layer 2 too (mechs and dummies, not the own mech), so shots land on the dummy under the blue ring. Before, the ray passed through the dummy to the ground behind it and the shots from the lower muzzle landed low.
- Target dummy collision: three boxes (legs, body, head) that match its mesh.
- `LoadoutSwitcher` (test map): keys 1 to 4 rebuild the player mech with another loadout; the HUD follows it (`DebugHud.set_mech`).
- Mech: `start_lunge()` (blade), boosters fire during the lunge. MechStats has the FCS lock range and max locks and the head lock-on speed.
- Granpa Gundam still uses the older hard-wired rifle nodes (WeaponFire).

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
data/               Part, weapon, mod, plate and loadout resources (.tres): parts/warden, weapons, plates, mods, loadouts.
materials/          Shared materials. warden/ and rx78/ hold the mech colors.
shaders/            greybox_grid.gdshader (1 m and 10 m grid lines).
scenes/levels/      test_map.tscn (main scene).
scenes/parts/warden/ Warden part models (head, core, arm_l, arm_r, legs, booster).
scenes/mech/        player_mech.tscn (Warden frame, weapons and logic), granpa_gundam.tscn (saved RX-78-2 style model).
tools/mech_gen/     Python generators for the mech models and rifles (Godot ignores this folder).
scenes/props/       greybox_block, car, lamppost, person, box_truck (8 m), semi_truck (16.5 m).
scenes/ui/          debug_hud.tscn.
scripts/data/       Part, plate, mod, loadout resource classes, mech_stats.gd, stat_calculator.gd.
scripts/mech/       mech.gd (movement), mech_shield.gd (shield lift and speed limit), mech_assembler.gd, mech_stat_applier.gd, mech_input.gd (player input), mech_energy.gd, mech_footsteps.gd,
                    mech_jump_charge.gd, mech_air_steer.gd, mech_landing_recovery.gd, mech_aim.gd (camera target and real mech aim with jitter).
scripts/animation/  shield_pose.gd, shield_mount.gd, dodge_slide_pose.gd, mech_leg_swing.gd, mech_leg_twist.gd, two_bone_ik.gd, weapon_pose.gd, torso_pose.gd,
                    inertia_sway.gd, skid_body_turn.gd, skirt_follow.gd (placeholder animation).
scripts/weapons/    weapon_controller.gd, mech_weapon.gd, gun_weapon.gd, beam_rifle_weapon.gd, blade_weapon.gd, pile_bunker_weapon.gd, missile_pod_weapon.gd, missile.gd, bullet.gd, weapon_recoil.gd, weapon_fire.gd (Granpa Gundam only). Scenes: scenes/weapons/bullet.tscn, scenes/effects/impact_spark.tscn.
scenes/weapons/     heavy_rifle.tscn (Warden), beam_rifle.tscn (Granpa Gundam), long_rifle.tscn (old box rifle). Markers: GripRight, GripLeft, GripLeftRest, GripLeftAim, Muzzle.
scripts/camera/     mech_camera_rig.gd (follow and mouse look), free_aim.gd (free aim box), aim_spring.gd (aim overshoot), camera_shake.gd, camera_ads.gd (aim down sight zoom).
scripts/world/      greybox_block.gd (box with collision, set size in Inspector), mech_spawner.gd (dummy and enemy mechs).
scripts/ui/         debug_hud.gd, aim_reticle.gd.
scripts/effects/    skid_dust.gd (dust while skidding), brake_thrusters.gd, booster_flames.gd, muzzle_flash.gd, impact_spark.gd.
scripts/ai/         ai_pilot.gd (Phase 4b).
scripts/core/       mouse_capture.gd, group_nodes.gd, loadout_switcher.gd, player_respawner.gd, debug_damage.gd.
scripts/combat/     mech_health.gd, part_hitbox.gd, part_breaker.gd, mech_death.gd, blast.gd (Phase 4). Animation: power_down_pose.gd, mech_fall.gd.
```

### Phase 1 structure

- `Mech` (CharacterBody3D) does physics movement only. It reads intent from `MechInput`.
- `MechInput` reads keyboard and mouse. `AIPilot` (Phase 4b) disables it and fills the same values.
- `MechEnergy` stores energy. Boost uses it now. Weapons use it in Phase 3.
- Mech visual tree: `Visual > Upper` (torso, head, arms, rifle) `> Lower` (pelvis, legs). Upper faces the aim. Lower twists toward the move direction.
- `MechLegSwing` is placeholder walk animation: hip swing, knee bend, body bob, and sway. Legs trail back while boosting and bend in the air. It reads the walk cycle from `MechFootsteps`, so each foot strike matches a footstep shake.
- `MechFootsteps` emits a `footstep` signal per stride. `CameraShake` listens to it and to `Mech.landed`.
- `MechCameraRig` is `top_level`, so it does not rotate with the mech. The mech body turns toward the camera yaw.
- Physics interpolation is on, so movement is smooth on high refresh rate monitors.
- Physics engine: Jolt.

## Reminders for the user

- No open reminders. (Closed: "update the dodge hop animation", the user accepted the current hop at the start of Phase 3.)

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
- Phase 3 revision 59: aim ray hits dummies (shots land on the blue ring), dummy collision fixed. Beam sniper charge shot (hold and release LMB), no scope overlay. Missiles: terminal guidance (close targets hit), one-at-a-time reload, lock with partial ammo, entrench on a locked volley. One weapon at a time (not the blade). Blade upright rest pose and charge slash (shield up, overhead, down swing). Camera view 12° lower (crosshair 0.3 above center).
- Phase 3 revision 60: beam sniper zoom 70% less (FOV 52.6°, ADS 8 m back) and a 2 s sustained beam for a full charge. Blade dash with the left shoulder leading, torso twist to the right shoulder on the down swing. Both missile pods work at the same time. Start pitch +6° (camera about 17° down, as in the user's image). Camera angle line in the debug HUD.
- Phase 3 revision 61: torso and shoulder shake during the charged beam. Pauldrons turn with the raised arm (pivot at each shoulder). Beam sniper 1 shot per 2.5 s. No Akira slide after a back dodge (the side and forward dodges and the boost stop keep it). Start camera pitch -24.5°, FOV 65°.
- Phase 3 revision 62: small camera shake while the beam sniper charges. Pile bunker replaces the beam blade in the melee loadout (shield charge with the torso turned 30°, twist and wind-up, punch, stake fires on contact).
- Phase 3 revision 63: beam discharge shake 30% less. Pile bunker fixed to the right forearm like a shield, 1 punch every 3 s. No Akira slide after left and right dodges.
- Phase 3 revision 64: pile bunker charge as 2 big leaps (boosters on). Beam sniper release shake 50% less, barrel coils and lens light up with the charge.
- Phase 3 revision 65: pile bunker charge is a simple boosted glide (leaps removed, legs hold the boost stance). Beam sniper release shake 85% less.
- Phase 3 revision 66: pile bunker charge copies the boost pose (torso lean too). Beam sniper torso shake while firing 40% less.
- Phase 4a: per-part HP and hitboxes, damage from all weapons, parts fall off (debris, smoke), legs slow, core destroyed = wreck, respawn after 3 s. Dummies with HP. Test keys F1 to F8.
- Phase 4a.2: torso split (center, left, right) and legs split (groin, left, right). New death rules (head, center torso, groin, both legs) with power down pose, explosions, side steps and falls. One leg: exploded leg with the inner frame, limp, falls after a boost (rolls twice after a full boost), gets up. Test keys F1 to F11.
- Phase 4a.3: 1 roll after a full boost. One-leg falls after a dodge, after landing, and on a pile bunker miss or leg loss during an attack. Both legs lost in the air: fall on landing (backwards with no speed). Booster HP (no boost, fuel blast). Fall damage 5%. Fall direction from motion. Arms break the fall, standby during the roll, staged get-up. V toggles the front view. Test key F12.
- Phase 4a.4: fall arms with IK (reach for the ground, hands planted at impact, folded in the roll, push-up get-up). Roll face down after every fall before getting up. Limp dead arms (gravity spring, rest on the ground), the weapon drops. Leg and torso turn speeds +50% (Warden legs 116.1°/s moving, 58.05°/s standing; torso 85.35°/s).
- Phase 4a.5: A / D strafe (movement relative to the torso), the legs follow the torso. Camera free look while the mech is down; after the get-up the mech turns back to the camera. Pile bunker: hold RMB to power up (energy), release or run out of energy to attack, power scales the hit.
- Phase 4a.6: smoother fall to stand (rest, eased roll riding on the shoulders, hands under the shoulders, knee bend blends in, push up, rise). Boost starts at once when the mech moves (1.5 m/s or faster).
- Phase 4a.7: the one-leg boost fall has no roll and no turn; the mech gets up as soon as the slide ends. Jump jets work on one leg.
- Phase 4a.8: one leg: every landing from the air ends in a fall toward the broken leg. The pile bunker charge and punch go for the blue ring (locked at release); the stake hits the ring point.
- Phase 4a.9: boost lock after the get-up removed. Shots aim at what the camera sees under the blue ring (`MechAim.get_ring_screen_point`, a camera ray through the ring), so bullets land on the ring on dummies and target edges too (before: a ray from the torso, which missed thin targets such as the dummy head when the ring was off the crosshair). If the ring is over empty space just past a target, the line of fire from the muzzle (lower than the camera) can still hit that target.
- Phase 4a.10: test map cleared: 1 tall and 1 medium building, 1 truck, 1 car, and a dummy mech (the current mech with no pilot, full part damage, HP label, respawns after 6 s).
- Phase 4b: enemy AI (simple gunner): keeps 40 to 80 m, strafes, fires the rifle with aim error, lifts the shield and dodges now and then. Same mech and rules as the player. Enemies reset when the player respawns.
- Phase 4b.1: booster fuel blast = 20% of total max HP over the torso. Hit marker (red X): where a shot from the right weapon muzzle really hits.
- Phase 4b.2: fixed the error after a pauldron fell off (a freed node was read, 20 s after the arm dropped) and the GDScript warnings. A two-hand weapon is held in one hand when the left arm is lost, with an unsteady ring. The ring stays neutral while the mech is down and during the Akira slide.
- Phase 3: weapons from the loadout (WeaponController, MechWeapon scripts): heavy rifle (ammo), beam sniper (heat, zoom and scope), beam blade (lunge slash, heat and energy), missile pods (hold to lock, release to fire, ammo), hex shield. Target dummies, weapon HUD, lock HUD, test loadouts on keys 1 to 4. Dodge hop reminder closed.
- Phase 2: part resources, loadout, part scenes on sockets, MechAssembler, StatCalculator with the weight formula, build panel in the debug HUD. Warden split into 6 part models. Tuned to keep the Phase 1 feel (60 t, walk 9.1 m/s).
- Phase 1 revision 58: aim shake while the boosters fire (0.7° at full thrust).
- Phase 1 revision 57: Akira swing 65% smaller (19°, lean 2.8°). Recoil and jitter 70% less kneeling, 60% more with the shield up.
- Phase 1 revision 56: free aim smoothing and recoil jitter. Box ±4° x ±3°. Recoil 2° up, up to 1° side.
- Phase 1 revision 55: targeting option 1 chosen: free aim with a dead zone (box 6° x 4°), recoil kicks the ring up, the player corrects it 1:1. The kick-line re-align is removed.
- Phase 1 revision 54: mech aim follows the body turn in slides. Camera 8.5 m, above the head, FOV 70°.
- Phase 1 revision 53: camera zoom undone (10.3 m, pivot 11.5 m, FOV 70°). Akira slide milder (55°, lean 8°). Mech aim re-align can overshoot the crosshair; the player lines them up along the kick line.
- Phase 1 revision 52: Akira slide at the end of the boost stop too, side from A / D or random, recovery 40% slower. Shot kick 3°, re-align rate 0.1. Bullet impacts with dust and bullet marks. Camera 25% closer (7.7 m), pivot 7.8 m, FOV 74°. Debug HUD text updated and moved off the bottom of the screen.
- Phase 1 revision 51: dodge slide in a deep crouch with an Akira slide end. Shot kick 2°, re-align by moving the mouse opposite to the kick (half rate). Re-center key removed. Shot camera shake +30%.
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
