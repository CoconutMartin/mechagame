class_name IdleMotion
extends Node
## Idle motion (Phase 8b): after the mech stands still for start_delay seconds, it breathes (a slow
## knee dip and torso lean), scans (the torso turns a little to look around) and shifts its weight
## from one leg to the other now and then. Any move, aim or action fades it out.
## TorsoPose adds lean_deg, roll_deg and yaw_deg. MechLegSwing adds crouch.

@export var mech: Mech
@export var weapon_pose: WeaponPose
@export var kneel: MechKneel

## Seconds of standing still before the idle motion starts.
@export var start_delay: float = 1.2
## How fast the idle motion fades in and out (1 / seconds).
@export var fade_speed: float = 1.2

@export_group("Breath")
## Seconds for one breath (knee dip and torso lean).
@export var breath_period: float = 4.5
@export var breath_lean_deg: float = 0.6
@export var breath_crouch_deg: float = 1.0

@export_group("Scan")
## Largest scan turn, in degrees, and seconds between new scan targets (random in this range).
@export var scan_deg: float = 7.0
@export var scan_time_min: float = 3.0
@export var scan_time_max: float = 6.5
## How fast the torso turns to a scan target (1 / seconds).
@export var scan_speed: float = 1.1

@export_group("Weight Shift")
## Roll toward the leg that takes the weight, in degrees, and seconds between shifts (random).
@export var shift_roll_deg: float = 1.4
@export var shift_time_min: float = 5.0
@export var shift_time_max: float = 10.0
@export var shift_speed: float = 0.8

var lean_deg: float = 0.0
var roll_deg: float = 0.0
var yaw_deg: float = 0.0
## Knee dip in radians of hip bend.
var crouch: float = 0.0

var _still_time: float = 0.0
var _amount: float = 0.0
var _time: float = 0.0
var _scan: float = 0.0
var _scan_goal: float = 0.0
var _scan_left: float = 0.0
var _shift: float = 0.0
var _shift_goal: float = 0.0
var _shift_left: float = 0.0


func _ready() -> void:
	# Before TorsoPose (3).
	process_physics_priority = 2
	_scan_left = randf_range(scan_time_min, scan_time_max)
	_shift_left = randf_range(shift_time_min, shift_time_max)


func _physics_process(delta: float) -> void:
	var busy := not mech.is_on_floor() or mech.get_horizontal_speed() > 0.5 or mech.is_fallen \
			or mech.is_wrecked or mech.is_boosting or absf(mech.leg_turn_rate) > 0.05 \
			or (weapon_pose != null and weapon_pose.aim_amount > 0.05) or (kneel != null and kneel.amount > 0.05)
	_still_time = 0.0 if busy else _still_time + delta
	var target := 1.0 if _still_time >= start_delay else 0.0
	_amount = move_toward(_amount, target, fade_speed * delta)
	_time += delta

	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = randf_range(scan_time_min, scan_time_max)
		_scan_goal = randf_range(-scan_deg, scan_deg) if randf() < 0.75 else 0.0
	_scan = lerpf(_scan, _scan_goal, 1.0 - exp(-scan_speed * delta))
	_shift_left -= delta
	if _shift_left <= 0.0:
		_shift_left = randf_range(shift_time_min, shift_time_max)
		_shift_goal = -signf(_shift_goal) if _shift_goal != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	_shift = lerpf(_shift, _shift_goal, 1.0 - exp(-shift_speed * delta))

	var breath := sin(_time * TAU / breath_period)
	var a := smoothstep(0.0, 1.0, _amount)
	lean_deg = breath_lean_deg * breath * a
	crouch = deg_to_rad(breath_crouch_deg * (breath * 0.5 + 0.5)) * a
	yaw_deg = _scan * a
	roll_deg = shift_roll_deg * _shift * a
