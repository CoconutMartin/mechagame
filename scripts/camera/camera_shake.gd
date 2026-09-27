class_name CameraShake
extends Camera3D
## Shakes the camera on heavy footsteps and hard landings.
## Uses the camera's h_offset and v_offset, so it does not fight the spring arm.

@export var mech: Mech
@export var footsteps: MechFootsteps

@export_group("Footstep")
## Downward camera jolt per footstep, in meters.
@export var footstep_kick: float = 0.117
@export var footstep_trauma: float = 0.2
## Mech height (meters) for the footstep values above. Taller mechs shake more.
@export var footstep_reference_height: float = 10.0

@export_group("Landing")
## Shake added per m/s of fall speed at landing.
@export var landing_trauma_per_speed: float = 0.045
@export var landing_kick_per_speed: float = 0.05

@export_group("Wall Bump")
## Shake added per m/s of speed into a wall.
@export var bump_trauma_per_speed: float = 0.05
## Camera drop per wall bump, in meters (before intensity: 0.267 x 0.75 = 0.2 m).
@export var bump_kick: float = 0.267

@export_group("Movement Start Kicks")
## One camera drop at the start of each movement, in meters (before intensity: 0.267 x 0.75 = 0.2 m).
@export var boost_start_kick: float = 0.267
@export var skid_start_kick: float = 0.267
@export var takeoff_kick: float = 0.267
## At the top of a jump, when the fall starts.
@export var fall_start_kick: float = 0.267
## At the start and the end of a dodge roll.
@export var dodge_start_kick: float = 0.267
@export var dodge_end_kick: float = 0.267
## Optional: the dodge node, for the dodge kicks.
@export var dodge: MechDodge

@export_group("Boost")
## Steady shake while boosting (0 to 1).
@export var boost_trauma: float = 0.4
## Steady shake while the feet slide in a boost skid stop (0 to 1).
@export var skid_trauma: float = 0.45
## Steady shake while in the air and falling (0 to 1).
@export var air_trauma: float = 0.28
## Steady shake while rising after a jump (0 to 1). Shake grows with trauma squared,
## so 0.44 gives about 1.2x the shake of 0.4.
@export var air_rising_trauma: float = 0.44

@export_group("Shake")
## Overall shake strength. 1.0 = all values as set above and below. 0.5 = half.
@export var intensity: float = 0.75
## Largest random offset in meters at full shake.
@export var max_offset: float = 0.5
@export var max_roll_deg: float = 1.2
## How fast shake fades (per second).
@export var trauma_decay: float = 2.5
## A kick (camera drop) comes back on a spring with a small bounce.
## Spring speed (bounces per second). Lower = slower return.
@export var kick_frequency: float = 2.2
## Spring damping. Lower = more bounce. 1.0 = no bounce.
@export_range(0.05, 1.0) var kick_damping: float = 0.45
## How fast the random shake moves. Lower = smoother, slower wobble.
@export var noise_speed: float = 21.0
## Smoothing of the final camera offset. Lower = smoother (and a little more lag).
@export var smoothing: float = 100.0

var _trauma: float = 0.0
var _kick := AimSpring.new(0.0)
var _was_boosting: bool = false
var _was_skidding: bool = false
var _was_rising: bool = false
var _time: float = 0.0
var _noise := FastNoiseLite.new()
var _offset := Vector3.ZERO


func _ready() -> void:
	_noise.frequency = 0.5
	footsteps.footstep.connect(_on_footstep)
	mech.landed.connect(_on_landed)
	mech.bumped.connect(_on_bumped)
	if dodge != null:
		dodge.dodge_started.connect(func() -> void: add_shake(0.2, dodge_start_kick))
		dodge.dodge_ended.connect(func() -> void: add_shake(0.25, dodge_end_kick))


func add_shake(trauma: float, kick: float) -> void:
	_trauma = minf(_trauma + trauma, 1.0)
	_kick.value = minf(_kick.value + kick, 1.5)


# One kick at the start of each steady movement.
func _physics_process(_delta: float) -> void:
	var airborne := not mech.is_on_floor()
	var rising := airborne and mech.velocity.y > 0.0
	if mech.is_boosting and not _was_boosting:
		add_shake(0.0, boost_start_kick)
	if mech.is_skidding and not _was_skidding:
		add_shake(0.0, skid_start_kick)
	if rising and not _was_rising:
		add_shake(0.0, takeoff_kick)
	if airborne and _was_rising and not rising:
		add_shake(0.0, fall_start_kick)
	_was_boosting = mech.is_boosting
	_was_skidding = mech.is_skidding
	_was_rising = rising


func _process(delta: float) -> void:
	_time += delta * noise_speed
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	if mech.is_boosting:
		_trauma = maxf(_trauma, boost_trauma)
	if mech.is_skidding:
		_trauma = maxf(_trauma, skid_trauma)
	if not mech.is_on_floor():
		_trauma = maxf(_trauma, air_rising_trauma if mech.velocity.y > 0.0 else air_trauma)
	_kick.update(0.0, kick_frequency, kick_damping, 10.0, delta)

	var shake := _trauma * _trauma * intensity
	var target := Vector3(
		max_offset * shake * _noise.get_noise_2d(0.0, _time),
		max_offset * shake * _noise.get_noise_2d(100.0, _time) - _kick.value * intensity,
		deg_to_rad(max_roll_deg) * shake * _noise.get_noise_2d(200.0, _time))
	# Smooth the result so the camera eases instead of jumping.
	_offset = _offset.lerp(target, 1.0 - exp(-smoothing * delta))
	h_offset = _offset.x
	v_offset = _offset.y
	rotation.z = _offset.z


func _on_footstep(strength: float) -> void:
	var size := mech.height_m / footstep_reference_height
	add_shake(footstep_trauma * strength * size, footstep_kick * strength * size)


func _on_bumped(strength: float) -> void:
	add_shake(strength * bump_trauma_per_speed, bump_kick)


func _on_landed(fall_speed: float) -> void:
	add_shake(fall_speed * landing_trauma_per_speed, fall_speed * landing_kick_per_speed)
