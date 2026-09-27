class_name MechEnergy
extends Node
## Stores and recharges the mech's energy. Boost (and later weapons) use it.

signal depleted
signal recovered

@export var capacity: float = 100.0
## Energy regained each second.
@export var recharge_rate: float = 35.0
## Wait time (seconds) after last use before recharge starts.
@export var recharge_delay: float = 0.6
## After running empty, energy must refill to this fraction before you can use it again.
@export_range(0.0, 1.0) var restart_fraction: float = 0.3

var current: float
var is_depleted: bool = false

var _delay_left: float = 0.0


func _ready() -> void:
	current = capacity


## Uses energy. Returns false if there is none to use.
func try_drain(amount: float) -> bool:
	if is_depleted or current <= 0.0:
		return false
	current = maxf(current - amount, 0.0)
	_delay_left = recharge_delay
	if current <= 0.0:
		is_depleted = true
		depleted.emit()
	return true


func get_fraction() -> float:
	return current / capacity


func _physics_process(delta: float) -> void:
	if _delay_left > 0.0:
		_delay_left -= delta
		return
	current = minf(current + recharge_rate * delta, capacity)
	if is_depleted and current >= capacity * restart_fraction:
		is_depleted = false
		recovered.emit()
