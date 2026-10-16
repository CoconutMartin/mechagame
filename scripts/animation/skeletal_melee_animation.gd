class_name SkeletalMeleeAnimation
extends SkeletonModifier3D
## Melee attacks (user request 2026-10-15): MeleeAttack clips played on the whole body, arms included.
## The mouse button of a melee weapon plus the move key picks the attack (user rules):
##   Fist (its own arm's button): no key = straight punch; W = uppercut; S = overhead swing ("Mutant
##   Swiping"); A = left fist hook, swings in toward the right; D = right fist hook, swings in toward
##   the left. The hooks need a fist on that arm.
##   Fist combo (user, 2026-10-15): the plain punch (no key) goes on for up to 3 swings: left, right, then
##   a heavy uppercut (MeleeAttack.follow_ups). The next swing plays when its button press comes within
##   combo_window seconds after the swing before hit a target, and before that swing ends. The body
##   blends from the pose of one swing into the next.
##   Hammer (RMB only, user 2026-10-15): S = downward strike; no key or W = a weaker downward strike;
##   D = one swing from the right to the left; A = one swing from the left to the right. No combos.
## After one swing or a whole combo ends, no melee attack starts for cooldown seconds.
## Target tracking (user, 2026-10-15): an enemy inside the aim cone (and within target_range) turns the
## mech to face it, and the mech glides toward it so the strike lands at the attack's contact distance.
## Without a target the attack plays in place.
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
## No melee attack starts for this many seconds after a swing or a whole combo ended (anti spam).
@export var cooldown: float = 5.0
@export_group("Combo")
## The next swing of a fist combo needs its button press within this many seconds after the swing
## before hit a target (and before that swing ends).
@export var combo_window: float = 0.5
## Seconds to blend from the pose of one swing into the next.
@export var combo_blend: float = 0.25
@export_group("Targeting")
## Farthest target the attack turns toward and glides to (m, center to center).
@export var target_range: float = 20.0
## A target counts when its edge is inside this angle from the aim (degrees, sideways).
@export var aim_cone_deg: float = 8.0
## Half width of a target mech for the aim cone (m).
@export var target_half_width: float = 2.5
## How fast the mech turns to the target (degrees per second).
@export var turn_speed_deg: float = 360.0
## Top speed of the glide toward the target (m/s).
@export var lunge_speed: float = 30.0
## How fast the glide speeds up and slows down (m/s per second).
@export var lunge_acceleration: float = 90.0
## The glide stops this far (m) from where the strike should land.
@export var lunge_tolerance: float = 0.3
## The wind-up pose waits this long (s) at most for the glide to arrive.
@export var lunge_hold_time: float = 0.6
## The legs and the pelvis follow the clip with no joint limits (the limits bent the legs of a deep
## stance until a foot was 2 m under the ground). The torso, head and arms keep the limits.
@export var free_legs: bool = true
@export_group("Foot clamp")
## The walk's ankle pitch (SkeletalAnklePitch, it runs after this node and turns the toes down while the
## mech moves) is off while a melee pose shows: the clip sets the feet, and the lunge speed made the toes
## dig into the ground.
func _switch_ankle_pitch(on: bool) -> void:
	if not is_instance_valid(_ankle_pitch):
		var found := get_skeleton().find_children("*", "SkeletalAnklePitch", false, false)
		if found.is_empty():
			return
		_ankle_pitch = found[0] as SkeletonModifier3D
	if _ankle_pitch.active != on:
		_ankle_pitch.active = on


## A sole that the pose pushes under the ground is lifted onto it (that leg is solved again with the
## ankle raised; user report 2026-10-15: the left leg went through the ground in the hammer strikes).
@export var lift_feet: bool = true
## Sole of a foot, in the foot bone's space (as SkeletalAnklePitch): down from the ankle, back to the
## heel, forward to the toes, and half the width (m).
@export var sole_depth: float = 1.05
@export var heel_length: float = 0.91
@export var toe_length: float = 1.73
@export var sole_half_width: float = 0.68
## A lifted sole ends this far above the ground (m): the foot mesh is a little wider than the sole box.
@export var sole_margin: float = 0.05
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
## A + RMB: swing from the left to the right.
@export var hammer_swing_a: MeleeAttack = preload("res://data/melee/hammer_swing_a.tres")
## D + RMB: swing from the right to the left.
@export var hammer_swing_d: MeleeAttack = preload("res://data/melee/hammer_swing_d.tres")

