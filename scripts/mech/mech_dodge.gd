class_name MechDodge
extends Node
## Double tap Space for a dodge hop: a quick, low hop in the chosen direction.
## Directions: A / D = side, W = forward, S or no key = back. While boosting: always forward.
## While boosting, the first Space press waits for the double tap before the jump charge starts,
## so the boost does not stop. Costs energy.
## In the air the mech leans into the hop and tucks its legs a little. It lands in a small crouch and
## springs upright. Ending: a short skid (feet slide with dust, two small brake thrusters fire),
## then two steps to a stop.
## No landing delay.
## A mech with a SkeletalDodgeAnimation plays a dodge animation (roll or step) instead of the hop
## (user requests 2026-10-13); the clip depends on the direction, the weight class and the speed.
## A dodge animation ends into the walk at once when a move key is held, at the walk speed or the dodge
## speed if that is higher (user request 2026-10-22: no slow steps after a dodge step).
## A shield with WeaponData.blocks_dodge (Hex Shield) turns every dodge into a shield dash (user request
## 2026-10-16): the mech dashes forward behind the raised shield, bashes a mech in its way (ShieldBash)
## and stops. A mech with that shield and no SkeletalDodgeAnimation cannot dodge. A heavily compromised
## leg strains on a roll or a shield dash and slows it (MechLegStrain).

signal dodge_started
signal dodge_ended

@export var mech: Mech
@export var input: MechInput
@export var energy: MechEnergy
@export var landing_recovery: MechLandingRecovery
@export var kneel: MechKneel
## Optional. Dodge animations instead of the hop.
@export var animation: SkeletalDodgeAnimation
## Damage and slowdown of heavily compromised legs on a roll. Made in _ready when not set.
@export var leg_strain: MechLegStrain
## The hit of the shield dash. Made in _ready when not set.
@export var shield_bash: ShieldBash
## The shield comes up this fast during the dash (1 / seconds; MechShield.raise_speed is slower).
@export var dash_shield_raise_speed: float = 6.0
## Two Space presses closer than this (seconds) start a dodge.
@export var double_tap_window: float = 0.3
## Hop length, in meters.
@export var distance: float = 11.9
## Hop height, in meters.
@export var hop_height: float = 1.5
@export var energy_cost: float = 25.0
## Speed kept in the hop direction at the landing (m/s). The skid slows the mech down from it.
@export var landing_speed: float = 10.0

## Skid length after the landing, in meters (until the steps start). The brake thrusters fire.
@export var skid_distance: float = 5.3
## Skid length for a dodge that starts while boosting, in meters.
@export var boost_skid_distance: float = 28.0
## Skid time for a dodge that starts while boosting, in seconds. With the distance this sets the
## speed: the boost dodge hops and lands at 2 x distance / time - skid end speed (about 20.9 m/s).
@export var boost_skid_time: float = 2.25
## Stride lengths (meters) of the two steps after the skid.
@export var stop_strides: PackedFloat32Array = PackedFloat32Array([1.5, 1.5])
## After the landing the mech cannot move for this long, in seconds.
@export var recovery_time: float = 0.2

@export_group("Recovery")
## The mech leans into the hop and lands in a small crouch with the torso leaned toward the
## hop direction. Then one damped spring brings the body upright.
@export var recover_lean_deg: float = 10.0
## Knee crouch at the landing, in degrees of hip bend (knees bend twice as much).
@export var recover_crouch_deg: float = 20.0
## Spring speed (swings per second). Lower = slower recovery.
@export var recover_frequency: float = 1.2
## Spring damping. Lower = more swing past upright.
@export_range(0.05, 1.0) var recover_damping: float = 0.45
@export_group("")

var is_dodging: bool = false
## World direction of the current dodge.
var direction: Vector3 = Vector3.ZERO

var _clock: float = 0.0
var _last_press: float = -10.0
var _air_time: float = 0.0
var _flight_time: float = 1.0
var _recover_left: float = 0.0
var _suppress_jump: bool = false
## Dodge direction in the leg frame (-Z forward, +X right).
var _local_direction: Vector3 = Vector3.BACK
var _recover := AimSpring.new(0.0)
var _recovering: bool = false
## Time left in the double tap window after a Space press during a boost.
var _boost_tap_left: float = 0.0
var _from_boost: bool = false
## True when the dodge started while running or boosting (it keeps its momentum, no landing penalty).
var _from_fast: bool = false
## True while the dodge clip is the roll (it ends with no slow-down).
var _rolling: bool = false
## True while the dodge clip is the shield dash (the shield is held up).
var _dashing: bool = false
var _weapons: WeaponController


