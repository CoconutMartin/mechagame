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
## Relaxed hand place (an empty or fist hand at its hang), torso space, meters, for the left side; a right arm takes the mirror
## (x negated). Each arm brings its own: the place depends on the arm's lengths and its neutral arm (user 2026-11-08). 0 = the mech
## scene's own marker (WeaponController.free_left_hand).
@export var relaxed_hand: Vector3 = Vector3.ZERO
## Neutral arm: the upper arm's local turn (in its parent bone's frame) the arm swings from, for an arm with no flat shoulder block
## (SkeletalArmRig.neutral_turn_*). Haliya: the mean of its Walk clip (tools/godot/write_arm_neutral_data.gd; user 2026-11-08: "Make HLY
## walking arms position as neutral arms position"). Identity: the flat shoulder block, or the rest pose.
@export var neutral_turn: Quaternion = Quaternion.IDENTITY

@export_group("Jointed hand")
## Written by tools/godot/write_arm_hand_data.gd, measured on this part's rig (zero: the mech scene's own values stay).
## The hand model's place on the hand bone.
@export var hand_transform: Transform3D = Transform3D.IDENTITY
## Wrist pin center in the forearm bone frame at rest (MechHandControl.wrist_pin_*).
@export var wrist_pin: Vector3 = Vector3.ZERO
## How far the hand model moved on its bone to reach the pin (MechHandControl.hand_shift_*).
@export var hand_shift: Vector3 = Vector3.ZERO
