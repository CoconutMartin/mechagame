class_name MechDodge
extends Node
## Double tap Space for a dodge roll (like Gundam Battle Operation 2): the mech dives toward the chosen
## direction, lands on one shoulder, rolls the whole body over that shoulder one full turn (a diagonal
## shoulder roll), then comes back up onto its feet.
## Directions: A / D = side, W = forward, S or no key = back. Costs energy.
## The dive and roll are visual (the Roll node). The collision body only slides along the ground.

signal dodge_started
signal dodge_ended

@export var mech: Mech
@export var input: MechInput
@export var energy: MechEnergy
@export var landing_recovery: MechLandingRecovery
@export var kneel: MechKneel
## The node that rolls (between Visual and Upper).
@export var roll: Node3D
## Two Space presses closer than this (seconds) start a dodge.
@export var double_tap_window: float = 0.3
## Dodge length, in meters.
@export var distance: float = 23.8
## Dodge time, in seconds. The speed starts high and ends at zero.
@export var duration: float = 1.7
@export var energy_cost: float = 25.0
## When the mech gets up, it springs forward in the dodge direction at this speed (m/s).
## Then it slows down in steps. The torso leans with the push (InertiaSway).
@export var spring_out_speed: float = 7.0
@export_group("Recovery")
## The rise ends in a crouch with the torso leaned toward the dodge direction.
## Then one damped spring brings the body upright (one small swing past upright).
@export var recover_lean_deg: float = 15.0
## Knee crouch in the recovery pose, in degrees of hip bend (knees bend twice as much).
@export var recover_crouch_deg: float = 25.0
## Spring speed (swings per second). Lower = slower recovery.
@export var recover_frequency: float = 1.1
## Spring damping. Lower = more swing past upright.
@export_range(0.05, 1.0) var recover_damping: float = 0.35
@export_group("")

## After the dodge the mech cannot move for this long, in seconds.
@export var recovery_time: float = 0.25
## Height of the body center above the feet, in meters.
@export var body_center_height: float = 5.0
## Gap between the lowest body point and the ground while rolling, in meters.
@export var ground_clearance: float = 0.05
## How far the body leans into the dive, in degrees.
@export var dive_angle_deg: float = 60.0
## How much the roll axis turns toward the dodge direction (0 = straight forward roll,
## higher = more over the shoulder). The roll goes over the right shoulder for this value > 0.
@export var shoulder_amount: float = 0.7
## Parts of the dodge time: the dive ends at dive_end, the roll ends at roll_end, then the body rises.
@export_range(0.0, 1.0) var dive_end: float = 0.3
@export_range(0.0, 1.0) var roll_end: float = 0.8

var is_dodging: bool = false
## World direction of the current dodge.
var direction: Vector3 = Vector3.ZERO

var _clock: float = 0.0
var _last_press: float = -10.0
var _time: float = 0.0
var _recover_left: float = 0.0
## Axis the body leans around for the dive (the top turns toward the dodge direction).
var _dive_axis: Vector3 = Vector3.FORWARD
## Diagonal axis of the shoulder roll.
var _roll_axis: Vector3 = Vector3.FORWARD
## Body box corners in the Roll node space, measured at the dodge start (weapon left out).
var _body_points: Array[Vector3] = []
## How far the lowest body point was below the ground at the dodge start (walk animation), in meters.
## The height plan subtracts it, so the dodge starts and ends at standing height with no jump.
var _start_sink: float = 0.0
var _suppress_jump: bool = false
## Dodge direction in the leg frame (-Z forward, +X right).
var _local_direction: Vector3 = Vector3.BACK
## Body center height along the dodge, sampled at the start and smoothed (plan for idea A).
var _center_path: PackedFloat32Array = PackedFloat32Array()
var _recover := AimSpring.new(0.0)
var _recovering: bool = false


func _ready() -> void:
	# Before the jump charge (-5) and the Mech (0).
	process_physics_priority = -6


## True while dodging or recovering. The mech cannot move, boost, or turn.
func is_busy() -> bool:
	return is_dodging or _recover_left > 0.0


## True while the Space press that started the dodge is still held. The jump charge waits.
func blocks_jump() -> bool:
	return is_busy() or _suppress_jump


