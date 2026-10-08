class_name TorsoPose
extends Node
## Leans and turns the torso (upper body above the waist). The legs do not move with it.
## Aim: the torso twists toward the mech aim (Mech.get_torso_twist, inside the twist limits).
## Boost on the ground: lean forward. Aim down sight: turn right and tilt, so the stock sits
## on the right shoulder and the left arm reaches the handguard. Kneel and landing: forward lean.

@export var mech: Mech
@export var torso: Node3D
@export var weapon_pose: WeaponPose
@export var kneel: MechKneel
## Body inertia (lean, roll, yaw) added on top of the pose.
@export var inertia: InertiaSway
## Dodge recovery pose (torso lean toward the dodge direction).
@export var dodge: MechDodge
## Optional (Phase 8b): hit flinch and idle motion (lean, roll, turn) added on top.
@export var hit_reaction: HitReaction
@export var idle_motion: IdleMotion
## Forward lean while boosting on the ground, in degrees.
@export var boost_lean_deg: float = 21.0
## Torso turn to the right while aiming, in degrees. Brings the left shoulder forward.
@export var aim_twist_deg: float = 30.0
## Sideways tilt toward the rifle while aiming, in degrees.
@export var aim_tilt_deg: float = 6.0
## Backward lean while skidding to a stop after a boost, in degrees.
@export var skid_lean_back_deg: float = 15.0
## After the skid, the torso sways forward and back on a spring before it is upright.
## Sway speed (swings per second). Lower = slower recovery.
@export var skid_recover_frequency: float = 0.9
## Sway damping. Lower = more swings. 1.0 = no swing past upright.
@export_range(0.05, 1.0) var skid_recover_damping: float = 0.3
## Random side sway when a skid starts: the torso rolls to a random side (left or right)
## by a random amount between these values (degrees), then sways back to upright on the same spring.
@export var skid_side_sway_min_deg: float = 3.0
@export var skid_side_sway_max_deg: float = 7.0
## At the end of the dodge skid the torso sways forward by this much (degrees),
## then back to upright on the skid spring.
@export var dodge_exit_forward_sway_deg: float = 8.0
## Forward lean while running, in degrees.
@export var run_lean_deg: float = 12.0
## Forward lean while walking, in degrees (full at walk speed). MechAssembler sets it from the legs
## (LegPart.walk_lean_deg).
@export var walk_lean_deg: float = 0.0
## Forward lean after a landing from landing_lean_full_height or higher, in degrees.
## Lower falls lean less, in proportion. Fades out with the landing delay.
@export var landing_lean_deg: float = 30.0
## Fall height (meters) that gives the full landing lean.
@export var landing_lean_full_height: float = 9.0
## Forward lean while kneeling, in degrees.
@export var kneel_lean_deg: float = 8.0
## How fast the boost lean changes.
@export var blend_speed: float = 5.0
## Torso and shoulder shake at action_shake 1 (the charged beam), in degrees.
@export var action_shake_deg: float = 1.2
## Shake speed, in shakes per second.
@export var action_shake_frequency: float = 11.0

## Extra torso turn from an action (the blade slash), in degrees. Positive = turn left.
## Set every frame by the action.
var action_twist_deg: float = 0.0
## 0 to 1: shakes the torso and shoulders (the charged beam). Set every frame by the action.
var action_shake: float = 0.0
var _shake_time: float = 0.0
var _boost: float = 0.0
var _run: float = 0.0
var _walk: float = 0.0
## Skid lean in degrees (positive = back), on a spring.
var _skid_lean := AimSpring.new(0.0)
## Skid side roll in degrees (positive = head to the left), on a spring.
var _skid_roll := AimSpring.new(0.0)
var _skid_roll_target: float = 0.0
var _was_skidding: bool = false
var _was_brake_skidding: bool = false


func _ready() -> void:
	# After the Mech turns (priority 0), before MechAim and WeaponPose, which use the torso position.
	process_physics_priority = 3


