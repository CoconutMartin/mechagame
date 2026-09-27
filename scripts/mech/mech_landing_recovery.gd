class_name MechLandingRecovery
extends Node
## After a hard landing the mech cannot move for a short time.
## Delay = reference_delay x (mass / reference_mass) x (fall height / reference_height).

@export var mech: Mech
## Delay in seconds for the reference mass falling the reference height.
@export var reference_delay: float = 1.5
## Mass in tons for the reference delay.
@export var reference_mass: float = 60.0
## Fall height in meters for the reference delay (top jump jet height).
@export var reference_height: float = 9.0
## Falls lower than this (meters) give no delay. The boost exit hop is about 0.8 m.
@export var min_height: float = 1.0
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
	if height < min_height:
		return
	duration = minf(reference_delay * (mech.mass_tons / reference_mass) * (height / reference_height), max_delay)
	time_left = duration
