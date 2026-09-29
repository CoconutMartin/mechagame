class_name FallPose
extends Node
## Arm and leg pose while a living mech falls over and gets up (MechFall runs the body tilt).
##   Fall: the knees buckle, the arms reach out toward the ground to break the fall.
##   Impact: the elbows give to take the hit.
##   Roll: arms back to a standby pose close to the body, legs straight and together.
##   Get up: arms push the body up, one knee comes under the body, then the legs straighten.
## Joints move toward their targets on a smooth spring, so the pose changes look soft.
## A dead mech uses PowerDownPose instead.

@export var mech: Mech
@export var mech_fall: MechFall
@export var shoulder_left: Node3D
@export var shoulder_right: Node3D
@export var elbow_left: Node3D
@export var elbow_right: Node3D
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
@export var torso: Node3D
## Holds the torso and the legs. It drops when the legs bend.
@export var upper_body: Node3D

## How fast the joints follow their targets (1 / seconds).
@export var follow_speed: float = 7.0
## Arms reaching out: how far down from straight ahead, in degrees; elbow bend.
@export var reach_down_deg: float = 20.0
@export var reach_elbow_deg: float = 15.0
## Elbow bend when the arms take the hit, and in the standby pose, in degrees.
@export var impact_elbow_deg: float = 70.0
@export var standby_elbow_deg: float = 35.0
## Knee buckle at the start of the fall, in degrees (hip, knee).
@export var buckle_hip_deg: float = 15.0
@export var buckle_knee_deg: float = 30.0
## Get up: kneel pose (front leg hip and knee, back leg hip and knee) in degrees.
@export var kneel_front_hip_deg: float = 80.0
@export var kneel_front_knee_deg: float = 95.0
@export var kneel_back_hip_deg: float = 20.0
@export var kneel_back_knee_deg: float = 110.0
@export var thigh_length: float = 2.6
@export var shin_length: float = 2.6

var _active: bool = false


func _ready() -> void:
	# After MechFall (-1) and the other poses.
	process_physics_priority = 12


func _physics_process(delta: float) -> void:
	var down := mech_fall.is_down() and not mech.is_wrecked
	if not down:
		if _active:
			_active = false
		return
	_active = true
	var weight := 1.0 - exp(-follow_speed * delta)
	var targets := _targets()
	for joint: Node3D in targets:
		if joint != null and is_instance_valid(joint):
			var target: Quaternion = (targets[joint] as Basis).get_rotation_quaternion()
			var now := joint.basis.orthonormalized().get_rotation_quaternion()
			joint.basis = Basis(now.slerp(target, weight))
	var drop := _leg_drop(targets)
	upper_body.position.y = lerpf(upper_body.position.y, -drop, weight)


## Target rotations for the joints now, by MechFall state.
func _targets() -> Dictionary:
	var state := mech_fall.state
	var t := mech_fall.state_time
	var reach := _reach_basis()
	var standby := Basis(Vector3.RIGHT, deg_to_rad(10.0))
	var elbow_standby := Basis(Vector3.RIGHT, deg_to_rad(standby_elbow_deg))
	var straight := Basis.IDENTITY
	var result := {torso: Basis.IDENTITY}
	match state:
		MechFall.State.STEPS, MechFall.State.FALL:
			# Knees buckle first, then the arms reach out as the body goes over.
			var reach_amount := clampf(t / (mech_fall.fall_time * 0.6), 0.0, 1.0) if state == MechFall.State.FALL else 0.0
			var arm := standby.slerp(reach, reach_amount)
			var elbow := Basis(Vector3.RIGHT, deg_to_rad(reach_elbow_deg))
			_set_arms(result, arm, elbow)
			_set_legs(result, buckle_hip_deg, buckle_knee_deg, buckle_hip_deg, buckle_knee_deg)
		MechFall.State.IMPACT, MechFall.State.LIE:
			var elbow := Basis(Vector3.RIGHT, deg_to_rad(impact_elbow_deg if state == MechFall.State.IMPACT else reach_elbow_deg + 20.0))
			_set_arms(result, reach, elbow)
			_set_legs(result, 0.0, 5.0, 0.0, 5.0)
		MechFall.State.ROLL:
			_set_arms(result, standby, elbow_standby)
			_set_legs(result, 0.0, 0.0, 0.0, 0.0)
		MechFall.State.GET_UP:
			var p := t / mech_fall.get_up_time
			if p < 0.3:
				# Push up: arms under the chest straighten.
				_set_arms(result, reach, Basis(Vector3.RIGHT, deg_to_rad(lerpf(impact_elbow_deg, 5.0, p / 0.3))))
				_set_legs(result, 0.0, 5.0, 0.0, 5.0)
			elif p < 0.5:
				# One knee comes under the body.
				_set_arms(result, reach, straight)
				_set_legs(result, kneel_front_hip_deg, kneel_front_knee_deg, kneel_back_hip_deg, kneel_back_knee_deg)
			else:
				# Rise: the legs straighten, the arms come back to the sides.
				var rise := smoothstep(0.5, 1.0, p)
				_set_arms(result, reach.slerp(standby, rise), elbow_standby)
				_set_legs(result, lerpf(kneel_front_hip_deg, 0.0, rise), lerpf(kneel_front_knee_deg, 0.0, rise),
						lerpf(kneel_back_hip_deg, 0.0, rise), lerpf(kneel_back_knee_deg, 0.0, rise))
	return result


## Arm rotation (shoulder space: the arm hangs along -Y) that points the arm toward the fall
## direction and a bit down.
func _reach_basis() -> Basis:
	var fall := mech_fall.local_direction
	# The fall direction in torso space (the torso may be turned on the legs).
	var torso_dir := (torso.basis.inverse() * fall) if torso != null else fall
	torso_dir.y = 0.0
	torso_dir = torso_dir.normalized() if torso_dir.length_squared() > 0.001 else Vector3.FORWARD
	var down := deg_to_rad(reach_down_deg)
	var aim := (torso_dir * cos(down) + Vector3.DOWN * sin(down)).normalized()
	return Basis(Quaternion(Vector3.DOWN, aim))


func _set_arms(result: Dictionary, arm: Basis, elbow: Basis) -> void:
	result[shoulder_left] = arm
	result[shoulder_right] = arm
	result[elbow_left] = elbow
	result[elbow_right] = elbow


## Hip and knee bends in degrees. The left leg is the front leg when kneeling.
func _set_legs(result: Dictionary, left_hip: float, left_knee: float, right_hip: float, right_knee: float) -> void:
	result[hip_left] = Basis(Vector3.RIGHT, deg_to_rad(left_hip))
	result[knee_left] = Basis(Vector3.RIGHT, -deg_to_rad(left_knee))
	result[hip_right] = Basis(Vector3.RIGHT, deg_to_rad(right_hip))
	result[knee_right] = Basis(Vector3.RIGHT, -deg_to_rad(right_knee))


## Body drop so the feet stay on the ground with the legs bent (the lower foot counts).
func _leg_drop(targets: Dictionary) -> float:
	var drops: Array[float] = []
	for pair in [[hip_left, knee_left], [hip_right, knee_right]]:
		var hip := _bend(targets.get(pair[0], Basis.IDENTITY))
		var knee := _bend(targets.get(pair[1], Basis.IDENTITY))
		var height := thigh_length * cos(hip) + shin_length * cos(hip + knee)
		drops.append(thigh_length + shin_length - height)
	return minf(drops[0], drops[1])


static func _bend(basis: Basis) -> float:
	return basis.get_euler().x