## The wind-up waits this far (s) before the first strike window.
const HOLD_MARGIN := 0.03
## Bones of the pelvis and the legs.
const LEG_BONES: PackedStringArray = ["pelvis", "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]

## True while an attack plays (not its blend out).
var is_playing: bool = false
## Lowest sole point of the last clip pose before the lift, in meters above the ground (for tests).
var sole_low: float = 0.0
## The same after the foot clamp (for tests).
var sole_after: float = 0.0

var _attack: MeleeAttack
var _weapon: MeleeWeapon
var _time: float = 0.0
var _end_time: float = 0.0
var _direction: Vector3 = Vector3.ZERO
## The swings of the running combo (the first attack and its follow-ups) and the one that plays.
var _sequence: Array[MeleeAttack] = []
var _step: int = 0
## True when this swing hit a target, and the seconds since.
var _landed: bool = false
var _since_hit: float = 0.0
## Seconds until the next attack may start.
var _cooldown_left: float = 0.0
## Mouse buttons last frame (the next swing needs a new press).
var _fire_was_held: bool = false
var _left_fire_was_held: bool = false
## Swing after the first of a combo: the pose is blended in from the swing before (_prev_attack held
## at _prev_time), not from the walk pose.
var _chained: bool = false
var _prev_attack: MeleeAttack
var _prev_time: float = 0.0
var _blend_left: float = 0.0
## Strike index -> {target: true}: each strike hits a target once.
var _hit := {}
## Blend out after the attack: the pose is held at _time and fades over the attack's blend_out.
var _fade_left: float = 0.0
## The target the mech turns to and glides toward (null = none), the glide speed and direction.
var _target: Node3D
var _lunge_velocity: float = 0.0
var _lunge_direction: Vector3 = Vector3.ZERO
var _lunge_done: bool = false
var _hold_time: float = 0.0
## Attack -> {bone name: [rotation track, position track]} (-1 = no track).
var _tracks := {}
var _ankle_pitch: SkeletonModifier3D


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


## True while weapon's attack plays (MeleeWeapon.is_busy).
func is_attacking_with(weapon: MeleeWeapon) -> bool:
	return is_playing and _weapon == weapon


## Seconds until the next melee attack may start (0 = ready).
func get_cooldown_left() -> float:
	return _cooldown_left


## True when an attack may start now: no swing plays, the cooldown is over and the mech is free (for the AI).
func is_ready() -> bool:
	return not is_playing and _cooldown_left <= 0.0 and _can_attack()


## Seconds since the swing hit a target while the next swing of a fist combo can still start (a fist
## button press now continues it); -1 when it cannot (for the AI).
func get_combo_wait() -> float:
	if not is_playing or not _landed or _since_hit > combo_window or _step + 1 >= _sequence.size() or _time >= _end_time:
		return -1.0
	return _since_hit


## The mouse button of a melee weapon was pressed: starts the attack for the move key. The next swings
## of a fist combo are read in _watch_combo_input.
func request(weapon: MeleeWeapon) -> void:
	if is_playing or _cooldown_left > 0.0 or not _can_attack():
		return
	var direction := _input_direction()
	if weapon.data.kind == WeaponData.Kind.HAMMER:
		# The hammer needs the right mouse button (user, 2026-10-15); the left button does nothing.
		if not mech.input.fire_held:
			return
		match direction:
			&"back":
				_start(hammer_down, weapon)
			&"left":
				_start(hammer_swing_a, weapon)
			&"right":
				_start(hammer_swing_d, weapon)
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
## &"" (none). A diagonal counts as its side.
func _input_direction() -> StringName:
	var local := Basis(Vector3.UP, mech.get_aim_yaw()).inverse() * mech.input.move_direction
	if Vector2(local.x, local.z).length() < key_dead_zone:
		return &""
	if absf(local.z) > absf(local.x) + 0.1:
		return &"forward" if local.z < 0.0 else &"back"
	return &"left" if local.x < 0.0 else &"right"


## A new attack (a combo's first swing).
func _start(attack: MeleeAttack, weapon: MeleeWeapon) -> void:
	_sequence = [attack]
	_sequence.append_array(attack.follow_ups)
	_step = 0
	_begin_swing(attack, weapon, false)


## Starts one swing. chained = the next swing of a combo: it blends in from the pose of the swing before.
func _begin_swing(attack: MeleeAttack, weapon: MeleeWeapon, chained: bool) -> void:
	if chained:
		_prev_attack = _attack
		_prev_time = _time
		_blend_left = combo_blend
	else:
		_prev_attack = null
		_blend_left = 0.0
	_chained = chained
	_attack = attack
	_weapon = weapon
	_time = 0.0
	_hit = {}
	_landed = false
	_since_hit = 0.0
	_fade_left = 0.0
	_end_time = attack.animation.length
	_lunge_done = false
	_hold_time = 0.0
	if not chained:
		_lunge_velocity = 0.0
	var target := _find_target()
	# A combo keeps its target while it stays in range, even when the aim moved off it.
	if target == null and chained and _is_valid_target(_target) and _flat_offset(_target).length() <= target_range:
		target = _target
	_target = target
	is_playing = true
	_direction = _clip_direction()


## Clip travel direction in the world (model space +Z forward, +X left to the leg frame -Z forward, +X right).
func _clip_direction() -> Vector3:
	var model_direction := _attack.get_direction()
	var direction := mech.global_basis * Vector3(-model_direction.x, 0.0, -model_direction.z)
	direction.y = 0.0
	return direction.normalized()


func _physics_process(delta: float) -> void:
	_watch_combo_input()
	if not is_playing:
		_fade_left = maxf(_fade_left - delta, 0.0)
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		return
	if mech.is_fallen or mech.is_wrecked or (mech.dodge != null and mech.dodge.is_dodging):
		_finish(false)
		return
	# The weapon or its arm broke: the attack stops.
	if not is_instance_valid(_weapon) or _weapon.process_mode == Node.PROCESS_MODE_DISABLED \
			or not is_instance_valid(_weapon.get_model()):
		_finish(true)
		return
	_blend_left = maxf(_blend_left - delta, 0.0)
	if _landed:
		_since_hit += delta
	_track_target(delta)
	var hold := _update_lunge(delta)
	var before := _time
	if not hold:
		_time = minf(_time + delta * _attack.speed_scale, _end_time)
	var speed := maxf(_attack.get_travel_between(before, _time) / maxf(delta, 0.0001), 0.0)
	if _target != null:
		_direction = _clip_direction()
	mech.root_motion_active = true
	mech.root_motion_velocity = _keep_away(_direction * speed + _lunge_direction * _lunge_velocity)
	_strike()
	if _time >= _end_time:
		_finish(true)


## Removes the part of the motion toward any mech closer than the attack's keep_away_distance.
func _keep_away(velocity: Vector3) -> Vector3:
	var limit := _attack.keep_away_distance
	if limit <= 0.0:
		return velocity
	for group in [&"lockable", &"player"]:
		for node in get_tree().get_nodes_in_group(group):
			var other := node as Mech
			if other == null or other == mech or other.is_wrecked:
				continue
			var offset := _flat_offset(other)
			var distance := offset.length()
			if distance > limit or distance < 0.01:
				continue
			var toward := offset / distance
			var closing := velocity.dot(toward)
			if closing > 0.0:
				velocity -= toward * closing
	return velocity


## The next swing of a fist combo: a new press of a fist button after the swing before hit a target.
func _watch_combo_input() -> void:
	var fire := mech.input.fire_held
	var left_fire := mech.input.left_fire_held
	var right_pressed := fire and not _fire_was_held
	var left_pressed := left_fire and not _left_fire_was_held
	_fire_was_held = fire
	_left_fire_was_held = left_fire
	if not is_playing or not _landed or _since_hit > combo_window or _step + 1 >= _sequence.size():
		return
	if _time >= _end_time or weapons == null:
		return
	if not ((right_pressed and _is_fist(weapons.right_weapon)) or (left_pressed and _is_fist(weapons.left_weapon))):
		return
	var next := _sequence[_step + 1]
	var weapon := (weapons.left_weapon if next.left_arm else weapons.right_weapon) as MeleeWeapon
	if not _is_fist(weapon) or weapon.process_mode == Node.PROCESS_MODE_DISABLED or not is_instance_valid(weapon.get_model()):
		return
	_step += 1
	_begin_swing(next, weapon, true)


func _is_fist(weapon: MechWeapon) -> bool:
	return weapon is MeleeWeapon and is_instance_valid(weapon) and weapon.data.kind == WeaponData.Kind.FIST


## The enemy inside the aim cone and within target_range (the one closest to the aim), or null.
func _find_target() -> Node3D:
	var aim := Vector3.ZERO
	if weapons != null and weapons.mech_aim != null:
		aim = weapons.mech_aim.aim_direction
	aim.y = 0.0
	if aim.length() < 0.01:
		aim = Basis(Vector3.UP, mech.get_aim_yaw()) * Vector3.FORWARD
	aim = aim.normalized()
	var best: Node3D = null
	var best_angle := INF
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var other := node as Node3D
		if not _is_valid_target(other):
			continue
		var offset := _flat_offset(other)
		var distance := offset.length()
		if distance > target_range or distance < 0.01:
			continue
		var angle := aim.angle_to(offset / distance)
		# The edge of the target counts, so a crosshair on its side still picks it.
		if angle - atan2(target_half_width, distance) > deg_to_rad(aim_cone_deg):
			continue
		if angle < best_angle:
			best_angle = angle
			best = other
	return best


func _is_valid_target(other: Node3D) -> bool:
	if other == null or not is_instance_valid(other) or other == mech or not other.is_inside_tree() or not other.can_process():
		return false
	return not (other is Mech and (other as Mech).is_wrecked)


## Flat vector from the mech to node (y = 0).
func _flat_offset(node: Node3D) -> Vector3:
	var offset := node.global_position - mech.global_position
	offset.y = 0.0
	return offset


## Turns the mech to face the target until the last strike window ends.
func _track_target(delta: float) -> void:
	if not is_instance_valid(_target) or _attack.strikes.size() == 0 or _time > _attack.strikes[_attack.strikes.size() - 1].y:
		return
	var offset := _flat_offset(_target)
	if offset.length() < 0.5:
		return
	var yaw := atan2(-offset.x, -offset.z)
	var turn := deg_to_rad(turn_speed_deg) * delta
	var step := clampf(wrapf(yaw - mech.rotation.y, -PI, PI), -turn, turn)
	mech.set_heading(wrapf(mech.rotation.y + step, -PI, PI))


## Glides the mech toward the target so the strike lands at the attack's contact distance. The glide
## speed closes the gap (minus the clip's own travel) by the start of the first strike window. When the
## mech is not there yet at the end of the wind-up, the pose waits (returns true) until it arrives.
func _update_lunge(delta: float) -> bool:
	var goal := 0.0
	var hold := false
	if _landed:
		_lunge_done = true
	if is_instance_valid(_target) and not _lunge_done:
		var offset := _flat_offset(_target)
		_lunge_direction = offset.normalized() if offset.length() > 0.01 else _lunge_direction
		var start := _attack.get_strike_start()
		var need := offset.length() - _attack.contact_distance - _attack.get_travel_between(_time, _attack.get_strike_mid())
		var at_end := _time >= start - HOLD_MARGIN
		if need > lunge_tolerance:
			var time_left := maxf((start - _time) / _attack.speed_scale, 0.05)
			goal = minf(need / time_left, lunge_speed)
			if at_end:
				if _hold_time < lunge_hold_time:
					hold = true
					_hold_time += delta
				else:
					_lunge_done = true
					goal = 0.0
		elif at_end:
			_lunge_done = true
	_lunge_velocity = move_toward(_lunge_velocity, goal, lunge_acceleration * delta)
	return hold


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
			_landed = true
			(closest[target][0] as PartHitbox).on_hit(damage, mech.global_position, &"melee")


## The attack ends: the legs are free again and the pose fades out (fade = false: at once, for a
## dodge or a fall that takes over the body). The cooldown starts.
func _finish(fade: bool) -> void:
	is_playing = false
	_fade_left = _attack.blend_out if fade else 0.0
	_cooldown_left = cooldown
	_blend_left = 0.0
	_lunge_velocity = 0.0
	# A dodge clip sets its own root motion.
	if mech.dodge == null or mech.dodge.animation == null or not mech.dodge.animation.is_playing:
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO


func _weight() -> float:
	if _attack == null:
		return 0.0
	if not is_playing:
		return _fade_left / maxf(_attack.blend_out, 0.01)
	if _chained:
		return 1.0
	return clampf(_time / _attack.speed_scale / maxf(_attack.blend_in, 0.01), 0.0, 1.0)


## Bone name -> [rotation track, position track] of an attack's clip (-1 = none).
func _bones_of(attack: MeleeAttack) -> Dictionary:
	if not _tracks.has(attack):
		var map := {}
		for track in attack.animation.get_track_count():
			var type := attack.animation.track_get_type(track)
			if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
				continue
			var bone := String(attack.animation.track_get_path(track).get_concatenated_subnames())
			if not map.has(bone):
				map[bone] = [-1, -1]
			map[bone][0 if type == Animation.TYPE_ROTATION_3D else 1] = track
		_tracks[attack] = map
	return _tracks[attack]


func _clip_rotation(attack: MeleeAttack, track: int, time: float, bone_name: String, rest: Quaternion, fallback: Quaternion) -> Quaternion:
	if track < 0:
		return fallback
	var rotation := attack.animation.rotation_track_interpolate(track, time)
	if limits == null or (free_legs and bone_name in LEG_BONES):
		return rotation
	return limits.clamp_rotation(bone_name, rest, rotation)


func _process_modification_with_delta(_delta: float) -> void:
	var weight := smoothstep(0.0, 1.0, _weight())
	_switch_ankle_pitch(weight <= 0.0)
	if weight <= 0.0:
		return
	var skeleton := get_skeleton()
	# An arm that holds a shield or a gun (IK to its grip) keeps it: the clip leaves that arm out.
	var keep_left := weapons != null and weapons.arm_ik_left.target != null
	var keep_right := weapons != null and weapons.arm_ik_right.target != null and weapons.arm_ik_right.can_process()
	var bones := _bones_of(_attack)
	# Blending in from the swing before: its pose (held at _prev_time) fades into this clip.
	var mix := 1.0
	var before := {}
	if _blend_left > 0.0 and _prev_attack != null:
		before = _bones_of(_prev_attack)
		mix = smoothstep(0.0, 1.0, 1.0 - _blend_left / maxf(combo_blend, 0.01))
	var names: Array = bones.keys()
	for bone_name: String in before:
		if not bones.has(bone_name):
			names.append(bone_name)
	for bone_name: String in names:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		if bone_name in SkeletalDodgeAnimation.ARM_BONES and ((keep_left and bone_name.ends_with("_L")) or (keep_right and bone_name.ends_with("_R"))):
			continue
		var now: Array = bones.get(bone_name, [-1, -1])
		var then: Array = before.get(bone_name, [-1, -1])
		if now[0] >= 0 or then[0] >= 0:
			var under := skeleton.get_bone_pose_rotation(bone)
			var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			var value := _clip_rotation(_attack, now[0], _time, bone_name, rest, under)
			if mix < 1.0:
				value = _clip_rotation(_prev_attack, then[0], _prev_time, bone_name, rest, under).slerp(value, mix)
			skeleton.set_bone_pose_rotation(bone, under.slerp(value, weight))
		if now[1] >= 0 or then[1] >= 0:
			var under_position := skeleton.get_bone_pose_position(bone)
			var position := under_position
			if now[1] >= 0:
				position = _attack.animation.position_track_interpolate(now[1], _time)
			if mix < 1.0:
				var from := under_position
				if then[1] >= 0:
					from = _prev_attack.animation.position_track_interpolate(then[1], _prev_time)
				position = from.lerp(position, mix)
			skeleton.set_bone_pose_position(bone, under_position.lerp(position, weight))
	_clamp_feet(skeleton)
	if arm_rig != null:
		arm_rig.refresh_torso()


## A sole under the ground (the clip bends the legs into it; the joint limits bend them further):
## each such leg is solved again with its ankle raised by that depth (two-bone IK about the hip, the
## knee keeps its side, the foot keeps its turn). The bone poses are chained here by hand: the
## skeleton's cached global poses are not updated yet while the modifiers run.
func _clamp_feet(skeleton: Skeleton3D) -> void:
	sole_low = 0.0
	sole_after = 0.0
	var to_mech := mech.global_transform.affine_inverse() * skeleton.global_transform
	var up := (to_mech.affine_inverse().basis * Vector3.UP).normalized()
	for side in ["L", "R"]:
		var thigh := skeleton.find_bone("thigh_" + side)
		var shin := skeleton.find_bone("shin_" + side)
		var foot := skeleton.find_bone("foot_" + side)
		if thigh < 0 or shin < 0 or foot < 0:
			continue
		var hip_frame := _chain_pose(skeleton, skeleton.get_bone_parent(thigh))
		var thigh_pose := hip_frame * skeleton.get_bone_pose(thigh)
		var shin_pose := thigh_pose * skeleton.get_bone_pose(shin)
		var foot_pose := shin_pose * skeleton.get_bone_pose(foot)
		var sole := to_mech * foot_pose
		var depth := 0.0
		for corner in [Vector3(-sole_half_width, -heel_length, -sole_depth), Vector3(sole_half_width, -heel_length, -sole_depth),
				Vector3(-sole_half_width, toe_length, -sole_depth), Vector3(sole_half_width, toe_length, -sole_depth)]:
			depth = maxf(depth, -(sole * corner).y)
		sole_low = minf(sole_low, -depth)
		if depth > 0.001 and lift_feet:
			_raise_ankle(skeleton, [thigh, shin, foot], hip_frame, [thigh_pose, shin_pose, foot_pose], up * (depth + sole_margin))
		var after := to_mech * _chain_pose(skeleton, foot)
		for corner in [Vector3(-sole_half_width, -heel_length, -sole_depth), Vector3(sole_half_width, -heel_length, -sole_depth),
				Vector3(-sole_half_width, toe_length, -sole_depth), Vector3(sole_half_width, toe_length, -sole_depth)]:
			sole_after = minf(sole_after, (after * corner).y)


## Two-bone solve: the ankle moves by lift (skeleton space), the thigh and shin turn, the foot keeps its
## world turn. poses = the thigh, shin and foot poses in skeleton space.
func _raise_ankle(skeleton: Skeleton3D, bones: Array, hip_frame: Transform3D, poses: Array, lift: Vector3) -> void:
	var hip: Vector3 = (poses[0] as Transform3D).origin
	var knee: Vector3 = (poses[1] as Transform3D).origin
	var ankle: Vector3 = (poses[2] as Transform3D).origin
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(ankle)
	var reach := ankle + lift - hip
	var distance := clampf(reach.length(), 0.01, upper + lower - 0.001)
	var along := reach.normalized()
	var cos_hip := clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0)
	# The knee stays on the side it bends to now.
	var side := (knee - hip) - along * (knee - hip).dot(along)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.FORWARD
	var new_knee := hip + along * upper * cos_hip + side * upper * sqrt(1.0 - cos_hip * cos_hip)
	var new_ankle := hip + along * distance
	var thigh_swing := Basis(Quaternion((knee - hip).normalized(), (new_knee - hip).normalized()))
	var thigh_basis := (thigh_swing * (poses[0] as Transform3D).basis).orthonormalized()
	var shin_basis := thigh_swing * (poses[1] as Transform3D).basis
	var shin_direction := (thigh_swing * (ankle - knee)).normalized()
	shin_basis = (Basis(Quaternion(shin_direction, (new_ankle - new_knee).normalized())) * shin_basis).orthonormalized()
	var foot_basis := (poses[2] as Transform3D).basis.orthonormalized()
	skeleton.set_bone_pose_rotation(bones[0], (hip_frame.basis.orthonormalized().inverse() * thigh_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(bones[1], (thigh_basis.inverse() * shin_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(bones[2], (shin_basis.inverse() * foot_basis).get_rotation_quaternion())


## Skeleton space pose of a bone from the local poses (root to bone).
func _chain_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var pose := Transform3D.IDENTITY
	while bone >= 0:
		pose = skeleton.get_bone_pose(bone) * pose
		bone = skeleton.get_bone_parent(bone)
	return pose
