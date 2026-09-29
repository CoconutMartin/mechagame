class_name MechFall
extends Node
## Makes the mech fall over: optional side steps first, then it topples over a foot edge (slow at
## first, then faster), hits the ground with a small bounce, slides, can roll over along its length,
## and (if it is still alive) pushes itself up and stands again. It turns the Visual node; the
## FallPose node moves the arms and legs, and the Mech body slides (Mech.is_fallen or wrecked).
## Every fall damages all parts by fall_damage of their max HP when the mech hits the ground.
## Fall direction: the way the mech moves, or its front when it stands still.
## A mech with one leg left falls over when it stops boosting (no roll; it gets up once the slide
## ends), after
## a dodge hop, when it lands after a jump, and when a pile bunker punch hits nothing.

signal landed
signal finished

enum State { IDLE, STEPS, FALL, IMPACT, SETTLE, ROLL, REPOSITION, LIE, GET_UP }

@export var mech: Mech
@export var visual: Node3D
## The normal animation nodes. They stop while the mech is down.
@export var animation: Node
@export var camera_shake: CameraShake
@export var dodge: MechDodge
## The right arm lower bone: the held weapon hangs from it while the mech is down.
@export var elbow_right: Node3D
@export var torso: Node3D

@export_group("Fall")
## Distance from the mech center to the foot edge it tips over, and the lift that keeps the body
## on top of the ground when it lies down, in meters.
@export var pivot_distance: float = 1.5
@export var lie_lift: float = 0.4
## Topple time in seconds (slow at first, then faster, like a falling pole).
@export var fall_time: float = 1.0
## Bounce when the body hits the ground: rebound in degrees and time in seconds.
@export var bounce_deg: float = 4.0
@export var impact_time: float = 0.45
## Extra slowdown (m/s²) while the body scrapes along the ground, and while it rolls.
@export var ground_friction: float = 14.0
@export var roll_friction: float = 2.0
## Damage to every part when the mech hits the ground, as a part of its max HP.
@export_range(0.0, 1.0) var fall_damage: float = 0.05
@export_group("Steps")
## Side steps before a fall: step count, time for each step, side speed (m/s), sway in degrees.
@export var step_count: int = 2
@export var step_time: float = 0.5
@export var step_speed: float = 2.4
@export var step_sway_deg: float = 5.0
@export_group("Roll and get up")
## Average roll speed in degrees per second (180 = 75% slower than 720). The roll starts and ends
## slowly (eased), and takes at least roll_min_time seconds.
@export var roll_speed_deg: float = 180.0
@export var roll_min_time: float = 0.9
## The body rests this long after the impact before it rolls, in seconds.
@export var settle_time: float = 0.4
## Extra height of the body center when it lies on its side (wide shoulders) and on its back
## (backpack), compared with lying face down, in meters. Keeps it on top of the ground while it rolls.
@export var side_lift: float = 1.4
@export var back_lift: float = 0.6
## Face down, before the get-up: the hands come under the shoulders and the chest lifts a little.
@export var reposition_time: float = 0.8
@export var reposition_deg: float = 4.0
## Time face down before getting up when there is no roll, and the get-up time, in seconds.
@export var lie_time: float = 0.8
@export var get_up_time: float = 2.4
## A fall that waits for the slide to end (the boost fall) gets up when the speed is below this (m/s).
@export var stopped_speed: float = 0.3
## One leg left: a landing this fast or faster (m/s down) makes the mech fall toward the broken leg.
@export var landing_fall_speed: float = 2.0
## Moving slower than this (m/s) counts as standing still (neutral fall).
@export var neutral_speed: float = 1.5

var state: State = State.IDLE
## Fall direction in the mech's own space (flat).
var local_direction := Vector3.FORWARD
## Tilt now (0 = standing, PI/2 = lying) and roll now, in radians.
var angle: float = 0.0
var roll: float = 0.0
## Time in the current state and its length (FallPose reads them).
var state_time: float = 0.0

