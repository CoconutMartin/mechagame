class_name ArmPart
extends PartData
## Arm (left or right). Holds one weapon.

## Recoil multiplier (1 = normal, lower = steadier).
@export var recoil_control: float = 1.0
## Melee damage multiplier (1 = normal).
@export var melee_bonus: float = 1.0
## Right arm: moves the place where this hand holds the right weapon (rest, aim and one-hand hold),
## in torso space, meters (x right, y up, -z forward). For mechs whose hands hang far from the
## standard hold place; 0 = the place in the weapon data.
@export var hold_offset: Vector3 = Vector3.ZERO
