class_name MechJumpCharge
extends Node
## Hold jump on the ground to charge the jump jets. Release to jump.
## Hold a move key while charging to jump in that direction.
## Height = full_height x charge. The charge follows height_at_second:
## 1 s = 33%, 2 s = 63%, 3 s = 100%. Values between whole seconds are blended.
## Charging uses energy at a steady rate. If energy runs out, the charge stops growing.

@export var mech: Mech
@export var input: MechInput
@export var energy: MechEnergy
@export var landing_recovery: MechLandingRecovery
@export var kneel: MechKneel
## Charge (fraction of full height) after 1 s, 2 s, 3 s, and so on. The last value is full charge.
@export var height_at_second: PackedFloat32Array = PackedFloat32Array([0.33, 0.63, 1.0])
## Jump height at full charge, in meters.
@export var full_height: float = 9.0
## Energy used for a full charge. 100 = a full tank.
@export var full_energy_cost: float = 100.0
## Charges below this fraction of full height cancel the jump.
@export var min_charge: float = 0.1
## A move key released this many seconds before the jump still sets the jump direction.
## This lets you release the move key and Space at the same time.
@export var direction_memory: float = 0.25

## 0 to 1: fraction of full height while charging.
var charge: float = 0.0
var is_charging: bool = false
## Move direction held when the jump launched (length 0 to 1). Zero = straight up.
var launch_direction: Vector3 = Vector3.ZERO

var _charge_time: float = 0.0
var _launch_height: float = 0.0
var _charge_direction: Vector3 = Vector3.ZERO
var _direction_age: float = 0.0


func _ready() -> void:
	# Run before the Mech so a release launches in the same frame.
	process_physics_priority = -5


## Seconds of charge for full height.
func get_full_charge_time() -> float:
	return float(height_at_second.size())


func _physics_process(delta: float) -> void:
	if not mech.is_on_floor() or landing_recovery.is_recovering() or kneel.is_kneeling:
		_reset()
		return
	_remember_direction(delta)
	if input.jump_held:
		is_charging = true
		var full_time := get_full_charge_time()
		if _charge_time < full_time and energy.try_drain(full_energy_cost * delta / full_time):
			_charge_time = minf(_charge_time + delta, full_time)
			charge = _height_for_time(_charge_time)
	elif is_charging:
		if charge >= min_charge:
			_launch_height = charge * full_height
			launch_direction = _charge_direction
		_reset()


## Height of a jump that is ready to launch, in meters. Returns 0 if none. Clears it.
func take_launch_height() -> float:
	var height := _launch_height
	_launch_height = 0.0
	return height


func _height_for_time(time: float) -> float:
	var second := int(time)
	var before := 0.0 if second == 0 else height_at_second[mini(second - 1, height_at_second.size() - 1)]
	if second >= height_at_second.size():
		return height_at_second[height_at_second.size() - 1]
	return lerpf(before, height_at_second[second], time - second)


func _remember_direction(delta: float) -> void:
	if input.move_direction.length_squared() > 0.01:
		_charge_direction = input.move_direction
		_direction_age = 0.0
	else:
		_direction_age += delta
		if _direction_age > direction_memory:
			_charge_direction = Vector3.ZERO


func _reset() -> void:
	is_charging = false
	charge = 0.0
	_charge_time = 0.0
