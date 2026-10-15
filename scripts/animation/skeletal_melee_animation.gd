class_name SkeletalMeleeAnimation
extends SkeletonModifier3D
## Melee attacks (user request 2026-10-15): MeleeAttack clips played on the whole body, arms included.
## The mouse button of a melee weapon plus the move key picks the attack (user rules):
##   Fist (its own arm's button): no key = straight punch; W = uppercut; S = overhead swing ("Mutant
##   Swiping"); A = left fist hook, swings in toward the right; D = right fist hook, swings in toward
##   the left. The hooks need a fist on that arm.
##   Hammer (either button): S = downward strike; no key or W = a weaker downward strike; A or D = the
##   two-swing hammer combo, first swing toward that side. The second swing plays only when the other
##   side's key and the button come before the first swing ends (else the combo stops after it).
## The mech steps along the clip's travel (root motion) and the legs do not walk meanwhile. During a
## strike window the weapon's strike point hits every mech within hit_radius once (the closest part).
## A dodge, a stun or knock-down, or death ends the attack.

@export var model: Node3D
@export var mech: Mech
@export var health: MechHealth
@export var weapons: WeaponController
## Moves the torso frame (shoulder weapons) with the body.
@export var arm_rig: SkeletalArmRig
## How far the clip can bend and twist the body (the arms are free).
@export var limits: JointLimits = preload("res://data/mechs/sanggigilid_joint_limits.tres")
## Radius of the hit sphere at the strike point (m).
@export var hit_radius: float = 2.0
## Move key input below this (0 to 1) counts as no key.
@export var key_dead_zone: float = 0.3
## Most hit boxes one strike query returns.
@export var max_query_results: int = 32
@export_group("Fist")
@export var straight_r: MeleeAttack = preload("res://data/melee/straight_r.tres")
@export var straight_l: MeleeAttack = preload("res://data/melee/straight_l.tres")
@export var uppercut_r: MeleeAttack = preload("res://data/melee/uppercut_r.tres")
@export var uppercut_l: MeleeAttack = preload("res://data/melee/uppercut_l.tres")
@export var swipe_r: MeleeAttack = preload("res://data/melee/swipe_r.tres")
@export var swipe_l: MeleeAttack = preload("res://data/melee/swipe_l.tres")
@export var hook_r: MeleeAttack = preload("res://data/melee/hook_r.tres")
@export var hook_l: MeleeAttack = preload("res://data/melee/hook_l.tres")
@export_group("Hammer")
@export var hammer_down: MeleeAttack = preload("res://data/melee/hammer_down.tres")
@export var hammer_down_light: MeleeAttack = preload("res://data/melee/hammer_down_light.tres")
@export var hammer_combo_a: MeleeAttack = preload("res://data/melee/hammer_combo_a.tres")
@export var hammer_combo_d: MeleeAttack = preload("res://data/melee/hammer_combo_d.tres")

## True while an attack plays (not its blend out).
var is_playing: bool = false

var _attack: MeleeAttack
var _weapon: MeleeWeapon
var _time: float = 0.0
## Where the attack ends now (the split of a combo until its second input comes).
var _end_time: float = 0.0
var _continue: bool = false
var _direction: Vector3 = Vector3.ZERO
## Mouse buttons last frame (the hammer combo's second input needs a new press of either button).
var _fire_was_held: bool = false
var _left_fire_was_held: bool = false
## Strike index -> {target: true}: each strike hits a target once.
var _hit := {}
## Blend out after the attack: the pose is held at _time and fades over the attack's blend_out.
var _fade_left: float = 0.0
## Clip -> [[track, type, bone name], ...].
var _tracks := {}


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)
	for each: MeleeAttack in [straight_r, straight_l, uppercut_r, uppercut_l, swipe_r, swipe_l, hook_r,
			hook_l, hammer_down, hammer_down_light, hammer_combo_a, hammer_combo_d]:
		if each == null or _tracks.has(each):
			continue
		var list := []
		for track in each.animation.get_track_count():
			list.append([track, each.animation.track_get_type(track),
					String(each.animation.track_get_path(track).get_concatenated_subnames())])
		_tracks[each] = list


