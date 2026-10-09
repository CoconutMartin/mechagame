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
| 4 | Per-part HP, hitboxes, destruction, target dummies, enemy AI, greybox urban map with destructible props | Done: 4a (part HP, hitboxes, part breaks, respawn), 4b (enemy AI gunner), 4c (destructible buildings and props) |
| 5 | Garage screen: swap parts, add plates, live stat preview. Graphics settings menu (low, medium, high) | Done |
| 6 | Pilot creation and skill tree | Skipped for now (user request, after Phase 5) |
| 7 | Save/load builds (JSON) and 4 preset archetype loadouts | Skipped for now (user request, after Phase 5) |
| 8 | Realistic graphics pass and complete mech animation | Done: 8a graphics (materials, CC0 textures), 8b animation (hit reactions, foot planting, idle motion, turn steps) |
| Urban | Urban map (replaces the Phase 4 test map): layout, buildings from data, props, textures, lighting; then destruction | Checkpoint 1 done (layout, textures, props, no building destruction yet). Checkpoint 2 (destruction) next |

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
| Camera crosshair | hidden since 4c (user request, `AimReticle.show_crosshair`); yellow dot 13.5% of the screen height above the center (matches the reference screenshot). `MechAim.screen_offset_up` |
| Mech aim reticle | blue ring, placed from the torso angle (no shake, no jitter). The camera follows the torso, so it sits on the yellow dot |
| Aim jitter | removed (0°). The code and exports stay in `MechAim` for later use |
| Vertical aim | mouse pitch speed 30% of horizontal |
| Ring while down or in an Akira slide (4b.2) | the ring stays at its neutral place (crosshair plus free aim offset) and does not follow the torso. It blends back in 0.25 s after the get-up, or when the body turn after an Akira slide is below 3°. `MechAim.neutral_amount` |
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
| Start view | camera pitch -24°, FOV 65° (4c, set by the user; -24.5° in revision 61): aim pitch starts at -3.1° and the crosshair tilt adds about 21°. `MechCameraRig.start_pitch_deg`. The debug HUD shows the camera angle: camera pitch, aim pitch, distance and FOV |
| Same target in ADS | the camera stays on the aim line and its tilt follows the FOV, so the crosshair points at the same spot with and without RMB |
| Tilt limits | 27.5° down, 15° up |
| Boost shake | steady shake while boosting (trauma 0.4) |
| Air shake | steady shake in the air: rising 0.44, falling 0.28 (50% less than before). Aim jitter moves only the blue ring |
| Aim spring | 1.75 Hz, damping 1.0 (no overshoot) |
| Max aim lag | 25° |
| Mech size | pivot height, distance (normal and ADS), shoulder offset and kneel drop scale with the mech's shoulder height (ShoulderL above the feet, from the parts' MechFrame) over 7.865 m (the OG layout), limits 0.6 to 2.0 (`MechCameraRig.scale_with_mech`, `reference_shoulder_height`). Warden 1.0 (unchanged), Recon Sheet 1.07, Medium 1.44 (pivot 16.6 m, distance 12.3 m, offset 4.3 m) |

### Collision layers

| Layer | Name | Used by |
|---|---|---|
| 1 | world | ground, buildings, platforms, building blocks (4c) |
| 2 | mechs | mech bodies |
| 3 | props | cars, trucks, lampposts, people. Mech bodies pass through them; a contact area on each `DestructibleProp` finds mechs (4c). Debris, rubble and wrecks have no layer (mask 1) |
| 4 | hitboxes | mech part hitboxes (`PartHitbox`) and target dummies. Weapons, the aim ray and blasts hit layers 1, 3 and 4 (mask 13), not the mech bodies on layer 2 |

## Urban map (urban_small, replaces the Phase 4 test map)

User brief: `urban_environment_agent_prompt.md` (two checkpoints; Checkpoint 2 building damage: see Building damage). Approved there: modular chunks generated in Godot from BuildingDef data (no Blender), towers take facade damage only and never collapse, LightmapGI for the static ground only (buildings and props use SDFGI), building occluders turn off when a building collapses.
- Map: `maps/urban_small/urban_small.tscn` (the default scene). The old test map stays in `scenes/levels/test_map.tscn`. Written by `tools/map_gen/urban_small.py` (placed nodes only: move or add them in the editor; running the script again overwrites the scene).
- Layout (about 256 x 256 m, x right, -z north): main avenue north-south, 24 m between curbs (6 lanes, 3 mechs side by side), 4 m sidewalks. Side street A east-west through the center (4-way intersection), 14 m (2 mechs), 3 m sidewalks. Side street B east of the avenue (T junction, z 57..71). Alley 4 m wide (z -35..-31, west of the avenue): the mech (5.2 m wide) stops at its mouth (tested: x -14.3, the alley starts at -16). Plaza 30 x 30 m with benches, trees and a fountain (x -50..-20, z 14..44). Parking lot with 12 cars and a fence (x 24..60, z -48..-14). Roads at y 0, curbs, sidewalks and blocks 0.15 m higher.
- Buildings: 25 low-rise (4 to 16 m: kiosks, sheds, shops, apartments, offices, warehouses) and 2 towers (55 m glass, 42 m concrete). Edge: 32 out-of-bounds edge blocks (32 m, no damage, one collider each) and invisible walls at +-129 m.
- Props: 156 near the streets, dense on the avenue near the spawn (lampposts, traffic lights, trees, benches, hydrants, people, a bus stop, parked cars, a bus).
- Paint and decals: lane lines, double yellow center lines, crosswalks, stop lines and parking stalls (one MultiMesh each for white and yellow); manhole covers, cracks and oil stains (Decal nodes, textures made by script in `assets/textures/decals`).
- Spawn: player on the avenue (x -5, z 36) facing north; dummy mech at z -30, enemy at z -95.

### Environment resources (data/environment, written by tools/map_gen/urban_data.py)

- `MaterialDef` (`scripts/environment/material_def.gd`): name, hp_per_m3, damage_threshold, density (t/m³), albedo/normal/roughness textures, texture_scale_m (meters per texture repeat), tint, metallic, roughness, emission, debris_color. The look is a StandardMaterial3D with world-space triplanar mapping, so textures keep their real size on every box. Starting values: glass 40 HP/m³, threshold 0; brick and plaster 150, threshold 30; concrete 300, threshold 80; steel frame 900, threshold 150; metal sheet 120, threshold 10.
- `BuildingDef`: footprint_x/z, floor_count, floor_height (3.2 m), ground_floor_height (4.0 m shops), wall/frame/glass/roof/door materials, window_ratio, window_height_ratio, shop_front, roof_type (FLAT, PARAPET, GRAVEL), wall_thickness, chunk_width (4 m), column_spacing, facade_only (towers), indestructible (edge blocks), integrity_multiplier.
- `PropDef`: size, hp, mass_t, reaction (NONE, CRUSH, PUSH, BEND, BREAK, FALL), crush_scale, bend_max_deg, push_per_speed, debris_pieces, water_spray, shake.
- New buildings, materials and props need only new .tres files (props also a scene in `scenes/props/urban`, made by `tools/map_gen/urban_props.py`).

### Building generator

`BuildingGenerator` (@tool, `scripts/environment/building_generator.gd`) builds a building from its BuildingDef in the editor and in the game. Origin: bottom center; front (shop windows, door) faces -Z.
- Per floor: wall panels along each face (the face length divided evenly near chunk_width), each with a window opening (4 wall pieces around it) and a thin glass panel set back in it; shop fronts on the ground floor front face (large windows, a 1 x 2 m door in the middle panel); a floor slab on top; interior columns on a column_spacing grid. Roof: parapet 1 m (PARAPET), parapet 0.5 m and gravel (GRAVEL), or none. Towers: a dark core box and a ring of columns behind the facade. 8% of the windows are lit.
- Look: one MultiMesh per material (few draw calls), dynamic GI. Game: each chunk is an `UrbanChunk` (StaticBody3D, layer 1) with its box shapes, kind (wall, glass, door, slab, column, parapet, roof, core), floor, material, volume and HP (volume x hp_per_m3 x integrity). Integrity: `BuildingGenerator.integrity_of()` = integrity_multiplier x (1 + 0.25 x footprint area / 100 m²). Edge blocks: one box collider, no chunks.
- One OccluderInstance3D (box) per building; occlusion culling is on in the project settings.
- The map has about 4050 chunks; it loads in about 1 s.

### Props and mech contact (Checkpoint 1)

`UrbanProp` (StaticBody3D, layer 3): weapons hit it (`on_hit`), mech bodies pass through it, its Contact area finds mechs. Reactions, one script each: `PropCrush` (car: squashed to 40% height with sparks), `PropPush` (bus: slides away about 0.35 m per m/s, heavier less, with a dent), `PropBend` (lamppost, traffic light: bends at the base, 25° + 7° per m/s up to 80°), `PropBreak` (bus stop, bench, fence section, hydrant: breaks into tumbling boxes with dust; the hydrant sprays water), `PropFall` (tree: falls over away from the mech). People stay (scale only). A small camera shake on the mech that touched it. At 0 HP from weapons the prop breaks (bends or falls for poles and trees). Meshes fade out past 120 m.

### Building damage (Checkpoint 2, user choice "break + collapse")