## Dodge speed now, in m/s. Starts high and falls steadily to spring_out_speed at the end,
## so the spring forward continues the motion with no gap.
func get_speed() -> float:
	var progress := clampf(_time / duration, 0.0, 1.0)
	var start_speed := 2.0 * distance / duration - spring_out_speed
	return lerpf(start_speed, spring_out_speed, progress)


## 0 to 1: how much the legs tuck in (most at the middle of the roll).
func get_tuck() -> float:
	if not is_dodging:
		return 0.0
	return sin(clampf(_time / duration, 0.0, 1.0) * PI)


## Recovery pose amount: rises to 1 at the end of the dodge, then springs to 0 (it can go a
## little below 0 on the swing past upright). TorsoPose and MechLegSwing use it.
func get_recovery_pose() -> float:
	if is_dodging:
		return smoothstep(roll_end, 1.0, clampf(_time / duration, 0.0, 1.0))
	return _recover.value


## True while the dodge or its recovery spring moves the body. InertiaSway pauses then.
func is_animating() -> bool:
	return is_dodging or _recovering


## Torso lean toward the dodge direction now, in degrees: x = forward lean, y = roll (head left).
func get_recovery_lean() -> Vector2:
	var amount := get_recovery_pose() * recover_lean_deg
	return Vector2(-_local_direction.z * amount, -_local_direction.x * amount)


func _physics_process(delta: float) -> void:
	if _recovering:
		_recover.update(0.0, recover_frequency, recover_damping, 10.0, delta)
		if absf(_recover.value) < 0.002 and absf(_recover.velocity) < 0.01:
			_recover.value = 0.0
			_recovering = false
	_clock += delta
	_recover_left = maxf(_recover_left - delta, 0.0)
	if not input.jump_held:
		_suppress_jump = false
	if input.jump_pressed:
		if _clock - _last_press <= double_tap_window and _can_start():
			_start()
		_last_press = _clock
	if is_dodging:
		_time += delta
		_update_roll()
		if _time >= duration:
			is_dodging = false
			roll.transform = Transform3D.IDENTITY
			# Spring forward out of the roll.
			var push := direction * spring_out_speed
			mech.velocity.x = push.x
			mech.velocity.z = push.z
			_recover_left = recovery_time
			# Start the recovery spring from the full recovery pose.
			_recover.value = 1.0
			_recover.velocity = 0.0
			_recovering = true
			dodge_ended.emit()


func _can_start() -> bool:
	return mech.is_on_floor() and not is_busy() and not landing_recovery.is_recovering() \
			and not kneel.is_kneeling and not mech.is_skidding and energy.current >= energy_cost


func _start() -> void:
	energy.try_drain(energy_cost)
	# Direction in the leg frame: -Z forward, +X right.
	var local := Vector3(0.0, 0.0, 1.0)  # No key: back.
	if input.turn_input > 0.5:
		local = Vector3(-1.0, 0.0, 0.0)  # A: left.
	elif input.turn_input < -0.5:
		local = Vector3(1.0, 0.0, 0.0)  # D: right.
	elif input.forward_held:
		local = Vector3(0.0, 0.0, -1.0)  # W: forward.
	direction = (mech.global_basis * local).normalized()
	_local_direction = local
	# Dive axis: the top of the body leans toward the move direction.
	_dive_axis = Vector3.UP.cross(local).normalized()
	# Shoulder roll axis: the dive axis turned toward the dodge direction, so one shoulder leads.
	_roll_axis = (_dive_axis + local * shoulder_amount).normalized()
	_collect_body_points()
	_plan_center_path()
	is_dodging = true
	_time = 0.0
	_last_press = -10.0
	_suppress_jump = true
	dodge_started.emit()


func _update_roll() -> void:
	var progress := clampf(_time / duration, 0.0, 1.0)
	var turn := _get_turn(progress)
	var pivot := Vector3(0.0, body_center_height, 0.0)
	# The smooth plan sets the height. The live body shape (legs tucked) can only lift it,
	# so no part goes into the ground.
	var live_lowest := 0.0
	for point in _get_live_body_points():
		live_lowest = minf(live_lowest, (turn * (point - pivot)).y)
	var height := maxf(_sample_center_path(progress), -live_lowest - _start_sink)
	roll.transform = Transform3D(turn, Vector3(0.0, height, 0.0) - turn * pivot)


