class_name LungeLeapPose
extends Node
## Shows a melee lunge (the pile bunker charge) as big leaps forward: the body lifts in an arc and
## the legs spread (one forward, one back), with a crouch at each take-off and landing. The legs
## change over for each leap. Visual only: the Mech moves on the ground. Runs after MechLegSwing
## and DodgeSlidePose.

signal leap_landed

@export var mech: Mech
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
## Upper body node (holds the legs too). The leap lifts it.
@export var upper_body: Node3D

## Leap height in meters, and the most a leap can be for its length (height = length x this).
@export var leap_height: float = 2.2
@export var height_per_length: float = 0.3
@export_group("Legs")
## Crouch at take-off and landing: hip and knee bend of both legs, in degrees.
@export var crouch_hip_deg: float = 20.0
@export var crouch_knee_deg: float = 45.0
## Leg spread at the top of the leap, in degrees.
@export var front_hip_deg: float = 55.0
@export var front_knee_deg: float = 70.0
@export var back_hip_deg: float = -35.0
@export var back_knee_deg: float = 40.0
## Body drop in the crouch, in meters.
@export var crouch_drop: float = 0.8
@export_group("")
## How fast the pose goes away after the lunge (1 / seconds).
@export var blend_out_speed: float = 5.0

var _weight: float = 0.0
var _last_leap: int = -1


func _ready() -> void:
	# After MechLegSwing (0) and DodgeSlidePose (3).
	process_physics_priority = 4


func _physics_process(delta: float) -> void:
	var active := mech.is_lunging and mech.lunge_leaps > 0
	if active:
		_weight = 1.0
	else:
		_weight = move_toward(_weight, 0.0, blend_out_speed * delta)
		if _last_leap >= 0:
			leap_landed.emit()
			_last_leap = -1
	if _weight <= 0.0:
		return
	var leaps := maxi(mech.lunge_leaps, 1)
	var progress := mech.get_lunge_progress() * leaps
	var leap := mini(int(progress), leaps - 1)
	if active and leap != _last_leap:
		if _last_leap >= 0:
			leap_landed.emit()
		_last_leap = leap
	# 0 at the take-off, 1 at the landing of this leap. After the lunge: landing crouch.
	var p := progress - leap if active else 1.0
	var arc := sin(p * PI)
	var length := mech.get_lunge_distance() / leaps
	var height := minf(leap_height, length * height_per_length)
	# Left leg forward first (the shield side leads), then the legs change over.
	var left_front := leap % 2 == 0
	var front_hip := hip_left if left_front else hip_right
	var front_knee := knee_left if left_front else knee_right
	var back_hip := hip_right if left_front else hip_left
	var back_knee := knee_right if left_front else knee_left
	var crouch := 1.0 - arc
	var pose := {
		front_hip: lerpf(deg_to_rad(crouch_hip_deg), deg_to_rad(front_hip_deg), arc),
		front_knee: -lerpf(deg_to_rad(crouch_knee_deg), deg_to_rad(front_knee_deg), arc),
		back_hip: lerpf(deg_to_rad(crouch_hip_deg), deg_to_rad(back_hip_deg), arc),
		back_knee: -lerpf(deg_to_rad(crouch_knee_deg), deg_to_rad(back_knee_deg), arc),
	}
	for joint: Node3D in pose:
		joint.rotation.x = lerpf(joint.rotation.x, pose[joint], _weight)
	upper_body.position.y += (height * arc - crouch_drop * crouch * crouch) * _weight
