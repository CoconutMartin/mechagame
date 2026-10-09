class_name BoneHitPart
extends Resource
## One HP part of a rigged mech: its hit key (the same keys as MechHealth), HP and the bones whose
## meshes make its hitboxes.

## MechHealth key, for example "Head", "Torso C", "Arm L", "Groin", "Leg R".
@export var key: String = ""
@export var max_hp: float = 100.0
## Bones whose meshes are this part (one hitbox per bone, following the bone).
@export var bones: Array[StringName] = []
## Only mesh volume between these model-space X values (m) counts (to split one torso mesh into
## center, left and right). The model's left side is +X.
@export var min_x: float = -100.0
@export var max_x: float = 100.0
