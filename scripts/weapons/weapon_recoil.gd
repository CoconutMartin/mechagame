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

var _amount := AimSpring.new(0.0)
var _side: float = 0.0


func _ready() -> void:
	# Before WeaponPose (5).
	process_physics_priority = 4
	if weapon_fire != null:
		weapon_fire.fired.connect(_on_fired)


## Listens to a weapon's fired signal (WeaponController calls it).
func bind(emitter: Object) -> void:
	emitter.connect(&"fired", _on_fired)


func _on_fired() -> void:
	# A velocity kick gives a fast snap back and a spring return.
	_amount.velocity += kick_speed * TAU * frequency
	_amount.value = minf(_amount.value, max_amount)
	_side = randf_range(-1.0, 1.0)


func _physics_process(delta: float) -> void:
	_amount.update(0.0, frequency, damping, max_amount, delta)


## Recoil offset in the weapon's own space: back along +Z, muzzle up, a little to the side.
func get_offset() -> Transform3D:
	var amount := _amount.value
	var basis := Basis.from_euler(Vector3(deg_to_rad(kick_up_deg) * amount, deg_to_rad(kick_side_deg) * _side * amount, 0.0))
	return Transform3D(basis, Vector3(0.0, 0.0, kick_back * amount))