var _direction := Vector3.FORWARD
var _step_side := Vector3.ZERO
## Roll to do after the impact (the turn to face down), in radians.
var _roll_total: float = 0.0
## Roll face down before the get-up (false for the boost fall).
var _face_down: bool = true
## True when the roll ends face down: the mech is then turned to face its head direction, so the
## get-up always starts from a front fall.
var _face_down_roll: bool = false
var _get_up: bool = false
var _sway: float = 0.0
var _base := Transform3D.IDENTITY
var _was_boosting: bool = false
var _pending_landing: bool = false
var _pending_back_if_still: bool = false


func _ready() -> void:
	# Before the Mech moves (0), so the side step speed is used this frame.
	process_physics_priority = -1
	mech.fall_control = self
	mech.landed.connect(_on_mech_landed)
	if dodge != null:
		dodge.dodge_ended.connect(_on_dodge_ended)


## Starts a fall toward direction (world, flat; zero = the way the mech moves, or its front).
## steps: world side direction for the side steps (zero = no steps). get_up: stand up at the end
## (the mech is alive). face_down: roll face down before the get-up; false = no roll and no turn,
## the mech gets up from the way it lies as soon as the slide ends (the boost fall).
func fall(direction: Vector3 = Vector3.ZERO, steps: Vector3 = Vector3.ZERO, get_up: bool = true, face_down: bool = true) -> void:
	if state != State.IDLE:
		return
	_pending_landing = false
	if direction.is_zero_approx():
		direction = get_motion_direction()
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_step_side = Vector3(steps.x, 0.0, steps.z).normalized()
	_get_up = get_up
	_face_down = face_down
	_base = visual.transform
	angle = 0.0
	roll = 0.0
	_sway = 0.0
	if not mech.is_wrecked:
		mech.start_fall()
		# The held weapon hangs from the hand while the mech is down.
		var weapon := _right_weapon()
		if weapon != null and elbow_right != null:
			weapon.reparent(elbow_right, true)
	freeze_animation()
	_set_state(State.STEPS if _step_side != Vector3.ZERO and step_count > 0 else State.FALL)


## Falls over when the mech lands (a leg broke in the air). back_if_still: with no speed, fall
## backwards instead of forwards.
func fall_on_landing(back_if_still: bool = false) -> void:
	_pending_landing = true
	_pending_back_if_still = back_if_still


## The way the mech moves (flat), or its front when it stands still.
func get_motion_direction(back_if_still: bool = false) -> Vector3:
	var velocity := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	if velocity.length() >= neutral_speed:
		return velocity.normalized()
	var front := -mech.global_basis.z
	return -front if back_if_still else front


## Fall direction in the world (flat).
func get_world_direction() -> Vector3:
	return _direction


func is_down() -> bool:
	return state != State.IDLE


