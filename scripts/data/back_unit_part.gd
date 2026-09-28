class_name BackUnitPart
extends PartData
## Back unit (left or right): missile pod, cannon or shield. Weapons work in Phase 3.

enum Kind { MISSILE_POD, CANNON, SHIELD }

@export var kind: Kind = Kind.MISSILE_POD