func _physics_process(delta: float) -> void:
	# A melee charge (lunge) copies the ground boost lean.
	var boosting_on_ground := (mech.is_boosting or mech.is_lunging) and mech.is_on_floor()
	var blend := 1.0 - exp(-blend_speed * delta)
	_boost = lerpf(_boost, 1.0 if boosting_on_ground else 0.0, blend)
	_run = lerpf(_run, 1.0 if mech.is_running else 0.0, blend)
	var walking := mech.is_on_floor() and not mech.is_running and not boosting_on_ground and mech.walk_speed > 0.0
	var walk_target := clampf(mech.get_horizontal_speed() / mech.walk_speed, 0.0, 1.0) if walking else 0.0
	_walk = lerpf(_walk, walk_target, blend)
	var skid_target := skid_lean_back_deg if mech.is_skidding else 0.0
	_skid_lean.update(skid_target, skid_recover_frequency, skid_recover_damping, 90.0, delta)
	if mech.is_skidding and not _was_skidding:
		# New skid: roll to the skid side by a random amount.
		_skid_roll_target = mech.skid_side * randf_range(skid_side_sway_min_deg, skid_side_sway_max_deg)
	if _was_brake_skidding and not mech.is_skidding:
		# Dodge skid ended: momentum throws the torso forward, to dodge_exit_forward_sway_deg.
		_skid_lean.velocity = _find_forward_sway_speed(-dodge_exit_forward_sway_deg)
	_was_skidding = mech.is_skidding
	_was_brake_skidding = mech.is_brake_skidding
	var roll_target := _skid_roll_target if mech.is_skidding else 0.0
	_skid_roll.update(roll_target, skid_recover_frequency, skid_recover_damping, 90.0, delta)
	var aim := smoothstep(0.0, 1.0, weapon_pose.aim_amount)
	var kneel_amount := smoothstep(0.0, 1.0, kneel.amount)
	var fall_ratio := clampf(mech.landing_recovery.fall_height / landing_lean_full_height, 0.0, 1.0)
	var landing := sin(mech.landing_recovery.get_fraction() * PI * 0.5) * fall_ratio
	# Negative X leans forward. Negative Y turns right. Negative Z tilts the head to the right.
	var lean := deg_to_rad(boost_lean_deg) * _boost + deg_to_rad(run_lean_deg) * _run + deg_to_rad(walk_lean_deg) * _walk
	lean = maxf(lean, deg_to_rad(kneel_lean_deg) * kneel_amount)
	lean = maxf(lean, deg_to_rad(landing_lean_deg) * landing)
	# Positive X leans back.
	lean -= deg_to_rad(_skid_lean.value)
	lean += deg_to_rad(inertia.lean_deg)
	var extra := Vector3.ZERO  # lean, yaw, roll in degrees
	for source: Node in [hit_reaction, idle_motion]:
		if source != null:
			extra += Vector3(source.lean_deg, source.yaw_deg, source.roll_deg)
	lean += deg_to_rad(extra.x)
	var recovery := dodge.get_recovery_lean()
	lean += deg_to_rad(recovery.x)
	var shake := _get_action_shake(delta)
	torso.rotation = Vector3(
		-lean + shake.x,
		mech.get_torso_twist() - deg_to_rad(aim_twist_deg) * aim + deg_to_rad(inertia.yaw_deg) + deg_to_rad(action_twist_deg) + deg_to_rad(extra.y) + shake.y,
		-deg_to_rad(aim_tilt_deg) * aim + deg_to_rad(_skid_roll.value) + deg_to_rad(inertia.roll_deg) + deg_to_rad(recovery.y) + deg_to_rad(extra.z) + shake.z)


## Fast shake (radians on X, Y, Z) from action_shake. Sine waves at unrelated speeds look random.
func _get_action_shake(delta: float) -> Vector3:
	if action_shake <= 0.0:
		return Vector3.ZERO
	_shake_time += delta * action_shake_frequency * TAU
	var t := _shake_time
	var size := deg_to_rad(action_shake_deg) * action_shake
	return Vector3(sin(t) + 0.5 * sin(t * 2.3 + 1.0), 0.6 * sin(t * 1.7 + 2.0), sin(t * 1.3 + 4.0) + 0.4 * sin(t * 3.1)) * size * 0.7


## Start speed for the skid lean spring that makes its lowest point (forward sway) reach peak_deg.
## Tries speeds and keeps the one that fits (the spring starts from its current lean).
func _find_forward_sway_speed(peak_deg: float) -> float:
	var low := -600.0
	var high := 0.0
	for i in 24:
		var middle := (low + high) * 0.5
		if _lowest_lean(middle) < peak_deg:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## Lowest lean (degrees) the skid spring reaches from its current lean with this start speed.
func _lowest_lean(start_speed: float) -> float:
	var spring := AimSpring.new(_skid_lean.value)
	spring.velocity = start_speed
	var lowest := spring.value
	for i in 180:
		spring.update(0.0, skid_recover_frequency, skid_recover_damping, 90.0, 1.0 / 60.0)
		lowest = minf(lowest, spring.value)
	return lowest