## True while weapon's attack plays (MeleeWeapon.is_busy).
func is_attacking_with(weapon: MeleeWeapon) -> bool:
	return is_playing and _weapon == weapon


## The mouse button of a melee weapon was pressed: starts the attack for the move key (the hammer
## combo's second swing is read in _watch_combo_input).
func request(weapon: MeleeWeapon) -> void:
	if is_playing or not _can_attack():
		return
	var direction := _input_direction()
	if weapon.data.kind == WeaponData.Kind.HAMMER:
		match direction:
			&"back":
				_start(hammer_down, weapon)
			&"left":
				_start(hammer_combo_a, weapon)
			&"right":
				_start(hammer_combo_d, weapon)
			_:
				_start(hammer_down_light, weapon)
		return
	match direction:
		&"forward":
			_start(uppercut_l if weapon.is_left else uppercut_r, weapon)
		&"back":
			_start(swipe_l if weapon.is_left else swipe_r, weapon)
		&"left":
			var left_fist := weapons.left_weapon as MeleeWeapon
			if left_fist != null:
				_start(hook_l, left_fist)
		&"right":
			var right_fist := weapons.right_weapon as MeleeWeapon
			if right_fist != null and right_fist.data.kind == WeaponData.Kind.FIST:
				_start(hook_r, right_fist)
		_:
			_start(straight_l if weapon.is_left else straight_r, weapon)


## True when the mech can start an attack: standing on the ground and free (no dodge, kneel, jump
## charge, stun or knock-down).
func _can_attack() -> bool:
	if mech.is_fallen or mech.is_wrecked or not mech.is_on_floor():
		return false
	if mech.dodge != null and mech.dodge.is_busy():
		return false
	if mech.kneel != null and mech.kneel.is_kneeling:
		return false
	return mech.jump_charge == null or not mech.jump_charge.is_charging


## The move key now, in the aim frame (MechInput builds move_direction from the aim yaw, so the keys
## keep their meaning while the legs lag behind the aim): &"forward", &"back", &"left", &"right" or
## &"" (none). A diagonal counts as its side (W + D continues the hammer combo).
func _input_direction() -> StringName:
	var local := Basis(Vector3.UP, mech.get_aim_yaw()).inverse() * mech.input.move_direction
	if Vector2(local.x, local.z).length() < key_dead_zone:
		return &""
	if absf(local.z) > absf(local.x) + 0.1:
		return &"forward" if local.z < 0.0 else &"back"
	return &"left" if local.x < 0.0 else &"right"


func _start(attack: MeleeAttack, weapon: MeleeWeapon) -> void:
	_attack = attack
	_weapon = weapon
	_time = 0.0
	_continue = false
	_hit = {}
	_fade_left = 0.0
	_end_time = attack.split_time if attack.split_time > 0.0 else attack.animation.length
	is_playing = true
	# Model space (+Z forward, +X left) to the leg frame (-Z forward, +X right), as the dodge does.
	var model_direction := attack.get_direction()
	_direction = mech.global_basis * Vector3(-model_direction.x, 0.0, -model_direction.z)
	_direction.y = 0.0
	_direction = _direction.normalized()


func _physics_process(delta: float) -> void:
	_watch_combo_input()
	if not is_playing:
		_fade_left = maxf(_fade_left - delta, 0.0)
		return
	if mech.is_fallen or mech.is_wrecked or (mech.dodge != null and mech.dodge.is_dodging):
		_finish(false)
		return
	# The weapon or its arm broke: the attack stops.
	if not is_instance_valid(_weapon) or _weapon.process_mode == Node.PROCESS_MODE_DISABLED \
			or not is_instance_valid(_weapon.get_model()):
		_finish(true)
		return
	if _continue:
		_end_time = _attack.animation.length
	var before := _time
	_time = minf(_time + delta * _attack.speed_scale, _end_time)
	var speed := 0.0
	if _attack.travel != null:
		var length := _attack.animation.length
		speed = maxf((_attack.travel.sample(_time / length) - _attack.travel.sample(before / length)) * _attack.get_distance() / maxf(delta, 0.0001), 0.0)
	mech.root_motion_active = true
	mech.root_motion_velocity = _direction * speed
	_strike()
	if _time >= _end_time:
		_finish(true)


