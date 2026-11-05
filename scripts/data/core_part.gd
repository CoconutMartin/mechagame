class_name CorePart
extends PartData
## Core: the body. Core destroyed = mech destroyed (Phase 4).

## Energy capacity.
@export var energy_capacity: float = 100.0
## Base torso turn speed in degrees per second, before the weight factor.
@export var torso_turn_speed_deg: float = 56.9
## Place of the back pack's front face center in mech space at the rest pose (m; +Z = back): on this core's back face.
@export var back_pack_offset: Vector3 = Vector3(0.0, 7.7, 1.43)
