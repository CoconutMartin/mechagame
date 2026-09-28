class_name SkidBodyTurn
extends Node
## During a boost skid the whole body turns at an angle to the skid side (like a drift),
## then turns back to center during the recovery. Visual only: the aim and the camera do not turn.
## Akira slide: near the end of every slide (dodge and boost stop) the body swings until the legs
## are sideways to the slide, and leans back against the motion. Then it turns back during the steps.
## The swing side follows A / D when one is held (A = left, D = right), otherwise it is random.

@export var mech: Mech
## Gives A / D for the swing side.
@export var input: MechInput
## The whole mech visual (legs and torso).
@export var body: Node3D
## Optional. Tilts the whole body for the Akira slide lean. A child of body.
@export var lean_node: Node3D
## Optional. Its Y turn (leg twist) counts when the legs turn sideways to the slide.
@export var lower_body: Node3D
## Random turn angle range, in degrees.
@export var turn_min_deg: float = 15.0
@export var turn_max_deg: float = 30.0
## Spring speed (swings per second). Lower = slower turn and return.
@export var frequency: float = 0.8
## Spring damping. 1.0 = smooth return with no swing past center.
@export_range(0.05, 1.0) var damping: float = 0.7

@export_group("Akira Slide")
## The swing starts at this part of the dodge slide (0 = start, 1 = end) and is full at akira_end.
@export_range(0.0, 1.0) var akira_start: float = 0.5
@export_range(0.0, 1.0) var akira_end: float = 0.9
## Legs sideways to the slide = 90 degrees. Largest body turn, in degrees.
@export var akira_max_turn_deg: float = 160.0
## Body lean back against the slide at the end, in degrees.
@export var akira_lean_deg: float = 14.0
## Spring speed for the Akira swing (faster than the drift turn).
@export var akira_frequency: float = 2.2
## The Akira pose stays this long after the slide ends (seconds), then the body turns back.
@export var akira_hold_time: float = 0.4
## How fast the body turns back after the hold (1 / seconds). 1.2 = 40% slower than 2.
@export var akira_recover_speed: float = 1.2
@export_group("")

## 0 to 1: how far the Akira swing is. DodgeSlidePose reads it.
var akira_amount: float = 0.0
## Swing side: +1 = body turns left, -1 = right. DodgeSlidePose reads it.
var akira_side: float = 1.0

var _turn := AimSpring.new(0.0)
var _lean := AimSpring.new(0.0)
var _target: float = 0.0
var _was_skidding: bool = false
var _slide_direction: Vector3 = Vector3.FORWARD
var _hold_left: float = 0.0


func _ready() -> void:
	# After the Mech moves, before the torso and arm poses.
	process_physics_priority = 2


func _physics_process(delta: float) -> void:
	if mech.is_skidding and not _was_skidding:
		_target = mech.skid_side * randf_range(turn_min_deg, turn_max_deg)
		akira_side = 1.0 if randf() < 0.5 else -1.0
	# A held direction key sets the swing side (A = left, D = right) until the swing is full.
	if mech.is_skidding and input != null and absf(input.turn_input) > 0.5 and akira_amount < 0.99:
		akira_side = signf(input.turn_input)
	_was_skidding = mech.is_skidding
	var velocity := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	if velocity.length() > 0.5:
		_slide_direction = velocity.normalized()
	var target := _target if mech.is_skidding else 0.0
	var frequency_now := frequency
	_hold_left = maxf(_hold_left - delta, 0.0)
	if mech.is_skidding:
		akira_amount = smoothstep(akira_start, akira_end, mech.get_skid_progress())
		_hold_left = akira_hold_time if akira_amount > 0.0 else 0.0
	elif _hold_left <= 0.0:
		akira_amount = move_toward(akira_amount, 0.0, delta * akira_recover_speed)
	if akira_amount > 0.0:
		target = lerpf(target, _get_sideways_turn_deg(), akira_amount)
		frequency_now = lerpf(frequency, akira_frequency, akira_amount)
	_turn.update(target, frequency_now, damping, 180.0, delta)
	body.rotation.y = deg_to_rad(_turn.value)
	_update_lean(delta)


## Body turn (degrees) that puts the legs sideways to the slide, turned toward the skid side.
func _get_sideways_turn_deg() -> float:
	var slide_yaw := atan2(-_slide_direction.x, -_slide_direction.z)
	var legs_twist := lower_body.rotation.y if lower_body != null else 0.0
	var facing := slide_yaw + akira_side * PI * 0.5
	var turn := rad_to_deg(wrapf(facing - mech.rotation.y - legs_twist, -PI, PI))
	return clampf(turn, -akira_max_turn_deg, akira_max_turn_deg)


## Leans the whole body back against the slide (top away from the motion).
func _update_lean(delta: float) -> void:
	if lean_node == null:
		return
	_lean.update(akira_lean_deg * akira_amount, akira_frequency, 0.6, 90.0, delta)
	var local := body.global_basis.inverse() * -_slide_direction
	local.y = 0.0
	if local.length_squared() < 0.001 or absf(_lean.value) < 0.01:
		lean_node.basis = Basis.IDENTITY
		return
	var axis := Vector3.UP.cross(local.normalized()).normalized()
	lean_node.basis = Basis(axis, deg_to_rad(_lean.value))
