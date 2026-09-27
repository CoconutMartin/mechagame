class_name TorsoPose
extends Node
## Leans and turns the torso (upper body above the waist). The legs do not move with it.
## Boost on the ground: lean forward. Aim down sight: turn right and tilt, so the stock sits
## on the right shoulder and the left arm reaches the handguard. Kneel: small forward lean.

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
## Forward lean while kneeling, in degrees.
@export var kneel_lean_deg: float = 8.0
## How fast the boost lean changes.
@export var blend_speed: float = 5.0

var _boost: float = 0.0


func _ready() -> void:
	# Before MechAim and WeaponPose, which use the torso position.
	process_physics_priority = 3


func _physics_process(delta: float) -> void:
	var boosting_on_ground := mech.is_boosting and mech.is_on_floor()
	_boost = lerpf(_boost, 1.0 if boosting_on_ground else 0.0, 1.0 - exp(-blend_speed * delta))
	var aim := smoothstep(0.0, 1.0, weapon_pose.aim_amount)
	var kneel_amount := smoothstep(0.0, 1.0, kneel.amount)
	# Negative X leans forward. Negative Y turns right. Negative Z tilts the head to the right.
	torso.rotation = Vector3(
		-deg_to_rad(boost_lean_deg) * _boost - deg_to_rad(kneel_lean_deg) * kneel_amount,
		-deg_to_rad(aim_twist_deg) * aim,
		-deg_to_rad(aim_tilt_deg) * aim)
