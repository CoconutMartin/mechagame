class_name SkeletalDeath
extends Node
## A rigged mech that is destroyed: it becomes a wreck (it slides to a stop and takes no input), its
## pose freezes, and it topples over its feet like a falling tree: the way it moves, or backward if
## it stands still. A crash shake and dust explosion when it hits the ground. PlayerRespawner then
## builds a new one.

@export var mech: Mech
@export var health: MechHealth
@export var tree: AnimationTree
@export var camera_shake: CameraShake
## The node that topples (the body visual, with the model in it).
@export var visual: Node3D
## Seconds from standing to lying on the ground.
@export var fall_time: float = 1.6
## Lean at the end (degrees from upright). Less than 90: the body lies on its front or back.
@export var fall_angle_deg: float = 82.0
## The body tips over a ground point this far from the mech center (m), on the side it falls to.
@export var pivot_distance: float = 1.4
## Below this speed (m/s) it falls backward.
@export var min_fall_speed: float = 1.0
## Flash size of the crash at the end of the fall (m).
@export var crash_size: float = 6.0

var _falling: bool = false
var _time: float = 0.0
var _axis := Vector3.RIGHT
var _pivot := Vector3.ZERO
var _crashed: bool = false


func _ready() -> void:
	health.destroyed.connect(_on_destroyed)


func _on_destroyed(_cause: String) -> void:
	mech.is_wrecked = true
	tree.active = false
	if camera_shake != null:
		camera_shake.add_shake(0.6, 0.8)
	# Fall direction in the mech's own space (forward is -Z).
	var move := mech.global_basis.inverse() * Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	var direction := Vector3.BACK
	if move.length() > min_fall_speed:
		direction = move.normalized()
	_axis = Vector3.UP.cross(direction).normalized()
	_pivot = direction * pivot_distance
	_falling = true


func _process(delta: float) -> void:
	if not _falling:
		return
	_time += delta
	# Slow at first, then faster, like a tall body tipping over.
	var amount := minf(_time / fall_time, 1.0)
	var basis := Basis(_axis, deg_to_rad(fall_angle_deg) * amount * amount)
	visual.transform = Transform3D(basis, _pivot - basis * _pivot)
	if amount >= 1.0 and not _crashed:
		_crashed = true
		var level := get_tree().current_scene if get_tree().current_scene != null else mech.get_parent()
		PartBreaker.explode_in(level, mech.global_position + mech.global_basis * (_pivot * 4.0) + Vector3.UP, crash_size)
		if camera_shake != null:
			camera_shake.add_shake(0.8, 1.2)
