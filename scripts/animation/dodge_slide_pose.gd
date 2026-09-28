class_name DodgeSlidePose
extends Node
## Leg pose for the slides. After a dodge hop landing the mech slides in a deep crouch.
## At the end of every slide (dodge and boost stop, the "Akira slide") the body swings sideways
## (SkidBodyTurn): the lead leg braces out to the side and the other leg folds low.
## Runs after MechLegSwing.

@export var mech: Mech
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
## Upper body node. The crouch lowers it.
@export var upper_body: Node3D
@export var skid_turn: SkidBodyTurn

@export_group("Crouch")
## Front leg hip and knee bend in the slide crouch, in degrees.
@export var front_hip_deg: float = 40.0
@export var front_knee_deg: float = 75.0
## Back leg hip and knee bend in the slide crouch, in degrees.
@export var back_hip_deg: float = 5.0
@export var back_knee_deg: float = 85.0
## Body drop in the slide crouch, in meters.
@export var drop: float = 1.5
@export_group("Akira")
## Lead leg out to the side at the end of the slide, in degrees.
@export var lead_out_deg: float = 12.0
## Lead leg hip and knee bend at the end (braced, nearly straight).
@export var lead_hip_deg: float = 15.0
@export var lead_knee_deg: float = 20.0
## Trail leg hip and knee bend at the end (folded low).
@export var trail_hip_deg: float = 28.0
@export var trail_knee_deg: float = 80.0
@export_group("")
## How fast the pose comes in (1 / seconds).
@export var blend_in_speed: float = 8.0
## How fast the crouch goes away after the slide (1 / seconds). 1.2 = 40% slower than 2.
@export var blend_out_speed: float = 1.2

var _weight: float = 0.0


func _ready() -> void:
	# After MechLegSwing (0) and SkidBodyTurn (2), before the skirts (11).
	process_physics_priority = 3


func _physics_process(delta: float) -> void:
	var sliding := mech.is_brake_skidding
	_weight = move_toward(_weight, 1.0 if sliding else 0.0, (blend_in_speed if sliding else blend_out_speed) * delta)
	hip_left.rotation.z = 0.0
	hip_right.rotation.z = 0.0
	var akira := skid_turn.akira_amount
	if _weight <= 0.0 and akira <= 0.0:
		return
	var w := smoothstep(0.0, 1.0, _weight)
	# Lead leg = the leg on the side the mech slides to after the body swings sideways.
	var side := skid_turn.akira_side
	var lead_is_right := side > 0.0
	var lead_hip := hip_right if lead_is_right else hip_left
	var lead_knee := knee_right if lead_is_right else knee_left
	var trail_hip := hip_left if lead_is_right else hip_right
	var trail_knee := knee_left if lead_is_right else knee_right
	# Slide crouch (left leg front), then the Akira pose on top.
	var crouch := {
		hip_left: deg_to_rad(front_hip_deg), knee_left: -deg_to_rad(front_knee_deg),
		hip_right: deg_to_rad(back_hip_deg), knee_right: -deg_to_rad(back_knee_deg),
	}
	var akira_pose := {
		lead_hip: deg_to_rad(lead_hip_deg), lead_knee: -deg_to_rad(lead_knee_deg),
		trail_hip: deg_to_rad(trail_hip_deg), trail_knee: -deg_to_rad(trail_knee_deg),
	}
	# Boost stop slides have no crouch: the Akira pose blends over the normal skid pose.
	var weight := maxf(w, akira)
	for joint: Node3D in crouch:
		var start: float = crouch[joint] if w > 0.0 else joint.rotation.x
		var angle: float = lerpf(start, akira_pose[joint], akira)
		joint.rotation.x = lerpf(joint.rotation.x, angle, weight)
	# Right leg out = positive Z turn, left leg out = negative.
	lead_hip.rotation.z = deg_to_rad(lead_out_deg) * (1.0 if lead_is_right else -1.0) * akira
	upper_body.position.y -= drop * weight
