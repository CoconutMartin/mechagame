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
@export var duration: float = 2.55
@export var energy_cost: float = 25.0
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
var _suppress_jump: bool = false


func _ready() -> void:
	# Before the jump charge (-5) and the Mech (0).
	process_physics_priority = -6


## True while dodging or recovering. The mech cannot move, boost, or turn.
func is_busy() -> bool:
	return is_dodging or _recover_left > 0.0


## True while the Space press that started the dodge is still held. The jump charge waits.
func blocks_jump() -> bool:
	return is_busy() or _suppress_jump


## Dodge speed now, in m/s. Starts at 2x the average speed and falls to zero.
func get_speed() -> float:
	var progress := clampf(_time / duration, 0.0, 1.0)
	return distance / duration * 2.0 * (1.0 - progress)


## 0 to 1: how much the legs tuck in (most at the middle of the roll).
func get_tuck() -> float:
	if not is_dodging:
		return 0.0
	return sin(clampf(_time / duration, 0.0, 1.0) * PI)


func _physics_process(delta: float) -> void:
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
			_recover_left = recovery_time
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
	# Dive axis: the top of the body leans toward the move direction.
	_dive_axis = Vector3.UP.cross(local).normalized()
	# Shoulder roll axis: the dive axis turned toward the dodge direction, so one shoulder leads.
	_roll_axis = (_dive_axis + local * shoulder_amount).normalized()
	_collect_body_points()
	is_dodging = true
	_time = 0.0
	_last_press = -10.0
	_suppress_jump = true
	dodge_started.emit()


func _update_roll() -> void:
	var progress := clampf(_time / duration, 0.0, 1.0)
	# Dive: 0 to 1 while leaning in, 1 during the roll, 1 to 0 while rising.
	var dive := 1.0
	if progress < dive_end:
		dive = smoothstep(0.0, dive_end, progress)
	elif progress > roll_end:
		dive = 1.0 - smoothstep(roll_end, 1.0, progress)
	# Shoulder roll: one full turn over the diagonal axis, during the middle part.
	var spin := TAU * smoothstep(dive_end, roll_end, progress)
	var turn := Basis(_roll_axis, spin) * Basis(_dive_axis, deg_to_rad(dive_angle_deg) * dive)
	# Lift the body so its lowest point just touches the ground: it rolls on the ground,
	# first on the leading shoulder, then over the back and the hip.
	var pivot := Vector3(0.0, body_center_height, 0.0)
	var lowest := 0.0
	for point in _body_points:
		lowest = minf(lowest, (turn * (point - pivot)).y)
	var center := Vector3(0.0, -lowest + ground_clearance * dive, 0.0)
	roll.transform = Transform3D(turn, center - turn * pivot)


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
	_body_points.clear()
	var to_roll := roll.global_transform.affine_inverse()
	for mesh in roll.find_children("*", "MeshInstance3D", true, false):
		if _is_weapon(mesh):
			continue
		var box: AABB = (mesh as MeshInstance3D).get_aabb()
		for i in 8:
			_body_points.append(to_roll * ((mesh as MeshInstance3D).global_transform * box.get_endpoint(i)))


func _is_weapon(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != roll:
		if parent.name == "Rifle":
			return true
		parent = parent.get_parent()
	return false
