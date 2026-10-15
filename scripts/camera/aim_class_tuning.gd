class_name AimClassTuning
extends Resource
## Aim feel per mech weight class (user request 2026-10-15). Light and medium mechs get less crosshair
## sway and a faster mouse. Heavy mechs stay as they were. The class comes from WeightClass.of_mech.

@export_group("Crosshair sway")
## Sway factor for light mechs (aim jitter, booster shake, walk and idle sway). 0.25 = 75% less.
@export var light_sway: float = 0.25
## Sway factor for medium mechs. 0.5 = 50% less.
@export var medium_sway: float = 0.5
## Sway factor for heavy mechs. 1.0 = unchanged.
@export var heavy_sway: float = 1.0
@export_group("Mouse sensitivity")
## Mouse sensitivity factor for light mechs. 1.5 = 50% faster.
@export var light_sensitivity: float = 1.5
## Mouse sensitivity factor for medium mechs. 1.3 = 30% faster.
@export var medium_sensitivity: float = 1.3
## Mouse sensitivity factor for heavy mechs. 1.0 = unchanged.
@export var heavy_sensitivity: float = 1.0
@export_group("")


## Sway factor for the mech's class. 1.0 when there is no mech.
func get_sway_factor(mech: Mech) -> float:
	if mech == null:
		return 1.0
	match WeightClass.of_mech(mech):
		WeightClass.Class.LIGHT:
			return light_sway
		WeightClass.Class.MEDIUM:
			return medium_sway
	return heavy_sway


## Mouse sensitivity factor for the mech's class. 1.0 when there is no mech.
func get_sensitivity_factor(mech: Mech) -> float:
	if mech == null:
		return 1.0
	match WeightClass.of_mech(mech):
		WeightClass.Class.LIGHT:
			return light_sensitivity
		WeightClass.Class.MEDIUM:
			return medium_sensitivity
	return heavy_sensitivity
