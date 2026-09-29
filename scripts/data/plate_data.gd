class_name PlateData
extends Resource
## An armor plate. It adds HP and weight to one part.

enum Slot { HEAD, CORE, ARM_LEFT, ARM_RIGHT, LEGS }

@export var display_name: String = ""
@export var slot: Slot = Slot.CORE
## Extra HP for the part in this slot.
@export var hp: float = 200.0
## Plate weight in tons.
@export var weight_t: float = 1.0
## Plate thickness on the model, in meters.
@export var thickness: float = 0.18
