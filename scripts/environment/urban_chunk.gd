class_name UrbanChunk
extends StaticBody3D
## One building chunk made by BuildingGenerator: a wall panel, a window glass, a door, a floor slab,
## a column, a parapet or a tower core. It is a StaticBody3D until it falls (Checkpoint 2).
## Its look is drawn by the building's MultiMeshes; `pieces` lists its instances there.

enum Kind { WALL, GLASS, DOOR, SLAB, COLUMN, PARAPET, ROOF, CORE }

var kind: Kind = Kind.WALL
## Floor index (0 = ground floor). Roof pieces use the top floor.
var floor_index: int = 0
var material_def: MaterialDef
## Volume in cubic meters (sum of its boxes).
var volume: float = 0.0
var max_hp: float = 0.0
var hp: float = 0.0
## The building that made it.
var building: Node3D
## Its instances in the building's MultiMeshes: Vector2i(multimesh slot, instance index).
var pieces: Array[Vector2i] = []