`BuildingDamage` (`scripts/environment/building_damage.gd`), one per destructible building, made by BuildingGenerator in the game (not for edge blocks). `UrbanChunk.on_hit` sends hits to it (bullets, beams, blades, pile bunker, missile blasts already call on_hit on layer 1).
- Damage: a hit below the material's `damage_threshold` does nothing (concrete 80, steel 150, glass 0). At 0 HP the chunk breaks: its boxes leave the MultiMeshes, rubble (`Rubble`, 1.2 pieces per m³, 2 to 6 per box, debris color) and dust (`DustBurst`) fly out; glass makes small shards and no dust. Its collision goes away. The building's occluder turns off at its first break.
- Support (low-rise): chunks link where their boxes touch (0.08 m gap); chunks within 0.2 m of the base stand on the ground. Glass and doors carry nothing. After a break, chunks with no path to the ground fall as `FallingChunk` bodies (their boxes, 90% collision size) and break when they land, hurting mech hitboxes within 6 m (250 at the center). At most 60 falling bodies at once in the level; more break where they are. Towers (facade_only) never collapse and have no support links.
- `FallingChunk.building` is now any node with `shatter()` (DestructibleBuilding or BuildingDamage).
- Test (headless, urban map): load 1.7 s (support links: whole-chunk bounds first, towers skipped); all 44 ground-floor chunks of Office5F broken: the other 186 chunks lose support (60 fall, the rest break in place), occluder off, rubble at its 220 cap; one wall on Apartment4F: that chunk and its window glass go, nothing else; a 1-damage hit on concrete does nothing; 116 facade chunks of TowerConcrete broken, nothing falls.

### Textures and lighting

- CC0 Poly Haven 1K textures in `assets/textures/<name>/` (asphalt 3 m, concrete 2 m, brick 1 m, plaster 2 m, paving tiles 2 m, sidewalk 1.8 m, metal 0.5 m, roof gravel 2.25 m; see CREDITS.md). Glass is a flat material.
- Sun with shadows; WorldEnvironment: SDFGI, SSAO, SSR, volumetric fog, glow, AgX tonemap, TAA (project setting); depth fog 0.003 (about 45% fade at 200 m). The graphics presets (GraphicsSettings) apply to it.
- LightmapGI node in the map: only the ground (GroundSlab meshes, static GI, lightmap UVs) is baked. Bake it in the editor on the user's PC (select LightmapGI, Bake Lightmaps); the cloud session cannot bake.
- Damage interface: the project already had one (`on_hit(damage: float)` on every damageable body: mech hitboxes, dummies, props, chunks), so no new Damageable component was added.

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
- G opens and closes the garage (Phase 5; Esc also closes it).
- Keys 1 to 9 and 0 switch test loadouts (5 = Recon, 6 = Recon Accurate, 7 = Recon Sleek, 8 = Recon Gen, 9 = Recon Sheet, 0 = Medium; key 0 is the action `loadout_10`): 1 Gunner (heavy rifle + shield), 2 Sniper (beam sniper, two hands), 3 Melee (pile bunker + shield), 4 Missile (heavy rifle + shield + two missile pods).

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
- Saved mech "OG Mech" (user request, after Phase 8b): the Warden as it is now, kept to call later. `scenes/mech/og_mech.tscn` (a copy of `player_mech.tscn`) with `data/loadouts/og_mech.tres` (the Warden gunner parts). `python3 tools/mech_gen/warden.py scenes/mech/og_mech.tscn` rebuilds it from the generator (then set its loadout back to og_mech.tres).
- Saved model "Granpa Gundam" (revision 41): RX-78-2 style, in `scenes/mech/granpa_gundam.tscn` with `beam_rifle.tscn` and `materials/rx78/`. It is a complete player mech scene. The Gundam design belongs to Sunrise and Bandai, so a public release needs an original design.
- Models are built from box, cylinder, sphere and prism shapes by Python scripts in `tools/mech_gen/` (run from the project root). Blender tools: `tools/blender/` (kit and export), `tools/godot/export_guide.gd`. `mech_scene.py` holds the shared skeleton and logic nodes. `warden.py` writes `player_mech.tscn`. `granpa_gundam.py` writes `granpa_gundam.tscn`. Give another path as the first argument to write somewhere else. Placeholders until Phase 8.
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
- Phase 8b (user choices: hit reactions, better walk and run, idle motion, turn in place):
  - `HitReaction`: every hit kicks the torso on springs (2.2 Hz, damping 0.4) and swings back. Head and center torso: lean back. Left side parts: turn left and roll right (right side: the mirror). Groin and legs: knee dip and roll toward that leg. Booster: lean forward. Push = damage / 150, up to 2.5. Per full push: 3.5° lean, 4.5° turn, 2° roll, 4° hip dip. Stagger: 450 damage within 0.35 s (a missile blast on several parts) adds 9° lean back and a 12° dip. Small camera shake per hit (0.0012 trauma per damage, up to 0.35).
  - `FootPlanter`: while walking and running, the leg in its stance half (MechFootsteps phase: left 0 to PI, right PI to TAU) is solved with two-bone IK in the leg plane so the sole stays where it touched down. When the stride is longer than the leg reaches, the leg straightens toward the point and the heel lifts (no sliding). IK blends in over 8% and out over the last 25% of the stance. Walk knee bend 9° hip / 18° knee (run 13° / 26°) for a heavier stance. Test: ground foot slide 0.025 m per frame before, 0.009 after (the body moves 0.152).
  - `TurnStepper` (turning in place): each foot keeps its world heading; the planted foot's leg turns at the hip against the body turn, the other foot lifts (knee up) and swings to lead the turn by 35% of a step. Feet swap every 22° of body turn. After the turn a foot that is still turned more than 4° takes a settling step (60°/s).
  - `IdleMotion`: after 1.2 s of standing still (no move, aim, kneel or turn): breathing every 4.5 s (0.6° lean, 1° knee dip), scanning (torso turns to a random angle up to 7° every 3 to 6.5 s) and a weight shift (1.4° roll to one leg every 5 to 10 s). It fades in and out at 1.2 per second.
  - Ground clipping fix (8b.1, user report): the feet were fixed to the shins (no ankle), so the toes went up to 1.7 m into the ground when walking and 3 m in slides. Test: the lowest point of every mech mesh in each state (stand, walk, run, boost stop skid, strafe, kneel, jump, dodge, fall, turn in place, hits, death) is now 0.00 m below the ground (toe tip bevels at most 0.07 m).
    - Ankle: each foot sits on a `FootPivot` at the ankle (2.05 m below the knee, sole 0.55 m below it; `tools/mech_gen/warden.py` ANKLE_Y).
    - `FootLeveler` (on the mech root, so it also works on a destroyed mech; priority 14, after every leg pose): a ray finds the ground under each ankle. Near the ground (sole within 0.4 m) the foot lies flat on it (up to 110° from the shin); high up (2 m) it hangs in line with the shin, toes 12° down. No corner of the foot box may go into the ground: the foot lies flat, and if that is not enough the leg bends (two-bone IK from the hip) to lift the ankle. The bend side is the knee's offset across the hip-ankle line (only the part across the line); a straight leg bends toward the body front (`straight_leg_pole_m`). Before this fix the offset from the line's middle was used: with a thigh and shin of different lengths (Medium 2.56 / 3.37 m) a straight knee is off the middle along the line, the IK bent the leg sideways and one leg stayed turned 90° (user report: legs spin). A knee or thigh under the ground (deep slide crouch, kneel) lifts the body by that much.
    - `BodyGroundClamp` (priority 15): while MechFall moves the body (topple, lie, roll, get up), the body rests on its lowest mesh point (`MechFall.ground_lift`, sinks back at 1.5 m/s when not needed). The held weapon turns up around its grip (9° steps) until it is out of the ground.
    - `FootPlanter` locks the ankle (0.55 m above the ground) instead of the sole.
  - `TorsoPose` adds the hit and idle lean, turn and roll. `MechLegSwing` adds the hit and idle knee dips and the turn step lifts.
- Later: rigged .glb models. Walk cycles for biped, reverse-joint, tank, and quad legs. Leg IK so feet stay on slopes and steps. Torso twist toward the aim. Weapon recoil. Boost and jump jet poses.

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
  - Skeleton (user choice "legs and torso keep frame"): `PartBreaker.blow_away` (side torso, booster, and the death blasts of the center torso, side torsos and groin) hides only the armor; the part's frame and joint meshes (material names starting with "frame" or "joint") stay in place, as for a destroyed leg. Arms and the head still fall off whole.
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
- Enemy AI (4b, user choice "simple gunner"): `MechSpawner` (was `DummyMech`) builds a mech with `pilot` NONE (dummy) or AI. `AIPilot` disables `MechInput` and fills the same input values, so the enemy uses the same movement, boost, dodge, shield and weapon rules as the player. It targets the nearest living mech in group "player" (the player mech, set by `LoadoutSwitcher`). It needs a clear line of sight (ray on layer 1) for 0.8 s before it acts. It walks in when farther than 80 m (boosts past 130 m), backs off when nearer than 40 m, and strafes left or right between (side changes every 2 to 4.5 s). It fires when the target is within 180 m and its torso is within 6° of it; the aim point wanders up to 2.2 m around the target lock point (`MechAim.use_ai_target`). It lifts the shield now and then (0.12 per second, more when the center torso is hurt, 1.6 s) and does a dodge hop now and then (0.06 per second). Enemy missile pods skip their own mech. The enemy label is red. When the player respawns (`PlayerRespawner.respawned`), all spawners build their mech again with full HP. Search (4b.3, user request): when it cannot see the target it walks to where it last saw it (8 m counts as arrived), then on toward the target, boosting past 130 m; stuck on a wall (under 1 m/s for 1.2 s) it steps sideways 1.5 s; no firing while searching. After a search finds the target it does not back off for 4 s. Test: player hidden behind the tall building; the enemy walked around it in about 17 s and fired.
- Destructible city (4c, user choice "props + building chunks"):
  - `DestructibleBuilding` (replaces `GreyboxBlock` for buildings): a grid of `BuildingChunk` blocks (static bodies on layer 1, wanted size 6 x 5 x 6 m, set to divide the building evenly: tall building 3 x 8 x 3 = 72 blocks, medium 3 x 3 x 3 = 27). 1000 HP per block. A block darkens with damage (to 55% of its tint). At 0 HP it breaks into 5 rubble pieces with a dust cloud.
  - Support: a block stands while it connects to a ground block through its faces. Blocks with no support fall (`FallingChunk`, a little smaller so they do not touch their old neighbors) and break into rubble when they hit the ground or the building. Each impact hurts mechs within 6 m (250 at the center, 30% at the edge; hitboxes only, so it does not break more blocks).
  - `Rubble`: loose box pieces (no layer, mechs walk through), 14 s, then they sink into the ground in 1.5 s. At most 220 pieces; the oldest goes first. `DustBurst`: one grey dust cloud per block.
  - Blocks and rubble use shared grid materials by tint (`GridMaterials`, shader `greybox_grid_tinted`), because per-object shader values have a small limit on some graphics cards.
  - `DestructibleProp` on the car (400 HP, 1.5 t), box truck (900 HP, 7 t), semi truck (1500 HP, 15 t) and lamppost (120 HP, 0.3 t). At 0 HP a vehicle explodes (flash, burnt black wreck, blast 80 to 120 damage in 6 to 9 m on props and mech hitboxes, so vehicles can set off vehicles next to them); a lamppost snaps. A mech that walks into a prop kicks it away (kick speed = mech speed x 1.3 x 30 / (30 + mass in t)); a mech that boosts or moves at 12 m/s or more wrecks it. Wrecks and kicked props are `Debris` bodies that stay 45 s.
  - Backspace loads the level again (test key, `DebugDamage`).
