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

@export_group("Boost")
## Steady shake while boosting (0 to 1).
@export var boost_trauma: float = 0.4
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
## How fast a kick (footstep or landing drop) comes back. Lower = slower, smoother.
@export var kick_recovery: float = 9.8
## How fast the random shake moves. Lower = smoother, slower wobble.
@export var noise_speed: float = 21.0
## Smoothing of the final camera offset. Lower = smoother (and a little more lag).
@export var smoothing: float = 42.0

var _trauma: float = 0.0
var _kick: float = 0.0
var _time: float = 0.0
var _noise := FastNoiseLite.new()
var _offset := Vector3.ZERO


func _ready() -> void:
	_noise.frequency = 0.5
	footsteps.footstep.connect(_on_footstep)
	mech.landed.connect(_on_landed)
	mech.bumped.connect(_on_bumped)


func add_shake(trauma: float, kick: float) -> void:
	_trauma = minf(_trauma + trauma, 1.0)
	_kick = minf(_kick + kick, 1.5)


func _process(delta: float) -> void:
	_time += delta * noise_speed
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	if mech.is_boosting:
		_trauma = maxf(_trauma, boost_trauma)
	if not mech.is_on_floor():
		_trauma = maxf(_trauma, air_rising_trauma if mech.velocity.y > 0.0 else air_trauma)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-kick_recovery * delta))

	var shake := _trauma * _trauma * intensity
	var target := Vector3(
		max_offset * shake * _noise.get_noise_2d(0.0, _time),
		max_offset * shake * _noise.get_noise_2d(100.0, _time) - _kick * intensity,
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
	add_shake(strength * bump_trauma_per_speed, 0.0)


func _on_landed(fall_speed: float) -> void:
	add_shake(fall_speed * landing_trauma_per_speed, fall_speed * landing_kick_per_speed)