func _ready() -> void:
	# Before the jump charge (-5) and the Mech (0).
	process_physics_priority = -6
	mech.landed.connect(_on_landed)
	_weapons = mech.get_node_or_null("WeaponController") as WeaponController
	if leg_strain == null:
		leg_strain = MechLegStrain.new()
		leg_strain.name = "LegStrain"
		leg_strain.mech = mech
		add_child(leg_strain)
	if shield_bash == null:
		shield_bash = ShieldBash.new()
		shield_bash.name = "ShieldBash"
		shield_bash.mech = mech
		shield_bash.dodge = self
		add_child(shield_bash)


## True when the mech carries a shield that turns the dodge into a dash (WeaponData.blocks_dodge, the
## Hex Shield). A broken shield (MechShield.enabled false) does not.
func has_dash_shield() -> bool:
	if _weapons == null or _weapons.left_data == null or not _weapons.left_data.blocks_dodge:
		return false
	return _weapons.mech_shield == null or _weapons.mech_shield.enabled


## True when the dodge input starts the shield dash.
func is_shield_dash() -> bool:
	return has_dash_shield() and animation != null and animation.shield_dash != null


## True when the mech carries a dodge-blocking shield and cannot dash either (no dodge animation).
func is_blocked_by_shield() -> bool:
	return has_dash_shield() and not is_shield_dash()


## True while a dodge animation (not the hop) plays.
func is_rolling() -> bool:
	return animation != null and animation.is_playing


## True while the mech slides on after a dodge animation (dust from the feet).
func is_sliding() -> bool:
	return animation != null and animation.is_sliding()


## True while hopping or recovering. The mech cannot move, boost, or turn.
func is_busy() -> bool:
	return is_dodging or _recover_left > 0.0


## True while the Space press that started the dodge is still held, or while a boost waits for
## the second tap. The jump charge waits.
func blocks_jump() -> bool:
	return is_busy() or _suppress_jump or _boost_tap_left > 0.0


## True while the hop or its recovery spring moves the body. InertiaSway pauses then.
func is_animating() -> bool:
	return is_dodging or _recovering


## 0 to 1: how much the legs tuck in (most at the top of the hop).
func get_tuck() -> float:
	if not is_dodging or is_rolling():
		return 0.0
	return 0.5 * sin(_get_air_progress() * PI)


## Recovery pose amount: grows toward 1 while the hop comes down, then springs to 0 after the
## landing (it can go a little below 0 on the swing past upright).
func get_recovery_pose() -> float:
	if is_rolling():
		return 0.0
	if is_dodging:
		return smoothstep(0.0, 1.0, _get_air_progress())
	return _recover.value


## Torso lean toward the hop direction now, in degrees: x = forward lean, y = roll (head left).
func get_recovery_lean() -> Vector2:
	var amount := get_recovery_pose() * recover_lean_deg
	return Vector2(-_local_direction.z * amount, -_local_direction.x * amount)


func _physics_process(delta: float) -> void:
	_clock += delta
	_recover_left = maxf(_recover_left - delta, 0.0)
	if is_dodging:
		_air_time += delta
	if _recovering:
		_recover.update(0.0, recover_frequency, recover_damping, 10.0, delta)
		if absf(_recover.value) < 0.002 and absf(_recover.velocity) < 0.01:
			_recover.value = 0.0
			_recovering = false
	_boost_tap_left = maxf(_boost_tap_left - delta, 0.0)
	if _dashing and _weapons != null and _weapons.mech_shield != null:
		# MechShield (later in the frame) moves the shield up slower: the dash lifts it faster.
		var shield := _weapons.mech_shield
		shield.amount = move_toward(shield.amount, 1.0, dash_shield_raise_speed * delta)
	if not input.jump_held:
		_suppress_jump = false
	if input.jump_pressed and mech.is_boosting and mech.is_on_floor() and _boost_tap_left <= 0.0 \
			and not is_blocked_by_shield():
		_boost_tap_left = double_tap_window
	if input.jump_pressed:
		if _clock - _last_press <= double_tap_window and _can_start():
			_start()
		_last_press = _clock


## Landing speed of a boost dodge that gives boost_skid_distance in boost_skid_time.
func _get_boost_landing_speed() -> float:
	return 2.0 * boost_skid_distance / boost_skid_time - mech.skid_end_speed


func _get_air_progress() -> float:
	return clampf(_air_time / _flight_time, 0.0, 1.0)


func _can_start() -> bool:
	return mech.is_on_floor() and not mech.is_fallen and not is_busy() and not landing_recovery.is_recovering() \
			and not kneel.is_kneeling and not mech.is_skidding and energy.current >= energy_cost \
			and not is_blocked_by_shield()


