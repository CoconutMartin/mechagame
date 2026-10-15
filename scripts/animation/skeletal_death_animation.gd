class_name SkeletalDeathAnimation
extends SkeletonModifier3D
## Death animations (user request 2026-10-15): a retargeted Mixamo clip (DeathClip) plays in place of
## the tree fall. Which clip (user table, the first match wins):
##   1. both legs or the groin destroyed: legs     5. standing, killing hit from behind: behind
##   2. running or boosting: run                   6. standing, head or center torso destroyed and a
##   3. walking: walk                                 side torso below side_fraction HP: side
##   4. kneeling or crouching: crouch              7. standing, head destroyed: head
##                                                 8. standing, center torso destroyed: torso
## The clip plays in place; the wreck moves along the clip's travel curve (its velocity), so the body
## falls the way the clip moves. The clip holds its last pose. impact is emitted when the pelvis is
## near its lowest point (the body hits the ground). The pose is held inside the death joint limits
## (the pelvis is free so the body can fall). The arms keep holding the weapon, like the other clips.

## The body hits the ground (world position of the pelvis).
signal impact(where: Vector3)

@export var model: Node3D
@export var mech: Mech
@export var health: MechHealth
## Moves the torso frame (weapon, shield) with the body.
@export var arm_rig: SkeletalArmRig
@export var limits: JointLimits = preload("res://data/mechs/sanggigilid_death_joint_limits.tres")
@export_group("Clips")
@export var legs: DeathClip = preload("res://data/deaths/legs.tres")
@export var run: DeathClip = preload("res://data/deaths/run.tres")
@export var walk: DeathClip = preload("res://data/deaths/walk.tres")
@export var crouch: DeathClip = preload("res://data/deaths/crouch.tres")
@export var behind: DeathClip = preload("res://data/deaths/behind.tres")
@export var side: DeathClip = preload("res://data/deaths/side.tres")
@export var head: DeathClip = preload("res://data/deaths/head.tres")
@export var torso: DeathClip = preload("res://data/deaths/torso.tres")
@export_group("Pick")
## Above this ground speed (m/s) the mech is walking.
@export var walk_speed: float = 1.0
## A killing hit from inside this angle around the mech's back (degrees) is "from behind".
@export var behind_angle_deg: float = 60.0
## A side torso below this part of its HP (0 to 1) is heavily damaged.
@export var side_fraction: float = 0.25
@export_group("Impact")
## The body hits the ground when the pelvis is this part of the way down to its lowest point (0 to 1).
@export var impact_depth: float = 0.85

## True while a clip plays (it holds its last pose after that).
var is_playing: bool = false
## The clip that plays (null when none).
var clip: DeathClip

var _time: float = 0.0
var _direction: Vector3 = Vector3.ZERO
var _impacted: bool = false
## Clip -> [[track, type, bone name], ...].
var _tracks := {}
## Clip -> impact time (seconds of the animation).
var _impact_times := {}


func _ready() -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if get_skeleton() == null:
		reparent.call_deferred(skeleton, false)
	# The pelvis track is in its parent bone's space: this turns it into model space (height = y).
	var pelvis := skeleton.find_bone("pelvis")
	var parent := skeleton.get_bone_parent(pelvis)
	var to_model := skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
	for each: DeathClip in [legs, run, walk, crouch, behind, side, head, torso]:
		if each == null or _tracks.has(each):
			continue
		var list := []
		for track in each.animation.get_track_count():
			var bone := String(each.animation.track_get_path(track).get_concatenated_subnames())
			if bone not in SkeletalDodgeAnimation.ARM_BONES:
				list.append([track, each.animation.track_get_type(track), bone])
		_tracks[each] = list
		_impact_times[each] = _find_impact(each.animation, to_model)