## The hammer combo's second input: a new press of either mouse button with the other side's key.
func _watch_combo_input() -> void:
	var fire := mech.input.fire_held
	var left_fire := mech.input.left_fire_held
	var pressed := (fire and not _fire_was_held) or (left_fire and not _left_fire_was_held)
	_fire_was_held = fire
	_left_fire_was_held = left_fire
	if not pressed or not is_playing or _continue:
		return
	var direction := _input_direction()
	if (_attack == hammer_combo_a and direction == &"right") or (_attack == hammer_combo_d and direction == &"left"):
		_continue = true


## Hits every mech near the strike point during a strike window, once per strike.
func _strike() -> void:
	for i in _attack.strikes.size():
		var window := _attack.strikes[i]
		if _time < window.x or _time > window.y or not is_instance_valid(_weapon):
			continue
		if not _hit.has(i):
			_hit[i] = {}
		var point := _weapon.get_strike_point()
		var shape := SphereShape3D.new()
		shape.radius = hit_radius
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, point)
		query.collision_mask = PartHitbox.LAYER
		query.exclude = health.get_hitbox_rids()
		# The closest part of each mech.
		var closest := {}
		for result in mech.get_world_3d().direct_space_state.intersect_shape(query, max_query_results):
			var hitbox := result.collider as PartHitbox
			if hitbox == null or hitbox.health == null or hitbox.health == health or _hit[i].has(hitbox.health):
				continue
			var distance := hitbox.global_position.distance_to(point)
			if not closest.has(hitbox.health) or distance < closest[hitbox.health][1]:
				closest[hitbox.health] = [hitbox, distance]
		var damage: float = _attack.damage[mini(i, _attack.damage.size() - 1)]
		for target: MechHealth in closest:
			_hit[i][target] = true
			(closest[target][0] as PartHitbox).on_hit(damage, mech.global_position, &"melee")


## The attack ends: the legs are free again and the pose fades out (fade = false: at once, for a
## dodge or a fall that takes over the body).
func _finish(fade: bool) -> void:
	is_playing = false
	_fade_left = _attack.blend_out if fade else 0.0
	# A dodge clip sets its own root motion.
	if mech.dodge == null or mech.dodge.animation == null or not mech.dodge.animation.is_playing:
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO


func _weight() -> float:
	if _attack == null:
		return 0.0
	if not is_playing:
		return _fade_left / maxf(_attack.blend_out, 0.01)
	return clampf(_time / _attack.speed_scale / maxf(_attack.blend_in, 0.01), 0.0, 1.0)


func _process_modification_with_delta(_delta: float) -> void:
	var weight := smoothstep(0.0, 1.0, _weight())
	if weight <= 0.0:
		return
	var skeleton := get_skeleton()
	var animation := _attack.animation
	# An arm that holds a shield or a gun (IK to its grip) keeps it: the clip leaves that arm out.
	var keep_left := weapons != null and weapons.arm_ik_left.target != null
	var keep_right := weapons != null and weapons.arm_ik_right.target != null and weapons.arm_ik_right.can_process()
	for entry: Array in _tracks[_attack]:
		var bone := skeleton.find_bone(entry[2])
		if bone < 0:
			continue
		if entry[2] in SkeletalDodgeAnimation.ARM_BONES and ((keep_left and entry[2].ends_with("_L")) or (keep_right and entry[2].ends_with("_R"))):
			continue
		if entry[1] == Animation.TYPE_ROTATION_3D:
			var rotation := animation.rotation_track_interpolate(entry[0], _time)
			if limits != null:
				rotation = limits.clamp_rotation(entry[2], skeleton.get_bone_rest(bone).basis.get_rotation_quaternion(), rotation)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(rotation, weight))
		elif entry[1] == Animation.TYPE_POSITION_3D:
			var position := animation.position_track_interpolate(entry[0], _time)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(position, weight))
	if arm_rig != null:
		arm_rig.refresh_torso()
