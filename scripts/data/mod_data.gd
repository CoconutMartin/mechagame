class_name ModData
extends Resource
## A mod: a small change to one stat, in percent (example: -5 = 5% less weight).

enum Stat { WEIGHT, SPEED, BOOST_THRUST, ENERGY_CAPACITY, ENERGY_OUTPUT, TURN_SPEED, JUMP_HEIGHT, PART_HP, RECOIL }

@export var display_name: String = ""
@export var stat: Stat = Stat.WEIGHT
## Change in percent. Positive = more.
@export var percent: float = 0.0