func _start() -> void:
	energy.try_drain(energy_cost)
	# Direction in the leg frame: -Z forward, +X right.
	var local := Vector3(0.0, 0.0, 1.0)  # No key: back.
	_from_boost = mech.is_boosting
	_from_fast = mech.is_boosting or mech.is_running
	if mech.is_boosting:
		local = Vector3(0.0, 0.0, -1.0)  # Boosting: forward.
	elif input.turn_input > 0.5:
		local = Vector3(-1.0, 0.0, 0.0)  # A: left.
	elif input.turn_input < -0.5:
		local = Vector3(1.0, 0.0, 0.0)  # D: right.
	elif input.forward_held:
		local = Vector3(0.0, 0.0, -1.0)  # W: forward.
	var dash := is_shield_dash()
	if dash:
		local = Vector3(0.0, 0.0, -1.0)  # The shield dash always goes forward.
	_local_direction = local
	direction = (mech.global_basis * local).normalized()
	var clip := animation.shield_dash if dash else (animation.pick(local) if animation != null else null)
	if clip != null:
		_start_animation(clip)
		return
	# Launch speeds for the hop height and length.
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * mech.gravity_scale
	var up_speed := sqrt(2.0 * gravity * hop_height)
	_flight_time = 2.0 * up_speed / gravity
	var side_speed := distance / _flight_time
	if _from_boost:
		side_speed = maxf(side_speed, _get_boost_landing_speed())  # Keeps the boost momentum.
	mech.velocity = direction * side_speed + Vector3.UP * up_speed
	is_dodging = true
	_air_time = 0.0
	_recovering = false
	_last_press = -10.0
	_boost_tap_left = 0.0
	_suppress_jump = true
	dodge_started.emit()


## A dodge animation: no hop; SkeletalDodgeAnimation moves the mech on the ground and calls _end_roll.
func _start_animation(clip: DodgeClip) -> void:
	is_dodging = true
	_recovering = false
	_last_press = -10.0
	_boost_tap_left = 0.0
	_suppress_jump = true
	# A heavily compromised leg: the roll is slower (checked before the roll hurts the leg).
	var speed_factor := 1.0
	# The shield dash counts as a roll for the legs and the end (user rule 2026-10-16).
	_dashing = clip == animation.shield_dash
	_rolling = clip == animation.roll or _dashing
	if _rolling and leg_strain != null:
		speed_factor = leg_strain.get_roll_speed_factor()
		leg_strain.strain_roll()
	animation.start(clip, _local_direction, _from_boost, _end_roll, speed_factor)
	if _dashing:
		shield_bash.begin()
		if _weapons != null and _weapons.mech_shield != null:
			_weapons.mech_shield.force_up = true
	dodge_started.emit()


func _end_roll() -> void:
	is_dodging = false
	if _dashing:
		_dashing = false
		if _weapons != null and _weapons.mech_shield != null:
			_weapons.mech_shield.force_up = false
	# A move key ended the dodge (SkeletalDodgeAnimation.release_at): walk at once, no slow steps
	# (user request 2026-10-22; the quick step slow-down of 2026-10-15 is gone).
	var walks_on := input.move_direction.length_squared() > 0.01
	_recover_left = 0.0 if walks_on else recovery_time
	if walks_on and not mech.is_fallen and not mech.is_wrecked:
		mech.start_dodge_exit()
	dodge_ended.emit()


func _on_landed(_fall_speed: float) -> void:
	if not is_dodging or is_rolling():
		return
	is_dodging = false
	# Keep some speed in the hop direction. The braked skid slows it down, then two steps to a stop.
	var speed := _get_boost_landing_speed() if _from_boost else landing_speed
	var keep := direction * speed
	mech.velocity.x = keep.x
	mech.velocity.z = keep.z
	# Slowdown that ends the skid (at the Mech skid end speed) after the skid distance.
	var end_speed := mech.skid_end_speed
	var skid_length := boost_skid_distance if _from_boost else skid_distance
	var slowdown := maxf((speed * speed - end_speed * end_speed) / (2.0 * skid_length), 0.5)
	mech.cancel_landing_steps()
	# Only a forward dodge ends with the Akira slide (not back, left or right).
	mech.start_skid(stop_strides, slowdown, true, _local_direction.z < -0.5)
	_recover_left = recovery_time
	# Start the recovery spring from the full landing pose.
	_recover.value = 1.0
	_recover.velocity = 0.0
	_recovering = true
	dodge_ended.emit()
