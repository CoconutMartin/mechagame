class_name SkeletalDeath
extends Node
## A rigged mech that is destroyed: it becomes a wreck (it slides to a stop and takes no input), its
## pose freezes, and it topples over its feet like a falling tree: the way it moves, or backward if
## it stands still. A crash shake and dust explosion when it hits the ground. PlayerRespawner then
## builds a new one.
## With a death animation (user request 2026-10-15) a Mixamo death clip plays in place of the tree
## fall, picked by the cause and the movement (SkeletalDeathAnimation); the crash comes when the body
## hits the ground.

@export var mech: Mech
@export var health: MechHealth
@export var tree: AnimationTree
@export var camera_shake: CameraShake
## Optional. A left arm that follows the animation (its weapon or shield broke) goes to the relaxed
## hang when the pose freezes, so it takes no stiff frozen pose.
@export var weapons: WeaponController
## Optional. Plays a death clip in place of the tree fall.
@export var animation: SkeletalDeathAnimation
## Optional. A mech that dies while it is down (knocked down) stays down: no clip, no fall.
@export var stagger: SkeletalStaggerAnimation
## Seconds after the death clip ends before the new mech (PlayerRespawner waits for it).
@export var after_clip_time: float = 1.5
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


func _on_destroyed(cause: String) -> void:
	# Pick before the wreck flag: the pick reads the movement.
	var down := stagger != null and stagger.is_down
	var stunned := stagger != null and stagger.is_staggered()
	var clip: DeathClip = animation.pick(cause, stunned) if animation != null and not down else null
	mech.is_wrecked = true
	tree.active = false
	if weapons != null:
		weapons.relax_free_left_arm()
	if camera_shake != null:
		camera_shake.add_shake(0.6, 0.8)
	if down:
		_crash_at(mech.global_position + Vector3.UP)
		return
	if clip != null:
		animation.impact.connect(_crash_at, CONNECT_ONE_SHOT)
		animation.start(clip)
		return
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
		_crash_at(mech.global_position + mech.global_basis * (_pivot * 4.0) + Vector3.UP)


## Seconds from death to the end of the fall (the clip, or the tree fall).
func get_fall_time() -> float:
	if stagger != null and stagger.is_down and animation != null and animation.clip == null:
		return after_clip_time
	if animation != null and animation.clip != null:
		return animation.get_length() + after_clip_time
	return fall_time


func _crash_at(where: Vector3) -> void:
	if _crashed:
		return
	_crashed = true
	var level := get_tree().current_scene if get_tree().current_scene != null else mech.get_parent()
	PartBreaker.explode_in(level, where, crash_size)
	if camera_shake != null:
		camera_shake.add_shake(0.8, 1.2)
