class_name TorsoPose
extends Node
## Leans and turns the torso (upper body above the waist). The legs do not move with it.
## Aim: the torso twists toward the mech aim (Mech.get_torso_twist, inside the twist limits).
## Boost on the ground: lean forward. Aim down sight: turn right and tilt, so the stock sits
## on the right shoulder and the left arm reaches the handguard. Kneel and landing: forward lean.

@export var mech: Mech
@export var torso: Node3D
@export var weapon_pose: WeaponPose
@export var kneel: MechKneel
## Forward lean while boosting on the ground, in degrees.
@export var boost_lean_deg: float = 35.0
## Torso turn to the right while aiming, in degrees. Brings the left shoulder forward.
@export var aim_twist_deg: float = 30.0
## Sideways tilt toward the rifle while aiming, in degrees.
@export var aim_tilt_deg: float = 6.0
## Backward lean while skidding to a stop after a boost, in degrees.
@export var skid_lean_back_deg: float = 15.0
## After the skid, the torso sways forward and back on a spring before it is upright.
## Sway speed (swings per second). Lower = slower recovery.
@export var skid_recover_frequency: float = 0.9
## Sway damping. Lower = more swings. 1.0 = no swing past upright.
@export_range(0.05, 1.0) var skid_recover_damping: float = 0.3
## Random side sway when a skid starts: the torso rolls to a random side (left or right)
## by a random amount between these values (degrees), then sways back to upright on the same spring.
@export var skid_side_sway_min_deg: float = 3.0
@export var skid_side_sway_max_deg: float = 7.0
## Forward lean while running, in degrees.
@export var run_lean_deg: float = 12.0
## Forward lean after a landing from landing_lean_full_height or higher, in degrees.
## Lower falls lean less, in proportion. Fades out with the landing delay.
@export var landing_lean_deg: float = 30.0
## Fall height (meters) that gives the full landing lean.
@export var landing_lean_full_height: float = 9.0
## Forward lean while kneeling, in degrees.
@export var kneel_lean_deg: float = 8.0
## How fast the boost lean changes.
@export var blend_speed: float = 5.0

var _boost: float = 0.0
var _run: float = 0.0
## Skid lean in degrees (positive = back), on a spring.
var _skid_lean := AimSpring.new(0.0)
## Skid side roll in degrees (positive = head to the left), on a spring.
var _skid_roll := AimSpring.new(0.0)
var _skid_roll_target: float = 0.0
var _was_skidding: bool = false


func _ready() -> void:
	# After the Mech turns (priority 0), before MechAim and WeaponPose, which use the torso position.
	process_physics_priority = 3


func _physics_process(delta: float) -> void:
	var boosting_on_ground := mech.is_boosting and mech.is_on_floor()
	var blend := 1.0 - exp(-blend_speed * delta)
	_boost = lerpf(_boost, 1.0 if boosting_on_ground else 0.0, blend)
	_run = lerpf(_run, 1.0 if mech.is_running else 0.0, blend)
	var skid_target := skid_lean_back_deg if mech.is_skidding else 0.0
	_skid_lean.update(skid_target, skid_recover_frequency, skid_recover_damping, 90.0, delta)
	if mech.is_skidding and not _was_skidding:
		# New skid: roll to the skid side by a random amount.
		_skid_roll_target = mech.skid_side * randf_range(skid_side_sway_min_deg, skid_side_sway_max_deg)
	_was_skidding = mech.is_skidding
	var roll_target := _skid_roll_target if mech.is_skidding else 0.0
	_skid_roll.update(roll_target, skid_recover_frequency, skid_recover_damping, 90.0, delta)
	var aim := smoothstep(0.0, 1.0, weapon_pose.aim_amount)
	var kneel_amount := smoothstep(0.0, 1.0, kneel.amount)
	var fall_ratio := clampf(mech.landing_recovery.fall_height / landing_lean_full_height, 0.0, 1.0)
	var landing := sin(mech.landing_recovery.get_fraction() * PI * 0.5) * fall_ratio
	# Negative X leans forward. Negative Y turns right. Negative Z tilts the head to the right.
	var lean := deg_to_rad(boost_lean_deg) * _boost + deg_to_rad(run_lean_deg) * _run
	lean = maxf(lean, deg_to_rad(kneel_lean_deg) * kneel_amount)
	lean = maxf(lean, deg_to_rad(landing_lean_deg) * landing)
	# Positive X leans back.
	lean -= deg_to_rad(_skid_lean.value)
	torso.rotation = Vector3(
		-lean,
		mech.get_torso_twist() - deg_to_rad(aim_twist_deg) * aim,
		-deg_to_rad(aim_tilt_deg) * aim + deg_to_rad(_skid_roll.value))
