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

@export_group("Jointed hand")
## Written by tools/godot/write_arm_hand_data.gd, measured on this part's rig (zero: the mech scene's own values stay).
## The hand model's place on the hand bone.
@export var hand_transform: Transform3D = Transform3D.IDENTITY
## Wrist pin center in the forearm bone frame at rest (MechHandControl.wrist_pin_*).
@export var wrist_pin: Vector3 = Vector3.ZERO
## How far the hand model moved on its bone to reach the pin (MechHandControl.hand_shift_*).
@export var hand_shift: Vector3 = Vector3.ZERO