## Stops the normal animation nodes (flames off first).
func freeze_animation() -> void:
	if animation == null or animation.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	for child in animation.get_children():
		if child.has_method(&"cut"):
			child.cut()
	animation.process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(delta: float) -> void:
	_watch_boost()
	if state == State.IDLE:
		return
	state_time += delta
	_scrape(delta)
	match state:
		State.STEPS:
			var total := step_time * step_count
			mech.velocity.x = _step_side.x * step_speed
			mech.velocity.z = _step_side.z * step_speed
			# A small sway to the side with each step.
			_sway = sin(state_time / step_time * PI) * deg_to_rad(step_sway_deg)
			if state_time >= total:
				_sway = 0.0
				_set_state(State.FALL)
		State.FALL:
			var t := clampf(state_time / fall_time, 0.0, 1.0)
			# A falling pole: slow at first, then faster.
			angle = PI * 0.5 * (1.0 - cos(t * PI * 0.5))
			if t >= 1.0:
				_on_impact()
				_set_state(State.IMPACT)
		State.IMPACT:
			var t := clampf(state_time / impact_time, 0.0, 1.0)
			# One small rebound, then the body settles.
			angle = PI * 0.5 - deg_to_rad(bounce_deg) * sin(t * PI) * (1.0 - t)
			if t >= 1.0:
				angle = PI * 0.5
				_plan_roll()
				_set_state(State.SETTLE if absf(_roll_total) > 0.02 else State.LIE)
		State.SETTLE:
			if state_time >= settle_time:
				_set_state(State.ROLL)
		State.ROLL:
			var duration := get_roll_time()
			roll = _roll_total * smoothstep(0.0, 1.0, clampf(state_time / duration, 0.0, 1.0))
			if state_time >= duration:
				_end_roll()
		State.REPOSITION:
			angle = PI * 0.5 - deg_to_rad(reposition_deg) * smoothstep(0.0, 1.0, clampf(state_time / reposition_time, 0.0, 1.0))
			if state_time >= reposition_time:
				_set_state(State.GET_UP)
		State.LIE:
			var ready := state_time >= lie_time
			if not _face_down:
				# Get up once the slide ends.
				ready = Vector2(mech.velocity.x, mech.velocity.z).length() < stopped_speed and state_time >= 0.2
			if _get_up and not mech.is_wrecked and ready:
				_set_state(State.REPOSITION)
		State.GET_UP:
			if mech.is_wrecked:
				_set_state(State.LIE)
			else:
				angle = get_up_angle(state_time / get_up_time)
				if state_time >= get_up_time:
					_finish()
					return
	visual.transform = _get_transform() * _base


## After the impact (for a mech that gets up and rolls face down): the turn along the body that
## brings its front to the ground.
func _plan_roll() -> void:
	_roll_total = 0.0
	_face_down_roll = _face_down and _get_up and not mech.is_wrecked
	if not _face_down_roll:
		return
	var axis := _direction
	var front := -visual.global_basis.z.normalized()
	var across := front - axis * front.dot(axis)
	if across.length_squared() < 0.0001:
		return
	across = across.normalized()
	_roll_total += atan2(across.cross(Vector3.DOWN).dot(axis), across.dot(Vector3.DOWN))


## The roll is done. Face down: the mech turns to face its head direction and the pose becomes a
## plain front fall (it looks the same), so the get-up works the same way after any fall.
func _end_roll() -> void:
	roll = 0.0
	if _face_down_roll:
		var head := visual.global_basis.y
		head.y = 0.0
		if head.length_squared() > 0.0001:
			head = head.normalized()
			mech.set_heading(atan2(-head.x, -head.z))
			_direction = head
			_base = Transform3D.IDENTITY
	_set_state(State.REPOSITION if _get_up and not mech.is_wrecked else State.LIE)


## Length of the roll now, in seconds.
func get_roll_time() -> float:
	return maxf(roll_min_time, absf(_roll_total) / deg_to_rad(roll_speed_deg))


## A body on the ground slows down fast (the Mech adds its own slide slowdown).
func _scrape(delta: float) -> void:
	var friction := 0.0
	match state:
		State.IMPACT:
			friction = ground_friction
		State.SETTLE, State.REPOSITION, State.LIE, State.GET_UP:
			friction = ground_friction
		State.ROLL:
			friction = roll_friction
	if friction <= 0.0:
		return
	var slide := Vector2(mech.velocity.x, mech.velocity.z).move_toward(Vector2.ZERO, friction * delta)
	mech.velocity.x = slide.x
	mech.velocity.z = slide.y


