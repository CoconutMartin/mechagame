class_name WeaponData
extends PartData
## A weapon or a hand shield. The scene is the weapon model; its root has a MechWeapon script
## (or it is a part-style scene with socket groups for a shield).
## Solid guns (rifle, missiles) use ammo and reloads. Beam weapons (sniper beam, blade) use heat:
## each use adds heat; at full heat the weapon overheats and must cool down to zero (the "reload").

enum Kind { GUN, BEAM_RIFLE, BLADE, MISSILE_POD, SHIELD }
enum Slot { ARM, BACK }

@export var kind: Kind = Kind.GUN
@export var slot: Slot = Slot.ARM
## Held with both hands (right arm weapon only). RMB aims down sight, LMB fires.
@export var two_handed: bool = false

@export_group("Firing")
## Shots per second.
@export var fire_rate: float = 0.5
## Damage per hit (used in Phase 4).
@export var damage: float = 100.0
## Projectile speed in m/s (guns and missiles).
@export var projectile_speed: float = 400.0
## Random spread cone, in degrees.
@export var spread_deg: float = 0.4
## Range in meters (beams and lock-on).
@export var range_m: float = 1500.0

@export_group("Recoil")
## Aim kick per shot, in degrees (FreeAim).
@export var recoil_up_deg: float = 2.0
@export var recoil_side_deg: float = 1.0
## Weapon model kick back per shot, in meters, and muzzle climb in degrees (WeaponRecoil).
@export var model_kick_back: float = 0.7
@export var model_kick_up_deg: float = 10.0
## Camera shake per shot.
@export var shake_trauma: float = 0.052
@export var shake_kick: float = 0.078

@export_group("Ammo")
## Shots before a reload (guns and missiles).
@export var magazine: int = 12
## Reload time in seconds.
@export var reload_time: float = 3.5

@export_group("Heat")
## Heat added per use (beam weapons). Full heat is 100.
@export var heat_per_use: float = 34.0
## Heat lost per second while not overheated.
@export var heat_cooling: float = 20.0
## Heat lost per second while overheated. The weapon works again at zero heat.
@export var overheat_cooling: float = 25.0

@export_group("Lock-on")
## Half size of the lock box around the mech aim, in degrees (missiles).
@export var lock_box_deg: float = 7.0
## Seconds to lock one target (divided by the head lock-on speed).
@export var lock_time: float = 0.5
## Missile turn speed in degrees per second.
@export var missile_turn_deg: float = 110.0

@export_group("Blade")
## Lunge length (m), lunge speed (m/s) and energy cost of one lunge slash.
@export var lunge_distance: float = 16.0
@export var lunge_speed: float = 32.0
@export var lunge_energy: float = 20.0
## Slash reach in meters (hit check in front of the mech).
@export var slash_reach: float = 11.0

@export_group("Pose")
## Weapon rest pose in torso space (right arm weapons).
@export var rest_transform: Transform3D = Transform3D.IDENTITY
## Stock position in the aim pose, in torso space.
@export var aim_anchor: Vector3 = Vector3.ZERO
## Elbow directions (right arm) at rest and aimed.
@export var right_pole_rest: Vector3 = Vector3(0.4, -1.0, 0.5)
@export var right_pole_aim: Vector3 = Vector3(0.4, -1.0, 0.5)
## Left elbow directions for two-handed weapons.
@export var left_pole_rest: Vector3 = Vector3(-1.0, -0.4, 0.3)
@export var left_pole_aim: Vector3 = Vector3(-0.3, -1.0, 0.0)
## Torso turn to the right and tilt while aiming (two-handed, shouldered weapons), in degrees.
@export var aim_twist_deg: float = 0.0
@export var aim_tilt_deg: float = 0.0
## Camera zoom while aiming (two-handed weapons). 0 = no zoom.
@export var zoom_fov: float = 0.0

@export_group("Shield")
## Shield front area in m². A bigger shield slows the mech more while it is up.
@export var shield_area_m2: float = 0.0
## Shield model scale.
@export var shield_scale: float = 1.2