## Body rotation at a point of the dodge (0 to 1): dive, shoulder roll, rise.
func _get_turn(progress: float) -> Basis:
	# Dive: 0 to 1 while leaning in, 1 during the roll, 1 to 0 while rising.
	var dive := 1.0
	if progress < dive_end:
		dive = smoothstep(0.0, dive_end, progress)
	elif progress > roll_end:
		dive = 1.0 - smoothstep(roll_end, 1.0, progress)
	# Shoulder roll: one full turn over the diagonal axis, during the middle part.
	var spin := TAU * smoothstep(dive_end, roll_end, progress)
	return Basis(_roll_axis, spin) * Basis(_dive_axis, deg_to_rad(dive_angle_deg) * dive)


## Plans the body center height along the whole dodge (idea A).
## 1. For each sample, the height where the lowest body point just touches the ground.
## 2. Take the highest value in a small window, then average: the path is smooth and never lower
##    than the contact height, so the body does not cut into the ground or pop up and down.
## The body rises a little while it leans over the long feet (toe and heel), then settles.
func _plan_center_path() -> void:
	var samples := 128
	var window := 10
	var pivot := Vector3(0.0, body_center_height, 0.0)
	var contact := PackedFloat32Array()
	contact.resize(samples + 1)
	for i in samples + 1:
		var turn := _get_turn(float(i) / samples)
		var lowest := 0.0
		for point in _body_points:
			lowest = minf(lowest, (turn * (point - pivot)).y)
		contact[i] = -lowest - _start_sink + ground_clearance
	var path := PackedFloat32Array()
	path.resize(samples + 1)
	for i in samples + 1:
		var highest := 0.0
		for j in range(maxi(i - window, 0), mini(i + window, samples) + 1):
			highest = maxf(highest, contact[j])
		path[i] = highest
	for _pass in 2:
		var smoothed := path.duplicate()
		for i in samples + 1:
			var total := 0.0
			var count := 0
			for j in range(maxi(i - window / 2, 0), mini(i + window / 2, samples) + 1):
				total += path[j]
				count += 1
			smoothed[i] = total / count
		path = smoothed
	# Near the start and the end, blend back to the exact contact height, so the path meets
	# standing height with no jump.
	for i in samples + 1:
		var progress := float(i) / samples
		var edge := 1.0 - smoothstep(0.0, 0.15, minf(progress, 1.0 - progress))
		path[i] = lerpf(path[i], contact[i], edge)
	path[0] = body_center_height
	path[samples] = body_center_height
	_center_path = path


func _sample_center_path(progress: float) -> float:
	var position := progress * (_center_path.size() - 1)
	var index := mini(int(position), _center_path.size() - 2)
	return lerpf(_center_path[index], _center_path[index + 1], position - index)


## Returns the name of the body part that touches the ground now (for tests and effects).
func get_contact_part() -> String:
	var lowest := INF
	var part := ""
	for mesh in roll.find_children("*", "MeshInstance3D", true, false):
		if _is_weapon(mesh):
			continue
		var box: AABB = (mesh as MeshInstance3D).get_aabb()
		for i in 8:
			var y := ((mesh as MeshInstance3D).global_transform * box.get_endpoint(i)).y
			if y < lowest:
				lowest = y
				part = mesh.name
	return part


func _collect_body_points() -> void:
	_body_points = _get_live_body_points()
	var lowest := 0.0
	for point in _body_points:
		lowest = minf(lowest, point.y)
	_start_sink = maxf(-lowest, 0.0)


## Body box corners in the Roll node space, from the pose now (weapon left out).
func _get_live_body_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var to_roll := roll.global_transform.affine_inverse()
	for mesh in roll.find_children("*", "MeshInstance3D", true, false):
		if _is_weapon(mesh):
			continue
		var box: AABB = (mesh as MeshInstance3D).get_aabb()
		for i in 8:
			points.append(to_roll * ((mesh as MeshInstance3D).global_transform * box.get_endpoint(i)))
	return points


func _is_weapon(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != roll:
		if parent.name == "Rifle":
			return true
		parent = parent.get_parent()
	return false
