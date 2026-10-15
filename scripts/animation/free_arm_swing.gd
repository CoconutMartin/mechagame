class_name FreeArmSwing
extends Node
## An empty hand moves (user request 2026-10-15: "the empty left arm just hangs without movement").
## The relaxed hand markers (WeaponController.free_left_hand / free_right_hand, the arm IK targets of an
## empty hand) swing forward and back against the legs while walking (the left hand forward when the
## right foot is forward) and sway a little while standing. Mech adds it at runtime; it finds the
## WeaponController and SkeletalLocomotion of its mech.

@export var mech: Mech
@export var locomotion: SkeletalLocomotion
@export var weapons: WeaponController
## Hand swing forward and back at walk speed, in meters (torso space; the mech is about 10 m tall).
@export var swing_m: float = 0.9
## The hand rises this much of the swing at the front and back of the arc.
@export var swing_lift: float = 0.15
## Idle sway while standing, in meters, and its speed in cycles per second.
@export var idle_sway_m: float = 0.08
@export var idle_sway_speed: float = 0.3
## How fast the swing size follows the speed (per second).
@export var blend_speed: float = 4.0

## Marker -> its place with no swing.
var _base := {}
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
	if mech == null or weapons == null:
		return
	_time += delta
	var walking := mech.is_on_floor() and not mech.is_fallen and not mech.is_wrecked
	var target := clampf(mech.get_horizontal_speed() / maxf(mech.walk_speed, 0.1), 0.0, 1.0) if walking else 0.0
	_amount = move_toward(_amount, target, blend_speed * delta)
	var phase := locomotion.get_phase() if locomotion != null else 0.0
	# Phase 0: the left foot lands (left leg forward), so the left hand is back then.
	var arc := cos(TAU * phase)
	_move(weapons.free_left_hand, -arc, 0.0)
	_move(weapons.free_right_hand, arc, 0.5)


## Moves one marker: forward is -Z in torso space. offset (0 to 1) shifts the idle sway in time.
func _move(marker: Node3D, forward: float, offset: float) -> void:
	if not is_instance_valid(marker):
		return
	if not _base.has(marker):
		_base[marker] = marker.position
	var base: Vector3 = _base[marker]
	var swing := forward * swing_m * _amount
	var idle := sin(TAU * (_time * idle_sway_speed + offset)) * idle_sway_m * (1.0 - _amount)
	marker.position = base + Vector3(0.0, absf(swing) * swing_lift + idle * 0.5, -swing + idle)
