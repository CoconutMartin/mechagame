class_name BoosterPart
extends PartData
## Booster: thrust and energy use. Heavier mechs gain boost speed slower.

## Thrust. Boost acceleration (m/s per second) = thrust / total weight in tons.
@export var thrust: float = 1200.0
## Boost top speed = walk speed x this value.
@export var boost_speed_multiplier: float = 1.5
## Energy used each second while boosting on the ground.
@export var energy_per_second: float = 30.0
