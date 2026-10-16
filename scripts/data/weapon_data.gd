class_name WeaponData
extends PartData
## A weapon or a hand shield. The scene is the weapon model; its root has a MechWeapon script
## (or it is a part-style scene with socket groups for a shield).
## Solid guns (rifle, missiles) use ammo and reloads. Beam weapons (sniper beam, blade) use heat:
## each use adds heat; at full heat the weapon overheats and must cool down to zero (the "reload").

enum Kind { GUN, BEAM_RIFLE, BLADE, MISSILE_POD, SHIELD, PILE_BUNKER, FIST, HAMMER }
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
## Bullets per shot (guns). Each pellet has its own spread and does `damage`. One shot uses one ammo.
@export var pellets: int = 1
## Range in meters: the most a beam reaches (and the lock-on range).
@export var range_m: float = 1500.0
## Damage falloff (spec "weapon_damage_falloff_implementation_spec.md", 2026-10-16): full damage up to
## effective_range_m (S), then linear down to falloff_min (M) at falloff_end_m (E), and M beyond E.
## effective_range_m 0 = no falloff. Distance is from the muzzle to the impact point.
@export var effective_range_m: float = 0.0
## End of the falloff (meters); must be more than effective_range_m.
@export var falloff_end_m: float = 0.0
## Part of the damage that is left at and beyond falloff_end_m (0 to 1).
@export_range(0.0, 1.0) var falloff_min: float = 1.0

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

@export_group("Melee")
## Lunge length (m), lunge speed (m/s) and energy cost of one melee charge (blade, pile bunker).
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
## Left hand place with this shield (weapon frame torso space). The arm stays there; the shield is in
## its blocking place all the time (user's arm drawing, 2026-10-12).
@export var shield_hand: Vector3 = Vector3(-2.1, -0.82, -1.95)

## True: the dodge input starts a shield dash instead of a dodge (Hex Shield, user rule 2026-10-16).
@export var blocks_dodge: bool = false


## Damage factor at a distance (meters): 1 up to effective_range_m, then linear down to falloff_min at
## falloff_end_m, and falloff_min beyond it. A weapon without falloff, or with falloff_end_m not more
## than effective_range_m (a warning), gives 1.
func damage_factor(distance: float) -> float:
	if effective_range_m <= 0.0:
		return 1.0
	if falloff_end_m <= effective_range_m:
		push_warning("%s: falloff_end_m (%.1f) must be more than effective_range_m (%.1f); no falloff used"
				% [display_name if display_name != "" else resource_path, falloff_end_m, effective_range_m])
		return 1.0
	if is_nan(distance):
		return 1.0
	var t := clampf((distance - effective_range_m) / (falloff_end_m - effective_range_m), 0.0, 1.0)
	return lerpf(1.0, clampf(falloff_min, 0.0, 1.0), t)
