class_name SkeletalBrakeStop
extends SkeletonModifier3D
## Power brake at the end of a full run or boost (user request 2026-10-13: replaces the sideways Akira
## stop). The mech keeps facing forward:
##   Plant (plant_time): the lead leg shoots forward, heel down, toes up; the rear leg folds under; the
##   hips drop; the torso leans back against the momentum and the body drifts a little to the lead side.
##   Slide (Mech's Akira slide speed curve, to a stop): the brace holds and judders with the speed;
##   near the end the momentum throws the torso forward.
##   Recover (recover_time): the torso springs back upright, the hips rise and the rear leg steps up
##   beside the lead leg.
## Legs are placed with a two-bone IK on the ground, so the feet stay planted. Runs after the arm rig
## (the arms keep the weapon; SkeletalArmRig.refresh_torso moves the torso frame with the body).
## Skeleton space: +Y up, +Z forward, +X left (the Model faces +Z).

@export var model: Node3D
@export var mech: Mech
@export var arm_rig: SkeletalArmRig
## Optional. Gets a heavy step at the heel slam and when the rear foot lands (camera shake, sound).
@export var locomotion: SkeletalLocomotion

@export_group("Plant")
## Seconds to get into the brace.
@export var plant_time: float = 0.25
## Hip drop at full brace, in meters.
@export var drop: float = 1.6
## Lead foot forward and rear foot back from the rest place, in meters.
@export var lead_forward: float = 2.4
@export var rear_back: float = 1.9
## Lead toes up (heel digs in), degrees.
@export var lead_toe_up_deg: float = 22.0
## Torso lean back against the momentum, degrees.
@export var lean_back_deg: float = 16.0
## Hips tip back, degrees.
@export var hips_back_deg: float = 8.0
## Body drift toward the lead side, degrees.
@export var drift_deg: float = 14.0
## Torso twist toward the lead side, degrees.
@export var twist_deg: float = 10.0

@export_group("Slide")
## Slide progress where the torso starts to swing forward, and the forward lean at the stop (degrees).
@export var swing_start: float = 0.55
@export var swing_forward_deg: float = 14.0
## Judder at full speed: hip shake (meters) and torso roll (degrees), and its speed (shakes per second).
@export var judder_drop: float = 0.06
@export var judder_roll_deg: float = 1.5
@export var judder_speed: float = 9.0

@export_group("Recover")
## Seconds from the stop to the normal pose (a move key does not make it faster).
@export var recover_time: float = 1.5
## The rear foot's step: start and end (0 to 1 of the recovery) and lift height (meters).
@export var step_start: float = 0.15
@export var step_end: float = 0.6
@export var step_lift: float = 0.7
## Forward lean spring after the stop: speed (swings per second) and damping (per second).
@export var spring_frequency: float = 1.4
@export var spring_damping: float = 4.0

var _active: bool = false
var _time: float = 0.0
var _after: float = -1.0
## +1 = left leg leads, -1 = right leg leads.
var _lead: float = 1.0
var _start_speed: float = 1.0
var _noise := FastNoiseLite.new()
var _bones := {}
var _rest := {}


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)
	_noise.frequency = 1.0


func _physics_process(delta: float) -> void:
	if not _active and mech.akira_skid and mech.is_skidding:
		_active = true
		_time = 0.0
		_after = -1.0
		_lead = mech.skid_side
		_start_speed = maxf(mech.get_horizontal_speed(), 1.0)
	if not _active:
		mech.akira_playing = false
		return
	var before := _time
	_time += delta
	if locomotion != null and before < plant_time and _time >= plant_time:
		locomotion.footstep.emit(1.0)  # Heel slam.
	var cancelled := not mech.is_on_floor() or mech.is_fallen or mech.is_wrecked \
			or (mech.is_skidding and not mech.akira_skid)
	if _after < 0.0 and not mech.is_skidding:
		_after = 0.0
	elif _after >= 0.0:
		_after += delta
		var landing := step_end * recover_time
		if locomotion != null and _after - delta < landing and _after >= landing:
			locomotion.footstep.emit(0.7)  # The rear foot lands.
	if cancelled or _after >= recover_time:
		_active = false
	# SkidBodyTurn keeps the body straight while this plays.
	mech.akira_playing = _active


