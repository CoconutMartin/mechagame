class_name FreeArmSwing
extends Node
## An empty hand moves (user request 2026-10-15: "the empty left arm just hangs without movement").
## A relaxed (hanging) arm swings forward and back against the legs while walking (the left arm forward
## when the right foot is forward) and sways a little while standing. Mech adds it at runtime; it finds
## the WeaponController and SkeletalLocomotion of its mech.
## Whole arm swing (user report 2026-10-18: the shoulders swung while the hands stayed in one place):
## this node only gives the swing angles (left_angle, right_angle). SkeletalArmRig solves the arm to its
## still relaxed hang marker and then turns the whole arm (shoulder, elbow and hand together) about the
## shoulder by that angle, like a pendulum. The hang markers do not move any more.

@export var mech: Mech
@export var locomotion: SkeletalLocomotion
@export var weapons: WeaponController
## Arm swing forward and back at walk speed, in degrees about the shoulder (13 degrees: the hand moves
## about the 0.9 m of the old hand swing).
@export var swing_deg: float = 13.0
## Idle sway while standing, in degrees, and its speed in cycles per second.
@export var idle_sway_deg: float = 1.2
@export var idle_sway_speed: float = 0.3
## How fast the swing size follows the speed (per second).
@export var blend_speed: float = 4.0

## Swing of each relaxed arm now (radians about the torso's right axis; forward is positive).
var left_angle: float = 0.0
var right_angle: float = 0.0

var _amount: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	if mech == null:
		mech = get_parent() as Mech
	if mech == null:
		return
	if weapons == null:
		weapons = mech.find_child("WeaponController", true, false) as WeaponController
	if locomotion == null:
		for node in mech.find_children("*", "", true, false):
			if node is SkeletalLocomotion:
				locomotion = node as SkeletalLocomotion
				break


func _physics_process(delta: float) -> void:
	if mech == null:
		return
	_time += delta
	var walking := mech.is_on_floor() and not mech.is_fallen and not mech.is_wrecked
	var target := clampf(mech.get_horizontal_speed() / maxf(mech.walk_speed, 0.1), 0.0, 1.0) if walking else 0.0
	_amount = move_toward(_amount, target, blend_speed * delta)
	var phase := locomotion.get_phase() if locomotion != null else 0.0
	# Phase 0: the left foot lands (left leg forward), so the left hand is back then.
	var arc := cos(TAU * phase)
	left_angle = _angle(-arc, 0.0)
	right_angle = _angle(arc, 0.5)


## One arm's swing angle: forward (-1 to 1) of the walk arc; offset (0 to 1) shifts the idle sway in time.
func _angle(forward: float, offset: float) -> float:
	var idle := sin(TAU * (_time * idle_sway_speed + offset)) * idle_sway_deg * (1.0 - _amount)
	return deg_to_rad(forward * swing_deg * _amount + idle)