## The clip for this death (cause: the part that killed the mech). standing: the mech stands still
## whatever its speed (a stun moves it with the stagger clip).
func pick(cause: String, standing: bool = false) -> DeathClip:
	if cause == "Groin" or (not health.is_part_alive("Leg L") and not health.is_part_alive("Leg R")):
		return legs
	if not standing and (mech.is_running or mech.is_boosting):
		return run
	if not standing and mech.get_horizontal_speed() > walk_speed:
		return walk
	if not standing and ((mech.kneel != null and mech.kneel.is_kneeling) or (mech.jump_charge != null and mech.jump_charge.is_charging)):
		return crouch
	if health.last_hit_from_behind(behind_angle_deg):
		return behind
	if (cause == "Head" or cause == "Torso C") and _side_heavily_damaged():
		return side
	if cause == "Head":
		return head
	return torso


## Starts a clip.
func start(chosen: DeathClip) -> void:
	clip = chosen
	is_playing = true
	_time = 0.0
	_impacted = false
	# Model space (+Z forward, +X left) to the leg frame (-Z forward, +X right), as the dodge does.
	var model_direction := clip.get_direction()
	_direction = mech.global_basis * Vector3(-model_direction.x, 0.0, -model_direction.z)
	_direction.y = 0.0
	_direction = _direction.normalized()


## Seconds the clip plays.
func get_length() -> float:
	return clip.get_length() if clip != null else 0.0


func _physics_process(delta: float) -> void:
	if not is_playing:
		return
	var length := clip.animation.length
	var before := _time
	_time = minf(_time + delta * clip.speed_scale, length)
	# The wreck moves along the clip's travel (Mech._update_wreck slides with this velocity).
	var speed := (clip.travel.sample(_time / length) - clip.travel.sample(before / length)) * clip.get_distance() / maxf(delta, 0.0001)
	# Mech._update_wreck takes the slide deceleration off before it moves: add it back, so the
	# travel does not depend on the frame rate.
	speed += mech.fallen_slide_deceleration * delta if speed > 0.0 else 0.0
	mech.velocity.x = _direction.x * speed
	mech.velocity.z = _direction.z * speed
	if not _impacted and _time >= _impact_times[clip]:
		_impacted = true
		var skeleton := get_skeleton()
		var pelvis := skeleton.find_bone("pelvis")
		impact.emit(skeleton.global_transform * skeleton.get_bone_global_pose(pelvis).origin)
	if _time >= length:
		is_playing = false


func _find_impact(animation: Animation, to_model: Transform3D) -> float:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var start_y := (to_model * animation.position_track_interpolate(track, 0.0)).y
		var low_y := start_y
		var time := 0.0
		while time <= animation.length:
			low_y = minf(low_y, (to_model * animation.position_track_interpolate(track, time)).y)
			time += 1.0 / 30.0
		var target := start_y - (start_y - low_y) * impact_depth
		time = 0.0
		while time <= animation.length:
			if (to_model * animation.position_track_interpolate(track, time)).y <= target:
				return time
			time += 1.0 / 30.0
	return animation.length


func _side_heavily_damaged() -> bool:
	return health.get_fraction("Torso L") < side_fraction or health.get_fraction("Torso R") < side_fraction


func _process_modification_with_delta(_delta: float) -> void:
	if clip == null:
		return
	var weight := smoothstep(0.0, 1.0, clampf(_time / clip.speed_scale / maxf(clip.blend_in, 0.01), 0.0, 1.0))
	if weight <= 0.0:
		return
	var skeleton := get_skeleton()
	var animation := clip.animation
	for entry: Array in _tracks[clip]:
		var bone := skeleton.find_bone(entry[2])
		if bone < 0:
			continue
		if entry[1] == Animation.TYPE_ROTATION_3D:
			var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			var rotation := rest.slerp(animation.rotation_track_interpolate(entry[0], _time), clip.strength)
			if limits != null:
				rotation = limits.clamp_rotation(entry[2], rest, rotation)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(rotation, weight))
		elif entry[1] == Animation.TYPE_POSITION_3D:
			var position := skeleton.get_bone_rest(bone).origin.lerp(animation.position_track_interpolate(entry[0], _time), clip.strength)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(position, weight))
	if arm_rig != null:
		arm_rig.refresh_torso()
