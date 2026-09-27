class_name MechLandingRecovery
extends Node
## After a landing the mech cannot move for a short time.
## Falls below min_height: short_fall_delay.
## Higher falls: reference_delay x (mass / reference_mass) x (fall height / reference_height),
## but never less than short_fall_delay.
## The boost exit hop is part of the walk and gives no delay.

@export var mech: Mech
## Delay in seconds for the reference mass falling the reference height.
@export var reference_delay: float = 1.5
## Mass in tons for the reference delay.
@export var reference_mass: float = 60.0
## Fall height in meters for the reference delay (top jump jet height).
@export var reference_height: float = 9.0
## Falls lower than this (meters) use short_fall_delay.
@export var min_height: float = 1.0
## Delay in seconds for falls lower than min_height.
@export var short_fall_delay: float = 0.5
## Falls lower than this (meters) give no delay, for example small steps and slopes.
@export var ignore_height: float = 0.2
@export var max_delay: float = 3.0

var time_left: float = 0.0
var duration: float = 0.0

var _peak_y: float = 0.0


func _ready() -> void:
	mech.landed.connect(_on_landed)


func is_recovering() -> bool:
	return time_left > 0.0


## 1 just after landing, 0 when recovered.
func get_fraction() -> float:
	return time_left / duration if duration > 0.0 else 0.0


func _physics_process(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	if mech.is_on_floor():
		_peak_y = mech.global_position.y
	else:
		_peak_y = maxf(_peak_y, mech.global_position.y)


func _on_landed(_fall_speed: float) -> void:
	var height := _peak_y - mech.global_position.y
	_peak_y = mech.global_position.y
	if height < ignore_height or mech.is_exiting_boost:
		return
	if height < min_height:
		duration = short_fall_delay
	else:
		var scaled := reference_delay * (mech.mass_tons / reference_mass) * (height / reference_height)
		duration = clampf(scaled, short_fall_delay, max_delay)
	time_left = duration
