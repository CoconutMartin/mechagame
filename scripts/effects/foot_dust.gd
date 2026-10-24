class_name FootDust
extends Node
## A small, thin dust puff where a foot lands (user request 2026-10-24). Walking steps come from
## SkeletalLocomotion.footstep (phase 0 = the left foot lands, 0.5 = the right foot); a jump landing
## (Mech.landed) puffs under both feet, bigger after a faster fall. Uses DustBurst (PixelSmoke look).

@export var mech: Mech
@export var locomotion: SkeletalLocomotion
## The rigged model; the Skeleton3D is found under it.
@export var model: Node3D
@export var foot_bones: PackedStringArray = ["foot_L", "foot_R"]
## Puff box size at a full strength step, in meters (x and z across the ground, y up).
@export var step_size: Vector3 = Vector3(2.0, 0.3, 2.0)
## Puff opacity at a full strength step (1 = solid). Thin: 0.25.
@export var step_alpha: float = 0.25
## Dust particles per step puff (DustBurst has 28 for a building chunk).
@export var step_amount: int = 10
## Fastest rise of the step dust, in m/s (DustBurst: 5).
@export var step_rise_speed: float = 2.0
## Seconds a step puff lasts.
@export var step_lifetime: float = 1.6
## Landings: puff size and opacity = the step values x (1 + fall speed / this value), up to landing_max_scale.
@export var landing_fall_speed: float = 15.0
## Largest landing puff = the step puff x this value.
@export var landing_max_scale: float = 2.5

var _skeleton: Skeleton3D
var _bones: Array[int] = []


func _ready() -> void:
	if model != null:
		_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton != null:
		for bone_name in foot_bones:
			_bones.append(_skeleton.find_bone(bone_name))
	if locomotion != null:
		locomotion.footstep.connect(_on_footstep)
	if mech != null:
		mech.landed.connect(_on_landed)


func _on_footstep(strength: float) -> void:
	var phase := locomotion.get_phase()
	# The step just crossed phase 0 (left) or 0.5 (right).
	var side := 0 if phase < 0.25 or phase >= 0.75 else 1
	_puff(side, strength)


func _on_landed(fall_speed: float) -> void:
	if mech.is_wrecked:
		return
	var scale := minf(1.0 + fall_speed / maxf(landing_fall_speed, 0.1), landing_max_scale)
	for side in foot_bones.size():
		_puff(side, scale)


func _puff(side: int, scale: float) -> void:
	var point := _foot_point(side)
	var size := Vector3(step_size.x * scale, step_size.y, step_size.z * scale)
	var dust := DustBurst.create(mech.get_parent(), point, size, minf(step_alpha * scale, 1.0))
	if dust == null:
		return
	# After _ready (DustBurst sets the building chunk look there), before it starts (deferred).
	dust.amount = maxi(int(step_amount * scale), 1)
	dust.lifetime = step_lifetime
	dust.spread = 90.0
	dust.initial_velocity_min = step_rise_speed * 0.3
	dust.initial_velocity_max = step_rise_speed
	dust.gravity = Vector3(0.0, -0.3, 0.0)


## The foot bone right over the ground (the mech origin is at the soles).
func _foot_point(side: int) -> Vector3:
	var ground := mech.global_position
	if side >= _bones.size() or _bones[side] < 0:
		return ground
	var foot := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bones[side]).origin
	return Vector3(foot.x, ground.y + step_size.y * 0.5, foot.z)
