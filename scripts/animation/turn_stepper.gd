class_name TurnStepper
extends Node
## Turning in place (Phase 8b): the feet step around instead of sliding.
## Each foot keeps its own world heading. While the body turns, the planted foot stays put (its leg
## turns at the hip against the body turn) and the other foot lifts and swings to lead the turn.
## When the body has turned step_angle_deg past the planted foot, the feet swap. When the turn
## ends, a foot that is still turned takes a small settling step back under the body.
## MechLegSwing reads lift_left and lift_right (0 to 1) for the knee lift. This script sets the hip
## turn (rotation.y) after MechLegSwing.

@export var mech: Mech
@export var footsteps: MechFootsteps
@export var hip_left: Node3D
@export var hip_right: Node3D

## Body turn per step, in degrees.
@export var step_angle_deg: float = 22.0
## The swinging foot leads the body by this part of a step.
@export_range(0.0, 1.0) var lead: float = 0.35
## A settling step starts when a foot is turned more than this after the turn, in degrees.
@export var settle_deg: float = 4.0
## Settling step speed, in degrees per second.
@export var settle_speed_deg: float = 60.0
## How fast the stepping fades in and out when the mech starts or stops walking (1 / seconds).
@export var blend_speed: float = 6.0

var lift_left: float = 0.0
var lift_right: float = 0.0

## World heading of each foot (radians).
var _foot := [0.0, 0.0]
## 0 = left foot planted, 1 = right foot planted.
var _planted: int = 0
var _swing_from: float = 0.0
var _active: float = 0.0
var _started: bool = false


func _ready() -> void:
	# After MechLegSwing (0) and DodgeSlidePose (3), before the arm IK.
	process_physics_priority = 4


func _physics_process(delta: float) -> void:
	var yaw := mech.global_rotation.y
	if not _started:
		_foot = [yaw, yaw]
		_started = true
	var standing := mech.is_on_floor() and mech.get_horizontal_speed() < footsteps.min_speed \
			and not mech.is_fallen and not mech.is_wrecked and not mech.is_skidding and not mech.is_boosting
	_active = move_toward(_active, 1.0 if standing else 0.0, blend_speed * delta)
	if _active <= 0.0:
		# Walking: both feet follow the body.
		_foot = [yaw, yaw]
		lift_left = 0.0
		lift_right = 0.0
		if not mech.is_fallen and not mech.is_wrecked:
			hip_left.rotation.y = 0.0
			hip_right.rotation.y = 0.0
		return
	if mech.is_fallen or mech.is_wrecked:
		# The fall poses own the legs. After the get-up the feet start under the body.
		_started = false
		return

	var step := deg_to_rad(step_angle_deg)
	var swing := 1 - _planted
	var planted_off := wrapf(yaw - _foot[_planted], -PI, PI)
	var turning := absf(mech.leg_turn_rate) > 0.02
	var lifts := [0.0, 0.0]
	if absf(planted_off) >= step:
		# The body turned a full step past the planted foot: the feet swap.
		_planted = swing
		swing = 1 - _planted
		_swing_from = _foot[swing]
		planted_off = wrapf(yaw - _foot[_planted], -PI, PI)
	if turning:
		# The swinging foot moves from where it lifted to lead the body, with the knee up.
		var progress := clampf(absf(planted_off) / step, 0.0, 1.0)
		var goal := yaw + signf(mech.leg_turn_rate) * step * lead
		_foot[swing] = lerp_angle(_swing_from, goal, smoothstep(0.0, 1.0, progress))
		lifts[swing] = sin(progress * PI)
	else:
		# Settling: a foot that is turned steps back under the body, one foot at a time.
		for side in [_planted, swing]:
			var off := wrapf(yaw - _foot[side], -PI, PI)
			if absf(off) > deg_to_rad(settle_deg):
				var move := minf(absf(off), deg_to_rad(settle_speed_deg) * delta)
				_foot[side] = wrapf(_foot[side] + signf(off) * move, -PI, PI)
				lifts[side] = clampf(absf(off) / step, 0.2, 1.0)
				break
		_swing_from = _foot[swing]
	lift_left = lifts[0] * _active
	lift_right = lifts[1] * _active
	# Leg turn at the hip = foot heading - body heading.
	hip_left.rotation.y = wrapf(_foot[0] - yaw, -PI, PI) * _active
	hip_right.rotation.y = wrapf(_foot[1] - yaw, -PI, PI) * _active
