class_name FootPlanter
extends Node
## Foot planting while walking and running (Phase 8b): the foot on the ground stays where it
## touched down while the body moves over it, instead of sliding with the swing animation.
## MechLegSwing swings the legs; the leg in its stance half (on the ground) is then solved with
## two-bone IK in the leg plane (hip swing and knee bend) so its ankle stays on the locked point.
## A stride can be longer than the leg reaches: then the leg straightens toward the locked point and
## the heel lifts (like a toe-off) instead of the foot sliding. The IK blends out before the swing.
## Walk cycle: MechFootsteps phase. The left foot is down from phase 0 to PI, the right foot from
## PI to TAU (walking backward swaps them).

@export var mech: Mech
@export var footsteps: MechFootsteps
@export var leg_twist: MechLegTwist
@export var kneel: MechKneel
@export var dodge: MechDodge
## The pelvis node that holds the hips.
@export var lower_body: Node3D
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
## Hip to knee and knee to ankle, in meters, and the ankle height above the ground (FootLeveler
## keeps the foot flat under the ankle).
@export var thigh_length: float = 2.6
@export var shin_length: float = 2.05
@export var ankle_height: float = 0.55
## Longest leg reach used, as a part of the full leg length (a little bend stays).
@export_range(0.8, 1.0) var max_reach: float = 0.985
## Part of the stance where the IK blends in and out (0 to 0.5).
@export var blend_in: float = 0.08
@export var blend_out: float = 0.25
## How fast foot planting turns on and off with walking (1 / seconds).
@export var blend_speed: float = 5.0

var _weight: float = 0.0
## Locked sole point (world) of each leg, and whether it is set.
var _lock := [Vector3.ZERO, Vector3.ZERO]
var _locked := [false, false]


func _ready() -> void:
	# After MechLegSwing (0) and DodgeSlidePose (3), with TurnStepper (4), before the arm IK (10).
	process_physics_priority = 5
	# Custom skeletons: lengths from the frame (the same values with the mech scene's places).
	thigh_length = FrameMeasure.thigh(knee_left, thigh_length)
	shin_length = FrameMeasure.shin(knee_left, shin_length)
	ankle_height = FrameMeasure.height(knee_left, mech, ankle_height + shin_length) - shin_length


func _physics_process(delta: float) -> void:
	var walking := mech.is_on_floor() and mech.get_horizontal_speed() >= footsteps.min_speed \
			and not mech.is_boosting and not mech.is_lunging and not mech.is_skidding \
			and not mech.is_exiting_boost and not mech.is_fallen and not mech.is_wrecked \
			and kneel.amount < 0.05 and not dodge.is_animating()
	_weight = move_toward(_weight, 1.0 if walking else 0.0, blend_speed * delta)
	if _weight <= 0.0:
		_locked = [false, false]
		return
	var phase := fposmod(footsteps.get_cycle_phase(), TAU)
	if leg_twist.moving_backward:
		phase = fposmod(phase + PI, TAU)
	var ground := mech.global_position.y
	for side in 2:
		var hip: Node3D = hip_left if side == 0 else hip_right
		var knee: Node3D = knee_left if side == 0 else knee_right
		# Stance progress 0 to 1 (touchdown to lift), or -1 while the foot swings.
		var stance := phase / PI if side == 0 else (phase - PI) / PI
		if stance < 0.0 or stance > 1.0:
			_locked[side] = false
			continue
		if not _locked[side]:
			# Touchdown: lock where the swing animation put the ankle, at ankle height over the ground.
			var ankle := knee.global_transform * Vector3(0.0, -shin_length, 0.0)
			_lock[side] = Vector3(ankle.x, ground + ankle_height, ankle.z)
			_locked[side] = true
		var ramp := smoothstep(0.0, blend_in, stance) * (1.0 - smoothstep(1.0 - blend_out, 1.0, stance))
		_solve(side, hip, knee, ramp * _weight)


## Two-bone IK in the leg plane: hip swing and knee bend that put the ankle on the locked point.
func _solve(side: int, hip: Node3D, knee: Node3D, weight: float) -> void:
	var reach := (thigh_length + shin_length) * max_reach
	var target: Vector3 = _lock[side]
	# The target in the pelvis frame, in the leg plane (forward = -Z, down = -Y).
	var local := lower_body.global_transform.affine_inverse() * target
	var from := hip.position
	var forward := -(local.z - from.z)
	var drop := -(local.y - from.y)
	var distance := clampf(Vector2(forward, drop).length(), 0.1, reach)
	var a := thigh_length
	var b := shin_length
	var knee_inner := acos(clampf((a * a + b * b - distance * distance) / (2.0 * a * b), -1.0, 1.0))
	var hip_offset := acos(clampf((a * a + distance * distance - b * b) / (2.0 * a * distance), -1.0, 1.0))
	var hip_angle := atan2(forward, drop) + hip_offset
	var knee_angle := -(PI - knee_inner)
	hip.rotation.x = lerp_angle(hip.rotation.x, hip_angle, weight)
	knee.rotation.x = lerp_angle(knee.rotation.x, knee_angle, weight)
