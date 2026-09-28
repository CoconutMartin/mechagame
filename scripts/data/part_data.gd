class_name PartData
extends Resource
## Base data for every mech part. Subclasses add the stats of each part type.
## The scene is the part model: its child groups attach to the frame nodes with the same names.

@export var display_name: String = ""
## Part weight in tons.
@export var weight_t: float = 1.0
## Part hit points.
@export var hp: float = 100.0
## Part model. Optional (a generator or FCS has no model).
@export var scene: PackedScene