- Test keys (`DebugDamage`): F1 head, F2 center torso, F3 left torso, F4 right torso, F5 left arm, F6 right arm, F7 groin, F8 left leg, F9 right leg, F10 shield, F11 back units, F12 booster. Each press takes 30% of max HP; Shift + key destroys the part at once.
- Debug HUD: current / max HP of each part, DESTROYED, MECH DESTROYED.

## Garage (Phase 5)

User choices: G key in the level, light / medium / heavy part variants, 0 to 3 plates per part with visuals, weapons and mods in the garage.
- `Garage` (CanvasLayer in the test map): G opens it. The game pauses, the other screen layers (HUD, reticle) hide, and `GarageCamera` stands still in front of the player mech (since 5.1, user request; it circled at 8°/s before; right drag turns it, the wheel zooms 10 to 32 m). Every change rebuilds the player mech at its place with full HP (`LoadoutSwitcher.rebuild`), so the look and the stats show the new build. "Undo changes" goes back to the build the garage opened with. The new build stays after respawns.
- Left panel: frame (head, core, arm L, arm R, legs, booster, generator, FCS), weapons (right arm: heavy rifle, beam sniper, pile bunker; left arm: shield or none, forced none with a two-hand weapon; back L and R: missile pod or none), plates (3 pickers per part: none, light, heavy), mods (3 pickers).
- `GarageStatPanel`: weight, load capacity, load, walk and boost speed, boost acceleration and energy, torso and leg turn, jump, energy, recharge and delay, recoil, lock range, max locks, lock speed, and the HP of each part. Next to each value, the change from the opening build: green = better, red = worse. A warning shows when the mech is overloaded.
- `GarageCatalog` (`data/garage_catalog.tres`) lists what each slot offers. `tools/data_gen/garage_data.py` writes the catalog, the part variants, the plates and the mods.
- Part variants: medium = Warden. Light = Kestrel (sand color, thinner), heavy = Bulwark (olive, bulkier). They use the Warden models with `PartData.model_scale` and `armor_tint` (`PartLook`: each piece scales in place and moves out by 60% of the scale; armor materials get a tinted copy; frame and joint materials stay).

| Part | Kestrel (light) | Warden (medium) | Bulwark (heavy) |
|---|---|---|---|
| Head | 2.5 t, 280 HP, sensor 700 m, lock speed x1.25 | 4 t, 400 HP, 600 m, x1.0 | 6 t, 560 HP, 500 m, x0.85 |
| Core | 13 t, 1200 HP, energy 90, torso turn 100°/s | 18 t, 1600 HP, 100, 85.35°/s | 24 t, 2100 HP, 120, 70°/s |
| Arm (each) | 3.5 t, 450 HP, recoil x1.2, melee x0.9 | 5 t, 600 HP, x1.0, x1.0 | 7 t, 800 HP, x0.8, x1.25 |
| Legs | 11 t, 1000 HP, load 65 t, speed 13.5, jump 11 m, turn 135 / 67.5°/s | 16 t, 1400 HP, 80 t, 11.742, 9 m, 116.1 / 58.05 | 22 t, 1900 HP, 105 t, 10.2, 7 m, 95 / 47.5 |
| Booster | 2 t, 150 HP, thrust 1000, boost x1.6, 26 energy/s | 3 t, 200 HP, 1200, x1.5, 30 | 4.5 t, 280 HP, 1600, x1.45, 38 |
| Generator | 2 t, output 14/s, delay 1.6 s | 3 t, 17.5/s, 2.0 s | 4.5 t, 22/s, 2.4 s |
| FCS | 0.5 t, lock range 400 m, 3 locks | 1 t, 500 m, 4 | 2 t, 650 m, 6 |

- Plates (`PlateData`, light / heavy): head 80 HP 0.5 t / 150 HP 1 t; core 300 HP 2 t / 550 HP 4 t; each arm 120 HP 0.8 t / 220 HP 1.5 t; legs 250 HP 2 t / 450 HP 3.5 t. `PlateMounter` adds each plate as an armor slab (0.16 to 0.32 m thick) at one of three places per part: head top, left and right cheek; belly, left and right chest; upper arm outside, forearm outside, forearm front; shin front, thigh front, shin outside (legs plates cover both legs). The slabs belong to their part: they have hitboxes and fall off with it.
- Test targets (5.2): switches in the garage spawn or remove the enemy (AI) and the dummy mech (`MechSpawner.set_active`). A removed mech stays away after a player respawn.
- Mods (`ModData`): boost tuning +10% thrust, lightweight frame -5% weight, reinforced frame +8% part HP, capacitor bank +15% energy, overclocked generator +15% recharge, servo tuning +10% turn speed, recoil dampers -15% recoil, jump jet tuning +15% jump.

## Graphics settings (Phase 5)

`GraphicsSettings` (autoload) with presets Low, Medium and High, set in the garage (`GraphicsMenu`). Saved in `user://settings.cfg`, applied at start and to each level that loads.

| Setting | Low | Medium | High |
|---|---|---|---|
| SDFGI (global light) | off | off | on |
| SSR (reflections) | off | off | on |
| SSAO (ambient shadows) | off | on | on |
| Volumetric fog | off | on | on |
| Glow | on | on | on |
| Anti-aliasing | FXAA | TAA | TAA |
| Render scale | 75% (FSR) | 100% | 100% |
| Directional shadow map | 1024, hard | 2048, soft low | 4096, soft high |

## Graphics pass (Phase 8a)

User choices: graphics first, CC0 textures, detail the box models. CC0 textures from Poly Haven (1k, `materials/textures/cc0`, see its LICENSE.txt): concrete slab wall (buildings, rubble) and asphalt 02 (ground). The Poly Haven metal sets have their own plate seams, so the mech keeps engine noise textures and the panel shader.
- Mech materials: `materials/textures/` noise textures (grime, roughness, fine surface bumps; `NoiseTexture2D`, seamless 512 px) on the Warden materials (armor, armor dark, frame, joint, rifle), mapped in object space (triplanar), so they move with the parts.
- Box armor pieces use `mech_panel.gdshader` (`armor_panel`, `armor_dark_panel`; the generator picks them for box pieces): a panel groove 0.16 m in from each face edge, bolts in the groove corners (faces larger than 0.75 m), and patchy worn bright edges. Face size in meters comes from screen derivatives, so every box gets the same groove width. Plates use it too. `PartLook` tints both material types.
- Buildings: `building_facade.gdshader` in world space: CC0 concrete (4 m repeat, color, normal and roughness; the tint sets the brightness) with large stains and rain streaks, a slab band every 4 m floor, glass windows (1.9 x 2.3 m every 3 m, dark reflective glass with a frame, 4% with a dim warm light) above the ground floor. Rubble uses it with no windows. The grid shader stays for the other greybox blocks.
- Ground: `asphalt.gdshader` (CC0 asphalt, 3 m repeat, with large stains, and faint 10 m lines to judge scale and speed).
- Fog thinner (8a.2): depth fog density 0.012 to 0.005, volumetric fog 0.003 to 0.0015 (the tall building faded at about 80 m in Forward+).
- Test renders: the cloud container renders Forward+ with Vulkan on the CPU (Mesa lavapipe, `mesa-vulkan-drivers`, about 1 frame per second) or GL. `GreyboxBlock.surface_material` sets it.

## Custom mech pipeline (Blender, after Phase 8)

