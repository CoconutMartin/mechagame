class_name GeneratorPart
extends PartData
## Generator: refills energy.

## Energy output: energy refilled each second.
@export var energy_output: float = 17.5
## Seconds after the last energy use before the refill starts.
@export var recharge_delay: float = 2.0
