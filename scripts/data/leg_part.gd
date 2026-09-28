class_name LegPart
extends PartData
## Legs: carry the weight and set the base speed and jump.

enum LegType { BIPED, REVERSE_JOINT, TANK, QUAD }

@export var leg_type: LegType = LegType.BIPED
## Weight the legs carry before the mech slows down a lot, in tons.
@export var load_capacity_t: float = 80.0
## Top walk speed with no load, in m/s. The weight formula lowers it.
@export var base_speed: float = 11.742
## Full jump jet height, in meters.
@export var jump_height: float = 9.0
## Leg turn speeds (A / D) before the weight factor, in degrees per second.
@export var turn_speed_deg: float = 77.4
@export var turn_speed_standing_deg: float = 38.7