## Tilt during the get-up (t = 0 to 1): push up on the arms, pause while the knee comes under the
## body, then rise.
static func get_up_angle(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var deg: float
	if t < 0.3:
		deg = lerpf(86.0, 62.0, smoothstep(0.0, 1.0, t / 0.3))
	elif t < 0.5:
		deg = lerpf(62.0, 52.0, smoothstep(0.0, 1.0, (t - 0.3) / 0.2))
	else:
		deg = lerpf(52.0, 0.0, smoothstep(0.0, 1.0, (t - 0.5) / 0.5))
	return deg_to_rad(deg)


## Tip over a foot edge, lift onto the body surface, roll along the body, sway for the steps.
func _get_transform() -> Transform3D:
	var local := (mech.global_basis.inverse() * _direction)
	local.y = 0.0
	local = local.normalized() if local.length_squared() > 0.001 else Vector3.FORWARD
	local_direction = local
	var pivot := local * pivot_distance
	var axis := Vector3.UP.cross(local).normalized()
	var tip := Transform3D(Basis(axis, angle), Vector3.ZERO)
	var result := Transform3D(Basis.IDENTITY, pivot) * tip * Transform3D(Basis.IDENTITY, -pivot)
	var lift := Vector3.UP * lie_lift * sin(angle)
	result = Transform3D(Basis.IDENTITY, lift) * result
	if roll != 0.0:
		var center := pivot + Vector3.UP * (pivot_distance + lie_lift)
		result = Transform3D(Basis.IDENTITY, center) * Transform3D(Basis(local, roll), Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -center) * result
	# The body is wider across the shoulders than it is deep, and deeper at the back (backpack):
	# lying on its side or back, it rests higher.
	var body := result.basis * _base.basis
	var on_side := absf(body.x.normalized().y)
	var on_back := maxf(-body.z.normalized().y, 0.0)
	result = Transform3D(Basis.IDENTITY, Vector3.UP * (side_lift * on_side + back_lift * on_back)) * result
	if _sway != 0.0:
		var side := mech.global_basis.inverse() * _step_side
		var sway_axis := Vector3.UP.cross(side.normalized()).normalized()
		result = Transform3D(Basis(sway_axis, _sway), Vector3.ZERO) * result
	return result


## The body hits the ground: shake, and every part takes fall damage.
func _on_impact() -> void:
	landed.emit()
	if camera_shake != null:
		camera_shake.add_shake(0.5, 0.6)
	var health := mech.health
	if health == null or fall_damage <= 0.0:
		return
	for key: String in health.max_hp.keys():
		if health.is_part_alive(key):
			health.damage(key, health.max_hp[key] * fall_damage)


func _finish() -> void:
	visual.transform = _base
	angle = 0.0
	state = State.IDLE
	mech.end_fall()
	var weapon := _right_weapon()
	if weapon != null and torso != null and weapon.get_parent() != torso:
		weapon.reparent(torso, true)
	if animation != null:
		for child in animation.get_children():
			if child.has_method(&"reset_after_fall"):
				child.reset_after_fall()
		animation.process_mode = Node.PROCESS_MODE_INHERIT
	finished.emit()


func _set_state(next: State) -> void:
	state = next
	state_time = 0.0


func _right_weapon() -> Node3D:
	var controller := mech.get_node_or_null("WeaponController") as WeaponController
	return controller.right_weapon if controller != null else null


## Landing: a mech whose legs broke in the air falls over; a living mech with one leg left falls
## toward the broken leg after any real landing (a dodge hop lands in its own fall).
func _on_mech_landed(fall_speed: float) -> void:
	if state != State.IDLE or (dodge != null and dodge.is_dodging):
		_pending_landing = false
		return
	if mech.is_wrecked:
		if _pending_landing:
			_pending_landing = false
			fall(get_motion_direction(_pending_back_if_still), Vector3.ZERO, false)
		return
	if not mech.one_leg or (not _pending_landing and fall_speed < landing_fall_speed):
		_pending_landing = false
		return
	_pending_landing = false
	var broken_side := mech.global_basis.x * signf(mech.broken_leg_side)
	fall(broken_side)


## One leg left: a dodge hop ends in a fall (in the hop direction).
func _on_dodge_ended() -> void:
	if mech.one_leg and not mech.is_wrecked and state == State.IDLE:
		fall(dodge.direction)


## One leg left: the mech falls over when the boost stops (on the ground), slides, and gets up
## as soon as the slide ends (no roll, no turn).
func _watch_boost() -> void:
	var boosting := mech.is_boosting
	if _was_boosting and not boosting and mech.one_leg and not mech.is_wrecked and state == State.IDLE \
			and mech.is_on_floor():
		fall(Vector3.ZERO, Vector3.ZERO, true, false)
	_was_boosting = boosting
