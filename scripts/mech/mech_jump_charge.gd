class_name MechJumpCharge
extends Node
## Hold jump on the ground to charge the jump jets. Release to jump.
## Height = full_height x charge. Charging 1 s gives 25%, 4 s gives 100%.
## Charging uses energy. If energy runs out, the charge stops growing.

@export var mech: Mech
@export var input: MechInput
@export var energy: MechEnergy
@export var landing_recovery: MechLandingRecovery
## Seconds of charge for full height.
@export var full_charge_time: float = 4.0
## Jump height at full charge, in meters.
@export var full_height: float = 9.0
## Energy used for a full charge. 100 = a full tank.
@export var full_energy_cost: float = 100.0
## Charges below this fraction cancel the jump (0.1 = 0.4 s).
@export var min_charge: float = 0.1

## 0 to 1 while charging.
var charge: float = 0.0
var is_charging: bool = false

var _launch_height: float = 0.0


func _ready() -> void:
	# Run before the Mech so a release launches in the same frame.
	process_physics_priority = -5


func _physics_process(delta: float) -> void:
	if not mech.is_on_floor() or landing_recovery.is_recovering():
		is_charging = false
		charge = 0.0
		return
	if input.jump_held:
		is_charging = true
		var step := delta / full_charge_time
		if charge < 1.0 and energy.try_drain(full_energy_cost * step):
			charge = minf(charge + step, 1.0)
	elif is_charging:
		is_charging = false
		if charge >= min_charge:
			_launch_height = charge * full_height
		charge = 0.0


## Height of a jump that is ready to launch, in meters. Returns 0 if none. Clears it.
func take_launch_height() -> float:
	var height := _launch_height
	_launch_height = 0.0
	return height
