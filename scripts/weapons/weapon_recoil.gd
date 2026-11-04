class_name WeaponRecoil
extends Node
## Kicks the weapon back and up at each shot, then a spring brings it back.
## WeaponPose adds get_offset() to the weapon pose. The hand IK follows the weapon grip.

## Optional (older scenes). WeaponController calls bind() instead.
@export var weapon_fire: WeaponFire
## Push back per shot, in meters.
@export var kick_back: float = 0.7
## Muzzle climb per shot, in degrees.
@export var kick_up_deg: float = 10.0
## Random side turn per shot, in degrees.
@export var kick_side_deg: float = 3.0
## Spring start speed per shot. 1.8 gives a peak of about 1 (one full kick).
@export var kick_speed: float = 1.8
## Largest total recoil (1 = one full kick).
@export var max_amount: float = 1.8
## Spring speed (swings per second).
@export var frequency: float = 5.0
## Spring damping. Lower = more bounce.
@export_range(0.1, 1.0) var damping: float = 0.55
## The kick's push is spread over this many seconds (0 = all in one frame). In one frame the Beam Rifle jumped
## 0.45 m back, and the hinge arm holding it flipped its elbow 32 deg in one frame (user report 2026-10-24: the
## right forearm twitched in charged firing).
@export var kick_rise_time: float = 0.12
## Sustained recoil (set_sustain, a beam that fires for seconds): how fast the weapon follows it (1 / seconds). It
## eases in and out so the hand IK never gets a jump.
@export var sustain_ramp_speed: float = 8.0
## Sustained recoil: how fast the weapon shakes (waves per second).
@export var sustain_shake_hz: float = 7.0

var _amount := AimSpring.new(0.0)
var _side: float = 0.0
## Spring speed still to add from the last kicks (spread over kick_rise_time).
var _push_left: float = 0.0
## Sustained recoil asked this frame (set_sustain), as back (m), climb (deg) and shake (deg). Reset every frame.
var _sustain_want := Vector3.ZERO
var _sustain_now := Vector3.ZERO
var _shake_time: float = 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	# Before WeaponPose (5).
	process_physics_priority = 4
	_noise.frequency = 1.0
	_noise.seed = randi()
	if weapon_fire != null:
		weapon_fire.fired.connect(_on_fired)


## Listens to a weapon's fired signal (WeaponController calls it). Binding the same weapon twice does
## nothing (a weapon that comes back to the hand keeps one connection).
func bind(emitter: Object) -> void:
	if not emitter.is_connected(&"fired", _on_fired):
		emitter.connect(&"fired", _on_fired)


## Stops listening to a weapon (it left the hand).
func unbind(emitter: Object) -> void:
	if is_instance_valid(emitter) and emitter.is_connected(&"fired", _on_fired):
		emitter.disconnect(&"fired", _on_fired)


func _on_fired() -> void:
	# A velocity kick gives a fast snap back and a spring return.
	var push := kick_speed * TAU * frequency
	if kick_rise_time > 0.0:
		_push_left += push
	else:
		_amount.velocity += push
	_amount.value = minf(_amount.value, max_amount)
	_side = randf_range(-1.0, 1.0)


## A steady recoil while a weapon fires for a longer time (the charged beam): the weapon is pushed back, its muzzle
## climbs and it shakes. A weapon calls it every physics frame while it fires; the recoil fades out when the calls
## stop (a dropped weapon cannot leave it on). back_m in meters, climb_deg and shake_deg in degrees.
func set_sustain(back_m: float, climb_deg: float, shake_deg: float) -> void:
	_sustain_want = Vector3(back_m, climb_deg, shake_deg)


func _physics_process(delta: float) -> void:
	_sustain_now = _sustain_now.lerp(_sustain_want, 1.0 - exp(-sustain_ramp_speed * delta))
	_sustain_want = Vector3.ZERO
	if _sustain_now.length_squared() > 0.000001:
		_shake_time += delta * sustain_shake_hz
	if _push_left > 0.0:
		var push := minf(_push_left, kick_speed * TAU * frequency * delta / kick_rise_time)
		_push_left -= push
		_amount.velocity += push
	_amount.update(0.0, frequency, damping, max_amount, delta)


## Recoil offset in the weapon's own space: back along +Z, muzzle up, a little to the side.
func get_offset() -> Transform3D:
	var amount := _amount.value
	var up := deg_to_rad(kick_up_deg) * amount
	var side := deg_to_rad(kick_side_deg) * _side * amount
	var back := kick_back * amount
	if _sustain_now.length_squared() > 0.000001:
		# Noise values are mostly within +/- 0.5, so x2 gives about the full shake size.
		var shake := deg_to_rad(_sustain_now.z) * 2.0
		up += deg_to_rad(_sustain_now.y) + shake * _noise.get_noise_2d(_shake_time, 0.0)
		side += shake * _noise.get_noise_2d(_shake_time, 50.0)
		back += _sustain_now.x
	var basis := Basis.from_euler(Vector3(up, side, 0.0))
	return Transform3D(basis, Vector3(0.0, 0.0, back))