func _process_modification_with_delta(_delta: float) -> void:
	if not _active:
		return
	var skeleton := get_skeleton()
	if _bones.is_empty():
		_setup(skeleton)
	var plant := smoothstep(0.0, plant_time, _time)
	var recover := clampf(_after / recover_time, 0.0, 1.0) if _after >= 0.0 else 0.0
	var hold := 1.0 - smoothstep(0.2, 1.0, recover)
	var weight := plant * (1.0 - smoothstep(0.55, 1.0, recover))
	var speed := clampf(mech.get_horizontal_speed() / _start_speed, 0.0, 1.0) if _after < 0.0 else 0.0
	var progress := mech.get_skid_progress() if _after < 0.0 else 1.0

	# Torso pitch (+ = forward): back against the momentum, forward swing near the stop, then a spring.
	var pitch := -lean_back_deg * plant
	pitch = lerpf(pitch, swing_forward_deg, smoothstep(swing_start, 1.0, progress))
	if _after >= 0.0:
		pitch = swing_forward_deg * exp(-spring_damping * _after) * cos(TAU * spring_frequency * _after)
	var judder := _noise.get_noise_1d(_time * judder_speed) * speed
	var hips_drop := (drop * hold + judder * judder_drop) * plant
	var yaw := deg_to_rad(drift_deg) * _lead * plant * hold
	var body := Basis(Vector3.UP, yaw)

	# Feet (ankle places): lead forward, rear back; the rear foot steps up during the recovery.
	var step := smoothstep(step_start, step_end, recover)
	var lead_side := "L" if _lead > 0.0 else "R"
	var rear_side := "R" if _lead > 0.0 else "L"
	var feet := {}
	feet[lead_side] = _rest["foot_" + lead_side].origin + Vector3(0.0, 0.0, lead_forward * hold)
	var rear_z := lerpf(-rear_back, 0.0, step) * plant
	var lift := sin(PI * step) * step_lift if step > 0.0 and step < 1.0 else 0.0
	feet[rear_side] = _rest["foot_" + rear_side].origin + Vector3(0.0, lift, rear_z)

	# Pelvis: drops and tips back; the whole body drifts to the lead side.
	var pelvis_rest: Transform3D = _rest["pelvis"]
	var pelvis_basis := body * Basis(Vector3.RIGHT, deg_to_rad(-hips_back_deg * plant * hold)) * pelvis_rest.basis
	var pelvis_global := Transform3D(pelvis_basis, pelvis_rest.origin + Vector3(0.0, -hips_drop, 0.0))
	_set_global(skeleton, "pelvis", pelvis_global, weight, true)

	# Torso: pitch, twist to the lead side, judder roll.
	var torso_rest: Transform3D = _rest["torso"]
	var torso_turn := body * Basis(Vector3.UP, deg_to_rad(twist_deg) * _lead * plant * hold) \
			* Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.FORWARD, deg_to_rad(judder * judder_roll_deg))
	var torso_global := Transform3D(torso_turn * torso_rest.basis, pelvis_global * (pelvis_rest.affine_inverse() * torso_rest.origin))
	_set_global(skeleton, "torso", torso_global, weight, false)

	for side in ["L", "R"]:
		var foot_target: Vector3 = body * (feet[side] as Vector3)
		_solve_leg(skeleton, side, pelvis_global, foot_target, body, weight, side == lead_side)
	if arm_rig != null:
		arm_rig.refresh_torso()


func _setup(skeleton: Skeleton3D) -> void:
	for name in ["root", "pelvis", "torso", "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]:
		_bones[name] = skeleton.find_bone(name)
		_rest[name] = skeleton.get_bone_global_rest(_bones[name])


## Sets a bone's skeleton-space pose (blended with its pose now). position: also set its place.
func _set_global(skeleton: Skeleton3D, name: String, global: Transform3D, weight: float, position: bool) -> void:
	var bone: int = _bones[name]
	var parent := skeleton.get_bone_parent(bone)
	var parent_global := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var local := parent_global.affine_inverse() * global
	var now := skeleton.get_bone_pose(bone)
	skeleton.set_bone_pose_rotation(bone, now.basis.get_rotation_quaternion().slerp(local.basis.get_rotation_quaternion(), weight))
	if position:
		skeleton.set_bone_pose_position(bone, now.origin.lerp(local.origin, weight))


## Two-bone leg IK: thigh and shin reach the ankle target, the knee forward; the foot stays level
## (the lead foot's toes up).
func _solve_leg(skeleton: Skeleton3D, side: String, pelvis_global: Transform3D, ankle: Vector3, body: Basis,
		weight: float, lead: bool) -> void:
	var thigh_rest: Transform3D = _rest["thigh_" + side]
	var shin_rest: Transform3D = _rest["shin_" + side]
	var foot_rest: Transform3D = _rest["foot_" + side]
	var pelvis_rest: Transform3D = _rest["pelvis"]
	var hip := pelvis_global * (pelvis_rest.affine_inverse() * thigh_rest.origin)
	var upper := thigh_rest.origin.distance_to(shin_rest.origin)
	var lower := shin_rest.origin.distance_to(foot_rest.origin)
	var to_ankle := ankle - hip
	var reach := clampf(to_ankle.length(), absf(upper - lower) + 0.01, upper + lower - 0.01)
	var down := to_ankle.normalized()
	# Knee bend plane: forward (the body's +Z) out of the hip-to-ankle line.
	var forward := body * Vector3.BACK
	var bend := (forward - down * forward.dot(down)).normalized()
	var cos_hip := (upper * upper + reach * reach - lower * lower) / (2.0 * upper * reach)
	var knee := hip + down * (upper * cos_hip) + bend * (upper * sqrt(maxf(1.0 - cos_hip * cos_hip, 0.0)))
	var ankle_now := hip + down * reach
	# Thigh: rest direction to the knee; shin: rest direction to the ankle.
	var thigh_dir_rest := (shin_rest.origin - thigh_rest.origin).normalized()
	var thigh_basis := Basis(Quaternion(body * thigh_dir_rest, (knee - hip).normalized())) * body * thigh_rest.basis
	var thigh_global := Transform3D(thigh_basis, hip)
	_set_global(skeleton, "thigh_" + side, thigh_global, weight, false)
	var shin_dir_rest := (foot_rest.origin - shin_rest.origin).normalized()
	var shin_dir_now := thigh_basis * (thigh_rest.basis.inverse() * shin_dir_rest)
	var shin_basis := Basis(Quaternion(shin_dir_now.normalized(), (ankle_now - knee).normalized())) \
			* thigh_basis * (thigh_rest.basis.inverse() * shin_rest.basis)
	_set_global(skeleton, "shin_" + side, Transform3D(shin_basis, knee), weight, false)
	var toe := deg_to_rad(lead_toe_up_deg) if lead else 0.0
	var foot_basis := body * Basis(Vector3.RIGHT, -toe) * foot_rest.basis
	_set_global(skeleton, "foot_" + side, Transform3D(foot_basis, ankle_now), weight, false)
