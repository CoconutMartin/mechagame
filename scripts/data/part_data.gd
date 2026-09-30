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

@export_group("Look")
## Model size change (Phase 5 light and heavy variants). Each piece grows or shrinks in place.
@export var model_scale: Vector3 = Vector3.ONE
## Armor color multiplier (white = the model colors).
@export var armor_tint: Color = Color.WHITE
## Material files for imported models (.glb): a Blender material named like a file here ("armor",
## "armor_dark", "frame", "joint", "eye"...) uses that file. Empty = keep the Blender materials.
@export_dir var material_library: String = "res://materials/warden"