User choice: models built in Blender in the cloud container (Blender 4.0.2 from Ubuntu, with python3-numpy for glTF), and the user can edit the same .blend in their own Blender and push it back.
- Kit: `blender -b --python tools/blender/mech_kit.py -- <name>` writes `models/<name>/<name>.blend`: one collection per part (part_head, part_core, part_arm_l, part_arm_r, part_legs, part_booster) with the socket empties the part attaches to (`<Socket>_<part>`, turned 180° so the front faces Blender -Y), pivot empties (PauldronPivotL/R, FootPivotL/R, BoosterFlameL/R), materials named like the game materials, the OG mech as a wire guide (collection guide_og, names start with og_, not exported) and the text block export_parts.py.
- Rules: 1 unit = 1 m, feet on Z = 0, front faces -Y, about 10 m tall, joints at the OG places (hip 5.2 m, knee 2.6 m, ankle 0.55 m, shoulder 7.87 m, elbow 5.57 m, 2.47 m out). Materials armor... (break off, tinted by variants), frame / joint (inner frame that stays when a leg is blown apart); a name with a file in the part's `material_library` (default `materials/warden`) uses that game material.
- Export: Text Editor > export_parts.py > Run Script, or `blender -b models/<name>/<name>.blend --python tools/blender/export_parts.py`: one `<name>_<part>.glb` per part next to the .blend.
- Game side: PartData.scene = the .glb. `MechAssembler` finds the socket from the name before "_" ("Torso_core" -> Torso). `PartRigging` gives nodes their roles by name (pivots, FootL/R, BoosterFlame and BrakeFlame get flame meshes, a BoosterLight is added) and swaps library materials in; `PartLook` and `PartBreaker` read material names, so Blender materials work with tints and part breaking. Godot does not import .blend files (`filesystem/import/blender/enabled=false`); the .glb files are the game files.
- Guide: `tools/godot/export_guide.gd` exports a built mech as `models/guides/og_guide.glb` (hitboxes, flames, lights and hidden nodes left out; the folder has .gdignore).
- Test (pipeline): a box blockout made in the kit, exported and built in the game: all 11 hit keys and hitboxes, pivots, feet, flames and light found, game materials used, parts break off.
- Blender MCP (user's PC, user choice): setup in `tools/blender/BLENDER_MCP.md`. Image-to-3D (Hyper3D Rodin) makes one fused mesh; `tools/blender/split_generated.py` fits it (height 10.6 m), cuts each face to the nearest body bone and puts the pieces under the kit sockets and pivots (core cut into center and side pieces). Tested with Recon Accurate fused into one mesh: parts, hit areas and animation work, no errors.
- Round trip: the user pulls, opens `models/<name>/<name>.blend` in Blender (4.0 or newer), edits, saves, runs export_parts.py (or only saves; the cloud session can export), commits and pushes. Keep the collection, empty and pivot names. `*.blend1` backups are ignored by git.
- Edit in the game pose: `tools/godot/capture_pose.gd` (headless Godot) builds the player mech with a loadout on flat ground, waits 40 physics frames (rifle and shield held, before the idle motion) and writes `models/<name>/pose/pose.json` (rest and posed transform of each frame joint, mech space) and `pose/weapons.glb` (rifle and shield pieces; the folder has .gdignore). `tools/blender/kit_pose.py` (also in the .blend as text blocks `kit_pose_POSE.py` and `kit_pose_REST_and_export.py`): pose turns each socket and pivot empty by its game joint's move from rest (game to Blender: (x, y, z) -> (-x, z, y)), keeps the rest place on the empty (custom property `kit_rest`) and adds the weapons as collection `pose_ref` (not exported); rest puts the empties back exactly, removes the reference, saves and exports. Move the part pieces, not the empties. `export_parts.py` refuses to export while any empty has `kit_rest`. Hand edits in `models/medium_mech/medium_mech.blend` are lost if `medium_mech_build.py` runs again.

## Recon (first custom Blender mech)

User brief: name Recon, slim body, blue and black, from the user's reference picture (a military recon mech: chamfered plates with bolts, big boxy pauldrons with a square side vent, low hooded head with two red eyes, two tall antennas on the back, black frame limbs with round joints, six-sided knee plates, chunky feet, fists).
- Model: `tools/blender/recon_build.py` builds it in `models/recon/recon.blend` (same skeleton and joint places as the OG) and exports `recon_<part>.glb`. Plates are chamfered boxes (Blender bevel modifier, applied on export) with bolts on the big plates. Rebuilding replaces hand edits in the part collections: after hand edits in Blender, export with export_parts.py only.
- Colors (`materials/recon`, same noise textures as the Warden): steel blue armor, dark navy armor_dark, black frame, gunmetal joint, red eyes (glow), amber marks (emblem), lens.
- Data: `data/parts/recon/` (Recon head, core, arms, legs, booster, FCS; `tools/data_gen/garage_data.py` RECON), loadout `data/loadouts/recon.tres` (heavy rifle, no shield, Warden generator, Recon FCS). Key 5 switches to it; the garage lists the Recon parts. Stats: head 3 t, 320 HP, sensor 900 m, lock speed x1.35; core 15 t, 1350 HP, energy 105, torso turn 95°/s; arms 4 t, 500 HP; legs 13 t, 1150 HP, load 72 t, speed 12.8, jump 10.5 m, turn 128 / 64°/s; booster 2.5 t, 170 HP, thrust 1150, boost x1.6, 28 energy/s; FCS 1 t, lock range 620 m, 5 locks. Total 47.5 t, walk 10.3 m/s.
- Test: builds with 10 hit keys and hitboxes; walk, boost, skid, fall, part breaks and death with no errors and at most 0.13 m under the ground (chamfer corners).
- Known: armor plate slabs (PlateMounter) use the Warden plate places, so on Recon they do not sit on the armor yet. The left arm with no shield holds the shield rest pose.

## Recon Accurate (second Blender mech)

User brief: model the same reference picture closely (shaped plates, not boxes), name recon_accurate, Recon colors.
- Model: `tools/blender/recon_accurate_build.py` builds `models/recon_accurate/recon_accurate.blend` and exports `recon_accurate_<part>.glb`. Plates are cut from outlines (side and front shapes, tapers, six-sided knee pads, wedge feet), then extruded and beveled, with inset panels and brass bolts. Build: `blender -b models/recon_accurate/recon_accurate.blend --python tools/blender/recon_accurate_build.py`. Rebuilding replaces hand edits.
- Shapes: large chamfered pauldrons with square side vents and top plates, low wedge helmet with two red eyes and a crest, two stepped antennas on the backpack, wide chest with sloped upper plates, vents and belly plate, black frame limbs with ring joints, six-sided guards on the forearms, tapered shins with calf pistons, wedge feet with black toe caps.
- Colors: the Recon materials (`materials/recon`) plus brass bolts (`bolt.tres`).
- Data: `data/parts/recon_accurate/` (Recon stats, Recon FCS shared), loadout `data/loadouts/recon_accurate.tres`. Key 6; the garage lists the parts.
- Test: walk, boost, jump, leg loss and death with no errors; no part under the ground.
- Known: plate slabs (PlateMounter) use the Warden places. The left arm with no shield holds the shield rest pose.

## Recon Sleek (third Blender mech)

User brief: a sleek version of Recon Accurate, name recon_sleek.
- Model: `tools/blender/recon_sleek_build.py` builds `models/recon_sleek/recon_sleek.blend` and exports `recon_sleek_<part>.glb`. It uses the plate and cylinder helpers of recon_accurate_build.py with 4 bevel segments, wide bevels, thin panel lines and no bolts. Build: `blender -b models/recon_sleek/recon_sleek.blend --python tools/blender/recon_sleek_build.py`. Rebuilding replaces hand edits.
- Shapes: long low wedge head with one red visor band and two swept fins; V-shaped chest with a pointed keel plate; thin waist; swept teardrop pauldrons tilted down at the outer edge, with a rear fin and slit vents; thin arms with forearm guards that taper to the wrist; tapered thighs; diamond knee pads; long tapered shins with a calf fairing; long pointed feet; slim backpack with two thin tapered antennas.
- Colors, stats and data as Recon Accurate: `data/parts/recon_sleek/`, loadout `data/loadouts/recon_sleek.tres`, key 7, garage parts.
- Test: walk, boost, jump, leg loss and death with no errors; no part under the ground; side torso hit areas found.

## Recon Gen (first generated mech)

- Rebuilt by script (user choice, the split generated mesh looked disjointed, showed cut faces at bent knees and had an open groin): `tools/blender/recon_gen_build.py` builds all pieces in `models/recon_gen/recon_gen.blend` with the Recon Accurate plate helpers and exports the parts. Every piece is a closed solid, so a bend shows joint pieces, never a cut face. Design from recon_ref.png and the user notes: olive plates with brass bolts, mono eye in a black ring, no antennas, even trap plates from the neck to the shoulders, shoulder ball with the pauldron above it (lower edge 7.7 m, detached look), elbow ball, wrist ball, black fists, closed groin (dark pelvis block, olive codpiece, back plate), hip ball, knee hinge on the knee axis plus the knee roller on the thigh (y -0.7, z 3.3 m, 0.9 x 0.95 m, user placement), six-sided knee pad, ankle ball, wedge feet. Vertex colour `Col` per piece (0.7 faces down to 1.0 faces up). 118 meshes, about 66,800 triangles, 9.53 m tall. The script also rebuilds the preview copies on the preview rig (run action, feet planted). Blender 5 note: the plate helper writes the mesh before its material slots, which sets every material index to 0; recon_gen_build.py restores the indexes (bolts keep brass). Everything below about the split model is history; `recon900_clean` stays in the .blend as a shape guide.
User brief: the left mech of `models/guides/recon_ref.png`, made with Hunyuan3D (`models/guides/recon.glb`), fitted and split with Blender MCP (`blender_task.md` steps).
- Source now `models/guides/recon_900k.glb` (Hunyuan3D; the file has 361,476 faces, same shape as the 100k and 300k exports). All steps below were run again on it (fit, antenna cut, 50,000 faces, plates, mirror, joint cuts, traps, pauldrons, ball joints, covers, shins, eye, paint, run contact); labels come from the stored 100k cut. The .blend keeps `recon900_clean` and the cut mesh `recon900_cut`. Earlier source: `models/guides/recon_100k.glb` (Hunyuan3D, 100,000 faces). Same steps as the 10k model: moved 0.3 m back, same leg/arm fit (arms back 0.66 m, legs 0.40 m), antennas cut above 8.75 m behind y 0.8, reduced to 50,000 faces, plate cleanup (20°, 3 passes), mirrored, cut and labelled from the 10k pieces, caps, shin shear (6.8° lean removed) and the left shin 4° turn. Right side pieces (core side, pauldron, upper arm, forearm, thigh) are mirror copies of the left. Pelvis plates that face forward are armor. Knee fix: the thigh ended in a thin neck above the knee plate, so the leg looked detached. Knee caps are now radius 0.72 m, raised 0.5 m above the knee axis (center 3.1 m) and fixed on the thigh (HipL/R), so they do not swing when the knee bends and each thigh has a black beveled knee housing (gen_kneeHousingL/R, z 3.15 to 3.9 m) that fills the neck. Surface smoothing was tried and undone (pieces back to the f90f334 shapes). Knee caps scaled to 70% (radius 0.5 m, z 2.6 to 3.6 m, still touching shin top and knee housing). One mono eye (gen_eye, red, in a black ring gen_eyeRing) at the head front center, 8.75 m. Paint v2: each flat plate (26° groups) gets one material: `frame` only for enclosed plates (occlusion over 0.85 on torso, head, pauldrons; 0.55 to 0.75 on limbs), `armor_dark` for plates that face down, `armor` for the rest; fists and foot soles frame. Vertex colour `Col` (exported as COLOR_0): recess shadow, lighter worn convex edges, ±6% brightness per plate. Blender materials multiply `Col` into the base colour; Godot materials use vertex_color_use_as_albedo. Colours (sRGB): armor 0.47/0.47/0.31, armor_dark 0.30/0.31/0.19, frame 0.10/0.10/0.11, joint 0.16/0.16/0.17. Joints like `models/guides/joints.png`: a ball on each joint point, segments end at the ball. Legs cut again at the knee point (thigh/shin at 2.6 m, foot at 0.85 m), shins straightened and the left shin turned 4° again; knee ball r 0.62 at the knee, ankle ball r 0.42 at the foot pivot, hip ball r 0.5; knee cylinders and knee housings removed. Arms: shoulder ball r 0.65 at the shoulder point, elbow ball r 0.55 at the elbow point, hand ball r 0.36 on top of each fist (4.15 m, on the forearm). Pauldrons detached: moved 0.25 m up and 0.15 m out, lower skirt cut at 7.55 m; upper arm top cut at 7.25 m, so the shoulder ball shows in the gap. Thigh covers (gen_thighCoverL/R, olive, beveled) close the thigh tops (5.5 to 6.08 m). Traps (torso top between neck and shoulders) are one even slope per side (8.6 m at the neck to 8.25 m at |x| 1.7 m); antenna stubs behind the head flattened to 8.5 m. Knee undo (user): all knee changes after phase 3 were undone (bigger cap, knee housing, raised cap, 70% cap, joints.png knee ball and 2.6 m cut). The knee is again the phase 3 design: thigh/shin cut at 3.35 m (knee plate on the shin), hinge cylinder on the knee axis (2.6 m) on the shin. Now diameter 0.9 m, length 0.95 m, centred across the leg width (x ±1.47), moved to center y -0.7, z 3.3 m (up 0.7 m and 0.7 m forward from the knee axis; set into the front of the knee) and fixed on the thigh (HipL/R) so it does not swing. The other joints.png balls stay. Mech about 50,500 triangles, 9.41 m tall. Kept in the .blend: `recon100_clean` (clean full mesh) and the old 10k `recon_clean`.
- Model: `models/recon_gen/recon_gen.blend`. The generated mesh (10,100 faces, no texture) was bent to the OG guide joints (legs shortened: ankle 0.8 m, knee 2.6 m, hip 5.2 m; arms moved in and back), the four back antennas were removed, then `split_generated.py` cut it (FIT_HEIGHT None). Height 9.58 m. The feet are flatter than the picture.
- Cut fixes by hand rules: head block from the core, crotch and waist to the pelvis, elbow cut at 5.75 m, thigh/shin cut at 3.35 m (the whole knee plate stays on the shin), foot/shin cut at 0.85 m, hip caps on the thighs.
- Skin (phase 4, from recon_ref.png): own material library `materials/recon_gen` (Recon files with olive armor 0.33/0.34/0.20 and dark olive armor_dark). Faces are `armor` (olive) or `frame` (black) by occlusion: 24 short rays (1.2 m) per face, more than 60% blocked = frame (recesses, inner faces); the fists (forearm below 4.1 m) are frame. Joint caps use `joint` (gunmetal). Two red `eye` boxes (gen_eyeL/R, part_head) on the head front at 8.8 m. Hidden `recon_hy` and `recon_hy_orig` (fitted and unfitted mesh) stay in the .blend outside the part collections.
- Data: `data/parts/recon_gen/` (Recon stats, Recon FCS shared, material library `materials/recon_gen`), loadout `data/loadouts/recon_gen.tres`, key 8, garage parts.
- Test (headless): builds with no errors, 10 hit keys with side torso, all surfaces use the Recon armor, feet at the ground, arm and leg breaks work.
- Rework (Blender, phases): 1. Skeleton: armature `recon_gen_skeleton` (collection `rig`, 8 m right of the model) with the game frame bones (Upper, Torso, Lower, Shoulder, Elbow, Hip, Knee, FootPivot, PauldronPivot, Head and Booster mounts) and colored joint balls (red joint, green pivot, blue mount). Joint limits (Limit Rotation, local): elbows and knees are hinges (elbow 0 to 145° forward, twist ±45°; knee 0 to 140° back), shoulder forward 150 / back 50 / out 100 / in 10 / twist ±70, hip forward 110 / back 40 / out 45 / in 15 / twist ±35, foot toe up 40 / down 60 / roll ±25, torso and lower twist ±90. 2. Clean mesh `recon_clean`: faces grouped into flat areas and vertices moved onto the area planes (flat plates, hard edges), mirrored left to right, closed. 3. Joints: `recon_clean` cut on planes (elbow 5.57 m, knee 3.35 m with the knee plate on the shin, ankle 0.85 m, waist 5.6 m, pelvis at |x| 0.7 above 4.0 m), open cuts filled, shins straightened (sheared so the shin center stays at |x| 1.47 m; feet moved under the ankle; the mech's left shin, ankle cap and foot turned 4° inward about the knee, foot kept flat), joint caps (material `joint`): hinge cylinders at elbows, knees and ankles, balls at shoulders and hips, a waist cylinder. 29 pieces, 9.40 m tall.
- Preview (Blender only): collection `preview`, 16 m right: linked copies of the pieces on a copy of the skeleton (rig hidden, so no bones over the moving model). Action `run` (40 frames at 24 fps, 2 steps: contact, planted stance to mid-stance, push-off, one flight per step with the body 0.46 m up; small ±4° body twist, ±18° arm swing with the pauldrons turning the same as their shoulder, forearms swing with the arm: elbow 68° with the arm forward, 32° with the arm back) plays on both skeletons. The first, bouncier cycle is kept as action `dance_animation`. The game does not use it: game walking and running are the procedural LegSwing and FootPlanter.

## Mech frames (own joint layout per mech)

User decision: a mech can have its own joint positions (asked for Recon Sheet, to match its picture).
- `MechFrame` resource (`scripts/data/mech_frame.gd`, files in `data/frames/`): hip height and width, thigh and shin length (ankle height = what is left), waist joint above the hips, shoulder width and height above the waist, upper arm and forearm length. Defaults = the OG layout.
- `PartData.frame`: the legs bring the leg values, the core the torso and shoulder values, each arm its arm lengths. No frame = OG layout, so all older parts are unchanged (tested: Warden joints and lengths the same).
- `MechFrameApplier` (called first by MechAssembler): moves Lower, Torso, HipL/R, KneeL/R, ShoulderL/R, ElbowL/R; hand markers (AimAnchor, LeftHand, LeftHandRest, LeftHandRaised) keep their offset from their shoulder; sets the lengths in FootPlanter (thigh, shin, ankle), FootLeveler (sole depth = ankle height), MechLegSwing (leg length = hip height), FallPose and PowerDownPose (thigh, shin + ankle), the arm TwoBoneIK nodes.
- Blender: `tools/blender/frame_io.py` reads a frame file; `mech_kit.py -- <name> <frame.tres>` makes a kit with those sockets and pivots (no OG guide).
- Known: mixing parts of different frames in the garage works, but the models may not fit each other. Armor plate slabs (PlateMounter) still use the Warden places.

## Recon Sheet (fourth Blender mech, from the user's views)

User brief: first built from the user's part sheet; then rebuilt to look like the user's three views (`models/guides/recon_sheet_views.png`: front, left side, back) with its own joint layout.
- Frame `data/frames/recon_sheet_frame.tres`, measured from the views at 0.0132 m per pixel (10 m to the helmet top): hips 5.95 m high and 1.6 m out, thigh 2.05, shin 2.95, ankle 0.95, waist 6.7, shoulders 2.6 out at 8.4 m, upper arm 1.45, forearm 2.5.
- Model: `tools/blender/recon_sheet_build.py`. Each piece is a box or side outline given in picture pixels (front view x, rows, side view x for depth), with flat chamfers (one bevel segment). The chest juts about 2.3 m in front of the legs and the feet are about 4.3 m long, as in the side view. The lower legs, feet and forearms sit a little outward of their joints, as the picture legs and arms spread. The .blend has the views as reference images (`ref_front`, `ref_side`, not exported).
- Colors: `materials/recon_sheet` (olive armor 0.31/0.34/0.18, darker olive armor_dark, dark gray frame and joint, red eye).
- Data: `data/parts/recon_sheet/` (Recon stats, Recon FCS, frame on core, arms and legs), loadout `data/loadouts/recon_sheet.tres`, key 9, garage parts.
- Test: walk, boost, jump, leg loss and death with no errors; no part under the ground; side torso hit areas found; the rifle is held with the new shoulders.
- Known: the three views do not agree fully (AI picture), so the side depth is a best fit. Arms and legs hang straight in the game rest pose (the picture arms spread out).

## Medium (user parts, playable as medium_mech, key 0; rigged GLB viewer)

User brief: assemble the four AI-made parts in `models/medium/` (head, torso, legs, arms .glb) like `models/guides/medium_reference.png`, add connector shapes, add an armature.
- File: `models/medium/medium.blend`, collection `Mech_Medium`. About 13.3 m to the head top, faces -Y, feet on Z = 0.
- Part fixes: torso and head had a ground plane in the mesh (removed). Legs and arms hold one limb each, so the right side is a mirrored copy. The leg was bent forward 17°; everything above the ankle is turned around the ankle so the leg stands straight, then legs made 20% larger (pelvis pieces too). The heel top plate was turned with the shin by mistake; it is turned back. Torso: 20% wider, then 50% larger (from its bottom); its neck block above the armor squashed to 20%.
- Manual changes by the user (keep them): torso scale Y 0.94, head scale 1.7/1.32/1.38 (head moved up), rig moved by (-0.056, 0.05, 0). On the right side: upper arm turned about 180° on Z (scale 1.56/1.26/1.48), forearm turned about 180° on Z, hand tilted (scale 0.8/1.0/0.84), larger elbow pin, thigh scale Y 1.58 and Z 1.32, shin and foot turned (foot scale 0.8), small shoulder mount (0.3). Later on the right side: torso scale X 0.91, upper arm scale 1.56/1.56/1.62, forearm scale Z 1.2 and re-turned, hand, wrist pin and elbow hub moved (hub scale X 0.68), elbow pin deleted, elbow moved (upper_arm tail), foot bone tail moved up and forward (now 2.5 m in front of the ankle, 0.35 m below it). Then on the right leg: thigh, shin, foot and hip axle moved up and out, shin scale Z 1.12, ankle hubs deleted. Joints follow their parts (hip on the thigh, knee on the shin, ankle and toe on the foot, found from the transforms before the edit): hip 7.26 m at x ±1.75, knee 4.72 m, ankle 1.39 m; soles 8 cm under Z = 0 at rest (the walk places the body from the lower sole). The left side copies each right transform and bone change, mirrored across the mech center plane in rig space (left meshes are exact mirrors of the right meshes).
- Lesson: a failed script can leave a half-made mesh behind under the wanted name (a full-leg copy called `new_shin` replaced both shins and doubled the leg in the walk). Look meshes up by the object that was just made, never by name after a failed run, and check vertex counts after any mesh swap.
- Splits (one object per bone, so nothing can tear):
  - Knee: natural seam behind the knee guard, no cut. Leg pieces with a top above z -2.0 (leg space) go to the thigh; the thigh frame ends at z -2.47, the knee guard covers z -2.05 to -3.8 and stays whole on the shin. `knee_cyl_L/R` hub (radius 0.55 m, 1.3 m long along X, end caps, on the shin bone) at the knee pivot (4.72 m) fills the gap between the thigh and the guard, so the open inside of the knee is not seen when it bends (replaces the knee balls, which stayed behind when the user moved the legs).
  - Ankle: pivot set by the user on the right leg (rig space (-1.927, 0.259, 1.466), at the ankle disc, slightly behind its center), mirrored to the left. Shin and foot rebuilt from `legs.glb`: a piece goes to the shin if it reaches above leg-space z -4.3 or its center is above -4.6 (front shin plate, side plates and strut stay whole); everything else goes to the foot, so the whole ankle disc ring is on the foot. The seam is hidden behind the front shin plate and between the side plates. The user deleted the ankle hubs. The user's later shin stretch (Z 1.12) and foot scale (0.8) made the shin and foot pieces at the back of the ankle stop lining up (torn flaps): thin shards (under 4 cm thick, under 200 verts) at leg-space z -4.85 to -4.35 behind the disc are deleted, and `ankle_bracket_L/R` (dark block 0.86 x 0.62 x 0.36 m with bevels, on the shin bone) covers the seam above the back of the disc. Objects `thigh`, `shin`, `foot`. (An earlier flat-plane cut at z -4.25 split the front plate; replaced.)
  - Elbow: flat-plane slice z -1.20 to -1.33 (arm space) through the dark roller, closed with flat `frame_dark` faces, `elbow_joint_L/R` pin (radius 0.15 m, along X).
  - Wrist: one plane at z -3.045 (arm space) between the forearm armor and the hand back plate, closed flat; `wrist_joint_L/R` pin (radius 0.13 m).
- Arms: imported again from `arms.glb` (scale chain: raw x 6.3, re-origin to the shoulder disc, x 0.85, then x 1.3 wide and x 1.1 long), mirrored on their own X (user: "switch sides the arms"); the upper arms (shoulders) then mirrored back on their own X (user: "switch the left and right shoulders"). Hands turned 90° on the vertical axis (palms in). The finger bundle had 5 segments; the 2 tip segments are removed. The finger end is cut flat and closed with a rounded tapered tip (material `finger_tip`) built from the cut outline.
- Layout: hips 6.72 m at x ±1.5 (legs splay 4° out), pelvis belt top 8.14 m, waist block 8.04 to 8.83 m, torso 8.68 to 12.34 m, shoulders about 11.2 m at x ±3.5 (arms splay 5° out), head on a short neck collar. The upper body (waist up: torso, neck, head, shoulders, arms and their joints) was raised by 8% of the mech height (1.03 m), then lowered by 60% of that lift (0.62 m); net +0.41 m. The pelvis bone ends at the waist block middle (8.41 m).
- Connectors (materials `frame_dark`, `armor_olive`): pelvis core, crotch plate, back plate, belt, hip axles, waist block and ring, shoulder mounts and axles, neck and collar, knee hubs, ankle brackets, wrist pins, `elbow_cyl_L/R` (elbow hub: radius 0.28 m, 1.6 m long along X at the midpoint of the two elbow cuts, end caps; on the forearm bone).
- Rig `mech_medium_rig`: root, pelvis (6.72 to 8.0 m), torso (to 11.93 m), head (to 12.85 m), upper_arm/forearm/hand .L/.R (bones placed from the parts: shoulder at the upper arm origin, elbow and wrist at the pin centers), thigh/shin/foot .L/.R (hip 6.72 m, knee 4.31 m, ankle 1.47 m, at the ball centers). Rigid skin, weight 1.0 on one bone per object, Armature modifier. Any vertex added later must get the weight too, or it stays behind in poses.
- Action `walk`: 48 frames at 24 fps, in place (two steps in 2 s). Thigh swing asymmetric: angle = (Af+Ab)/2·cos q + (Af−Ab)/2·cos² q, so Af at full forward and Ab at full back with no kink. Knee lift: extra thigh flexion Ak·L(q) with the same extra knee bend (shin keeps its angle), L = sin² window over the middle of the swing (q from π+0.35 to 2π−0.35) so it does not change the step ends. Tuned by search on the posed rig: Af = 33.6°, Ab = 16.9°, Ak = 46.5°, c = 15.1°: the ankle reaches 2.37 m in front of the hip (+50% from 1.58 m), 2.82 m behind (kept), knee rise 2.09 m (+33% over the longer step alone, which already raised it from 0.92 to 1.57 m); max knee bend 124°. Foot flat in stance. Body height and toe-off (fixes a knee/foot flick): a fixed toe-down angle on the 2.6 m long foot pushed the toe 0.5 m into the ground, so the body rose and then dropped 0.5 m in 2 frames at heel strike, and the raised knee jerked with it. Now: (1) body height comes from the flat feet (no toe-down), smoothed over the cycle; (2) at push-off the trailing foot tilts toe-down only as far as needed to keep its toe on the ground (found by search each frame, max 20°), and after the toe can no longer reach the ground (lift-off) the last tilt fades out over 0.8 rad; (3) the tilt curve is smoothed; (4) the body is raised only if a sole would go below Z = 0. Result: body moves at most 0.09 m per frame, foot pitch to the ground changes at most 4.7° per frame (peak 14° toe-down at push-off), lowest sole 0.00 to 0.02 m every frame. Swing foot clears up to 3.24 m. Crouched walk: a constant crouch c is added (thigh forward +c, knee +2c, foot keeps the sole level), found by search so the mean hip height is 7% of the rest hip height (0.47 m) lower than the upright walk. Current: pelvis bone 5.78 to 6.26 m (mean 6.07 m); stance foot slides 0.07 m sideways. Search again whenever a leg joint moves. Arms swing ±12° opposite to the legs; torso twists ±8°, the pelvis does not twist (a pelvis twist swings both legs and slides the stance foot sideways). Bone roll: every limb bone has its X axis along world X (`align_roll(X × bone direction)`), so the X rotations are pure forward/back hinges; the default roll on the forward-pointing foot bone was tilted 30° and turned the foot up to 17° each step. Measured after the fix: stance foot slides 0.06 m sideways, foot yaw changes by less than 3° over the cycle. Forearms sway ±10° (lagging the upper arm by 0.9 rad, ±4° sideways) and straighten up to 5° more while the upper arm swings forward (forearm X from -22° to -4°), hands ±6° (lag 1.6 rad).
- Godot export (user choice: rigged GLB + viewer, not playable yet): `models/medium/medium.glb` (53 MB, textures embedded), exported from the `Mech_Medium` collection with the armature, skins and the `walk` action (glTF, Y up, modifiers not applied). Checked by importing it back into an empty Blender scene: same size at rest and at frame 37 as the source. The mech faces +Z in Godot.
- Viewer: `scenes/levels/medium_viewer.tscn` (sky, sun with shadows, asphalt ground, the model, `OrbitCamera`). `AnimationLooper` (`scripts/animation/animation_looper.gd`) finds the model's AnimationPlayer and plays `walk` on a loop; `OrbitCamera` (`scripts/camera/orbit_camera.gd`) circles the mech (drag to turn, wheel to zoom).
- Playable (user choices: game part system, keep 13.3 m, Recon Sheet booster): `medium_mech`, key 0, garage parts.
  - Frame `data/frames/medium_mech_frame.tres` (from the rig, limbs straightened): hips 7.407 m high and 1.747 m out, thigh 2.562, shin 3.374 (ankle 1.471), waist 1.147 above the hips, shoulders 3.207 out and 2.797 above the waist, upper arm 1.733, forearm 2.745 (elbow to the hand center).
  - Model: kit `models/medium_mech/medium_mech.blend` (mech_kit.py with the frame) filled by `tools/blender/medium_mech_build.py` from `models/medium/medium.blend`: each limb piece turned about its upper joint until the joint below hangs straight (the 4° leg and 5° arm splay go away in the game), feet only moved (flat), model lifted 0.147 m (soles at 0) and moved 0.06 m along the depth, rigid pieces under the kit sockets (no skin), feet named FootL / FootR. The script checks the result against the frame file. Pieces: head (head, neck), core (torso, waist, neck collar, shoulder mounts), arms (shoulder axle on Torso, upper arm on the shoulder, elbow hub, forearm, wrist pin, hand on the elbow), legs (pelvis pieces, hip axles, waist ring on Lower, thigh on the hip, knee hub, shin, ankle bracket on the knee, foot on FootPivot), booster (Recon Sheet backpack pieces and BoosterFlame pivots, moved 1.79 m back and 0.39 m up onto the torso back). Run it again after any change to medium.blend.
  - Data `data/parts/medium_mech/` (Warden stats for head, core, arms, legs; Recon Sheet booster stats; frame on core, arms, legs; the booster uses `materials/recon_sheet`, the rest keeps the Blender textures), loadout `data/loadouts/medium_mech.tres` (heavy rifle, Warden shield, Warden generator and FCS). Listed in both maps (and `tools/map_gen/urban_small.py`), the garage catalog (and `tools/data_gen/garage_data.py`).
  - Hand edits (user, in the game pose with kit_pose.py, 2026-10-07): right upper arm turned, right forearm, hand, wrist pin and elbow hub moved 0.5 to 0.9 m on the elbow, booster nozzles moved about 1 m (the BoosterFlame pivots moved with them, 0.14 m behind each nozzle). Exported from `medium_mech.blend`; checked in the game (posed snapshot from capture_pose.gd): every changed piece within 3.5 cm of the Blender pose. Since these edits, `medium_mech.blend` is the source of the game parts: running `medium_mech_build.py` again would undo them.
  - Rifle hold (user: gun and hand not aligned): the arm IK puts the forearm bone end (forearm_length from the elbow) on the rifle's GripRight, so the hand must sit at that bone end. The moved right forearm group had put the hand 1.36 m off it (1.24 m to the side). Fix: the right elbow hub, forearm, wrist pin and hand are the mirror of the left ones again (as built; the turned right upper arm stays), and the rifle hold moves to where the user put the hand: `ArmPart.hold_offset` (new, default 0; the right arm's offset is added to the weapon's rest transform, aim anchor and one-hand hold place in `WeaponController`), Medium right arm (1.21, -0.45, -0.33). Test (headless): grip at (3.59, 8.76, -2.02) m, hand center 0.19 m from it standing and aiming; Warden grip unchanged.
  - Walk lean (user: lean a couple of degrees forward while walking): `LegPart.walk_lean_deg` (new, default 0), Medium legs 3°; MechAssembler gives it to `TorsoPose.walk_lean_deg`, which leans the upper body forward by it, faded in by walk speed (not while running or boosting). Test: Medium torso about 2.8° more forward than the Warden while walking.
  - Booster flames (user: fire from the bottom of the jet pack): BoosterFlameL/R at the bottom center of the nozzles the user moved to the pack bottom (8.28 m), 25° back tilt kept. An earlier flame move was undone by kit_pose.py rest (it restored every empty); kit_pose.py now keeps and restores only the frame joint empties.
  - Skeleton: `tools/blender/medium_frame_split.py` splits each textured Medium piece by texture brightness per mesh island (area-weighted, below 0.18 linear = frame): frame islands go to `<piece>_frame` on the same socket with material `frame_<piece>` (same texture). Torso, head, thighs, shins, feet, upper arms, forearms, hands: about 35 to 50% frame. Test: a destroyed Medium leg keeps its 5 frame meshes, the booster its 7 frame and joint meshes.
  - Arm turn: the game arm IK (`TwoBoneIK`) builds the shoulder and elbow turn from the bend direction, which turns both arm bones 155 to 180° about their own length in the standing pose (measured: shoulder L 177°, elbow L 173°, shoulder R -153°, elbow R -168°; Recon Sheet gets 135 to 175° too, but its arms look the same from all sides). So the Medium arm pieces are turned 180° about their joint's vertical axis in the build (`ARM_IK_TWIST_DEG`); without it the left forearm and hand looked like the right ones (user report).
  - Test (headless Godot 4.7.2, `D:\EMCMII\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . --script <test.gd>`, temporary test script removed after): stand, walk, strafe left and right, walk back and turn in place: no hip turn while moving (turn in place: the normal turn step, up to 24°), foot pivots within 1.5°; arms match the source model in a posed snapshot.
  - Known: the mech body capsule (10 m) is made for 10 m mechs, so the head stands above it. When a leg explodes only its dark caps and hubs stay (the textured armor is not named `armor`, so no tint either). Armor plate slabs (PlateMounter) use the Warden places.
- Recon Comfy (earlier user model) was removed on 2026-10-07 at the user's request.

## New mech (user parts, Blender only, not in the game yet)

- File: `models/new_mech/new_mech_exploded.blend` (user's working file; `new_mech_v2*.blend` are older copies). 9.85 m tall (scaled to 10 m, then lowered 0.155 m so the feet stand on z = 0), mech faces -Y.
- Parts stay separate objects (the user asked; Godot imports several skinned meshes on one skeleton, and PartBreaker hides or drops parts by node). Each part is a child of `MechRig` with an Armature modifier and one vertex group at full weight (rigid, no stretching). Hands (`Hand_L`, `Hand_R`, user's low-poly versions, about 19,400 faces each) are cut at the knuckles into palm, 3 segments per finger and 3 thumb segments.
- Rig `MechRig`: root, pelvis, torso, head, upper_arm, forearm, hand, fingers, thigh, shin, foot per side; `grip_L/R` weapon sockets (not deforming); leg IK (`foot_ctrl`, `knee_pole`); arm IK set up with influence 0 (`hand_ik`, `elbow_pole`).
- Joint limits: `tools/blender/new_mech_joint_limits.py` (design limits, then each joint is swung until it pushes more than 6 cm deeper into its own parent chain than at rest). Elbows about 55°, knees about 66 to 69°: weapon poses that need more elbow bend need trimmed arm parts.
- Actions (fake user, looping with Cycles modifiers, each on its own NLA track for export; scene 30 fps since 2026-10-09, older actions stretched 1.25x to keep their speed): Idle (120 frames), Walk (60, 2.7 m/s), Slow_Run (45, 4.6 m/s, arms 12° out, hip sway 0.03 m, yaw ±3°, roll ±1°) with the feet 30% closer to the centre line than the rest stance (2.6 m apart), Head_Scan (150 frames, ±17.5°, head bone only, layered over the body actions), Hand_Open, Hand_Grip, Hand_Trigger. Gaits: `tools/blender/new_mech_gaits.py` (a swing foot too close to the hip for the knee limit is pushed straight away from the hip, so the knee never flips). No body part clips into another limb by more than 3 cm in any action.
- Full-speed run (user's run brief, 2026-10-09): `tools/blender/new_mech_run.py` builds `biped_run_full` (free arm swing: shoulders ±25°, elbows 40 to 55°) and `biped_run_full_unarmed` (small additive arm layer for the aim layer: shoulders ±4°, elbows 55°, hands lag 2 frames); the user swapped the brief's two names. 30 frames at 30 fps, in place, forward -Y. Brief distances scaled by hip height 5.90 / 5.0 = 1.18: 14.2 m/s, step 7.08 m, stance foot moves back 0.472 m per frame, lands 2.36 m ahead and leaves 3.31 m behind the hip, feet 1.06 m from the centre line (brief 0.71 m, widened 50% by the user). Stance by foot position (no sliding, sole flat at 0), swing through the brief's leg shapes by joint angle (monotone blend), pelvis bob -0.35/+0.12 m with a contact jolt, 12° lean, ±4° yaw, ±1.5° roll, 0.07 m side shift (user: less hip sway than the brief's ±7°, ±3°, 0.18 m), heel starts lifting at frame 7 (the ankle's toe-up limit), spine counter-turn, head keeps 30% of the pelvis motion. Pose markers footstep_L (frame 0), footstep_R (15). User decisions: knee limit 80° (override in new_mech_joint_limits.py), elbows 55°, ankle roll limit ±25° (feet closer than the rest stance). Differences from the brief: no spine split, neck, toe or piston bones; the pelvis must drop 0.33 m for the contact reach, so loading and midstance knees bend about 59° and 56° (brief 38° and 30°); swing clearance 1.41 m (brief 1.42). In Blender each NLA strip repeats to fill 10 s (frames 0 to 299). Start and stop: `tools/blender/new_mech_run_transitions.py` (reuses the run script's leg math). `biped_run_start` (48 frames): crouch from Idle (knees 25°, lean 20°), left step 1 (4.13 m, right foot planted, no flight), right step 2 (13-frame left stance, short flight), step 3 at full speed; frame 48 = biped_run_full frame 0 exactly; body speed rises from 0 to full by frame 33; lean 20° to 12°. `biped_run_stop` (48 frames, brief 45: the body needs that long to slow over the skidding foot): starts on biped_run_full frame 0; right foot brakes 3.54 m ahead at 12 (knee 52°, lean back 12°, pelvis down 0.71 m), skids until 24, left stutter step at 24 (lean back 6°), right foot steps in at 36, overshoot forward 4°, settles to the Idle stance (feet on their idle places) at 48. Pose markers: start footstep_L 17, footstep_R 33; stop footstep_R 12, skid_start 12, skid_end 24, footstep_L 24, footstep_R 36. Planted feet lift the heel when the shin leans past the ankle's toe-up range, swinging feet keep 0.24 m sole clearance where the knee limit allows. A last pass lifts any foot that still dips below the ground. `biped_run_stop_akira` (100 frames, Akira power slide): starts on biped_run_full frame 0; the right leg swings out and plants wide at 8 (footstep_R, slide_start); both feet skid while the body turns 90° right about the root by frame 22 (left side leads, wide stance, crouch 0.65 m, lean back 12° against the slide, left arm out, right arm trailing, head keeps looking down the slide and follows most of the lean); slide_end at 30; turns back to the original direction with two pivot steps (right 40, the planted foot turns on the spot; left 50) while rising; 3 small steps forward (58, 68, 78, body speed up to 0.13 m/frame and back to 0); left foot steps in at 88; settles on the Idle pose facing forward at 100 (no root turn needed). Pose markers footstep_* on every contact. The knee poles turn with the body; every other rig action keys them at rest so they cannot stay turned. Ankle roll limit ±35°. .glb export: next step.
- Godot export later: export glTF with all actions; play Head_Scan on the head bone on top of the body animation (AnimationTree blend with a head-only filter).

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

## Hand grip system (approved 2026-10-08, not built yet)

- Hands are rigged: each finger segment is a separate rigid mesh parented to its own bone (3 segments per finger, 2 per thumb).
- Each weapon resource has `grip_pose` (String, for example "rifle", "pistol", "blade", "open").
- Each weapon scene has a `socket_grip` Marker3D. The palm aligns to it. `socket_grip` replaces `GripRight` (user decision): the right arm IK target and every code that reads `GripRight` move to `socket_grip`.
- When MechAssembler attaches a weapon, the arm's hand plays the matching grip pose.
- New weapons need only a new `grip_pose` value in the .tres file. No code changes.
- Step 1 (the note's "Phase 3"): add `grip_pose` and `socket_grip` with placeholder box fingers.
- Step 2 (the note's "Phase 8"): replace them with rigged .glb arms. Grip poses are made in Blender and exported with the arm.
- Medium: its claws are one AI-made mesh per hand, so they must be cut into finger segments (3 per finger, 2 per thumb) and rigged before they can take grip poses.

## Architecture rules

- Parts, weapons, mods, plates, and skills are Godot Resources (.tres) in `/data`. New parts need no code changes.
- Each part is its own scene with Marker3D sockets (example: `socket_head`, `socket_arm_L`, `socket_weapon`). MechAssembler attaches parts by socket. Placeholder meshes are replaced with .glb models later, with no code changes.
- MechAssembler builds a mech from a Loadout resource.
- StatCalculator computes final stats from parts, plates, mods, and pilot skills.
- Small scripts, one job per script.
- Debug HUD: total weight, load ratio, speed, HP of each part.
- Rendering: Forward+ renderer. PBR StandardMaterial3D, SDFGI, SSAO, SSR, volumetric fog, glow, AgX tonemap, TAA.
- Graphics settings menu (low, medium, high). Built in Phase 5 (see Garage).
- After each phase, explain in plain English what was built.

## Project layout

```
data/               Part, weapon, mod, plate and loadout resources (.tres): parts/warden, parts/kestrel, parts/bulwark, weapons, plates, mods, loadouts, garage_catalog.tres.
materials/          Shared materials. warden/ and rx78/ hold the mech colors, textures/ the noise textures (Phase 8), asphalt.tres.
shaders/            greybox_grid.gdshader (1 m and 10 m grid lines), mech_panel.gdshader, building_facade.gdshader, asphalt.gdshader (Phase 8).
scenes/levels/      test_map.tscn (main scene).
scenes/parts/warden/ Warden part models (head, core, arm_l, arm_r, legs, booster).
scenes/mech/        player_mech.tscn (Warden frame, weapons and logic), granpa_gundam.tscn (saved RX-78-2 style model).
tools/mech_gen/     Python generators for the mech models and rifles (Godot ignores this folder).
scenes/props/       greybox_block, car, lamppost, person, box_truck (8 m), semi_truck (16.5 m).
scenes/ui/          debug_hud.tscn.
scripts/data/       Part, plate, mod, loadout resource classes, garage_catalog.gd, mech_stats.gd, stat_calculator.gd.
scripts/mech/       part_look.gd and plate_mounter.gd (Phase 5), mech.gd (movement), mech_shield.gd (shield lift and speed limit), mech_assembler.gd, mech_stat_applier.gd, mech_input.gd (player input), mech_energy.gd, mech_footsteps.gd,
                    mech_jump_charge.gd, mech_air_steer.gd, mech_landing_recovery.gd, mech_aim.gd (camera target and real mech aim with jitter).
scripts/animation/  shield_pose.gd, shield_mount.gd, dodge_slide_pose.gd, mech_leg_swing.gd, mech_leg_twist.gd, two_bone_ik.gd, weapon_pose.gd, torso_pose.gd,
                    inertia_sway.gd, skid_body_turn.gd, skirt_follow.gd (placeholder animation).
scripts/weapons/    weapon_controller.gd, mech_weapon.gd, gun_weapon.gd, beam_rifle_weapon.gd, blade_weapon.gd, pile_bunker_weapon.gd, missile_pod_weapon.gd, missile.gd, bullet.gd, weapon_recoil.gd, weapon_fire.gd (Granpa Gundam only). Scenes: scenes/weapons/bullet.tscn, scenes/effects/impact_spark.tscn.
scenes/weapons/     heavy_rifle.tscn (Warden), beam_rifle.tscn (Granpa Gundam), long_rifle.tscn (old box rifle). Markers: GripRight, GripLeft, GripLeftRest, GripLeftAim, Muzzle.
scripts/camera/     mech_camera_rig.gd (follow and mouse look), free_aim.gd (free aim box), aim_spring.gd (aim overshoot), camera_shake.gd, camera_ads.gd (aim down sight zoom).
scripts/world/      greybox_block.gd (box with collision, set size in Inspector), mech_spawner.gd (dummy and enemy mechs), destructible_building.gd, building_chunk.gd, falling_chunk.gd, rubble.gd, grid_materials.gd, destructible_prop.gd (4c).
scripts/ui/         debug_hud.gd, aim_reticle.gd, garage.gd, garage_camera.gd, garage_stat_panel.gd, graphics_menu.gd (Phase 5).
scripts/effects/    skid_dust.gd (dust while skidding), brake_thrusters.gd, booster_flames.gd, muzzle_flash.gd, impact_spark.gd, dust_burst.gd (4c).
scripts/ai/         ai_pilot.gd (Phase 4b).
scripts/core/       mouse_capture.gd, group_nodes.gd, loadout_switcher.gd, player_respawner.gd, debug_damage.gd, graphics_settings.gd (autoload, Phase 5).
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

- Closed: upload individual mech parts made with Hunyuan3D, to combine in Blender with proper joints. Done 2026-10-07 as Medium (`models/medium/medium.blend`).
- Closed: "update the dodge hop animation", the user accepted the current hop at the start of Phase 3.

## Decisions log

- Phase 1: Space was a jump plus hold-in-air jets. Replaced in revision 5 by charged jump jets.
- Phase 1: test map ground is 400 x 400 m with invisible walls at the edge. Distance fog hides the edge.
- Phase 1: the camera follows the mouse on a damped spring, so fast aim moves overshoot a little.
- Graphics settings menu goes in Phase 5 (done).
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
- Phase 4b.1: booster fuel blast = 20% of total max HP over the torso. Hit marker (red X): where a shot from the right weapon muzzle really hits (removed in 4c, user request).
- Phase 4b.2: fixed the error after a pauldron fell off (a freed node was read, 20 s after the arm dropped) and the GDScript warnings. A two-hand weapon is held in one hand when the left arm is lost, with an unsteady ring. The ring stays neutral while the mech is down and during the Akira slide.
- Phase 4c: destructible city. Buildings made of blocks (1000 HP) that break into rubble and dust; blocks with no support fall, break and hurt mechs below. Vehicles explode into burnt wrecks, lampposts snap, mechs kick props away or wreck them at boost speed. Backspace reloads the level. Also: hit marker removed, yellow crosshair dot hidden, start camera pitch -24°.
- Phase 5: garage (G): light / medium / heavy part variants (Kestrel, Warden, Bulwark), plates 0 to 3 per part with armor slabs, weapons, up to 3 mods, live stats with the change from the opening build. Graphics presets Low / Medium / High (autoload, saved).
- Phases 6 and 7 skipped for now (user request). Phase 8a: mech metal textures (noise), panel grooves, bolts and worn edges on box armor, building facades with windows, asphalt ground.
- Phase 8a.2: CC0 concrete and asphalt (Poly Haven), thinner fog. Phase 8b: hit reactions, foot planting IK while walking and running, idle motion, stepping when turning in place.
- Phase 8b.1: no ground clipping: ankle pivots with foot leveling and ground clamp (feet, knees, legs), body rests on the ground in falls, weapon lifts out of the ground.
- After 8b.1: enemy AI searches for a hidden target. The current Warden saved as OG Mech (scene and loadout).
- Custom mech pipeline: Blender kit, per-part .glb export, PartRigging for imported parts (tested with a box blockout).
- Recon: first custom Blender mech (slim, blue and black, from the user's reference), key 5 and garage parts.
- Recon Accurate: closer model of the same reference (shaped plates), key 6 and garage parts.
- Recon Sleek: smooth, slim version of Recon Accurate, key 7 and garage parts. The user did not like it: next step is Blender MCP on the user's PC with image-to-3D.
- Recon Gen: first generated mech (Hunyuan3D model of the reference, fitted and split with Blender MCP), key 8 and garage parts.
- Blender MCP connected on the user's PC (Claude Desktop, mcp-for-blender with Python 3.12). Recon Sheet: built from the user's part sheet, key 9 and garage parts.
- Urban map Checkpoint 1: urban_small map (default scene), BuildingDef/MaterialDef/PropDef data, BuildingGenerator, props with mech contact reactions, CC0 textures, decals, lighting, LightmapGI for the ground.
- Mech frames: each mech can have its own joint layout (MechFrame on legs, core and arms). Recon Sheet rebuilt from the user's three views on its own frame.
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
- 2026-10-08: hand grip system approved (see Hand grip system): weapon `grip_pose` and `socket_grip`; `socket_grip` replaces `GripRight`. Recorded only, not built yet.
