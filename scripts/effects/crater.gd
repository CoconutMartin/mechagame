class_name Crater
extends Node3D
## A road crater (user answer 2026-10-12: missiles and cannon shells break the road): a scorched,
## cracked decal, slabs of broken road tilted up around the rim, a burst of road rubble and dust.
## The slabs have no collision (mechs walk over them). At most max_count craters: the oldest goes.

const TEXTURE := preload("res://assets/textures/decals/crater.png")

## Largest number of craters in the level.
static var max_count: int = 40
# Untyped: a typed read of a freed crater is an error.
static var _all: Array = []

var radius: float = 1.5
var material: Material
var tint: Color = Color(0.3, 0.3, 0.3)


## Makes a crater on the ground at point (radius in meters). ground: the ground body that was hit (its
## material gives the slabs and rubble their look; may be null).
static func spawn(world: Node, point: Vector3, crater_radius: float, ground: Node = null) -> Crater:
	while _all.size() >= max_count:
		var oldest: Variant = _all.pop_front()
		if is_instance_valid(oldest):
			(oldest as Crater).queue_free()
	var crater := Crater.new()
	crater.radius = crater_radius
	var slab := ground as GroundSlab
	if slab != null and slab.material_def != null:
		crater.material = slab.material_def.get_material()
		crater.tint = slab.material_def.debris_color
	world.add_child(crater)
	crater.global_position = point
	crater.rotation.y = randf() * TAU
	_all.append(crater)
	return crater


func _ready() -> void:
	name = "Crater"
	var decal := Decal.new()
	decal.texture_albedo = TEXTURE
	decal.size = Vector3(radius * 2.6, 1.5, radius * 2.6)
	decal.cull_mask = 1
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 100.0
	add_child(decal)
	_slabs()
	var parent := get_parent()
	DustBurst.create(parent, global_position + Vector3.UP * 0.3, Vector3(radius * 1.6, 0.6, radius * 1.6))
	var color := Color(tint.r, tint.g, tint.b, 1.0)
	for i in randi_range(3, 5):
		var side := radius * randf_range(0.15, 0.3)
		var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		Rubble.spawn(parent, global_position + away * radius * 0.4 + Vector3.UP * 0.4,
				Vector3(side, side * 0.4, side * randf_range(0.7, 1.2)), color * randf_range(0.85, 1.05),
				away * randf_range(3.0, 7.0) + Vector3.UP * randf_range(4.0, 8.0))


## Broken road slabs around the rim, tilted up and out, half sunk.
func _slabs() -> void:
	var count := randi_range(6, 9)
	for i in count:
		var angle := TAU * (i + randf_range(-0.3, 0.3)) / count
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var size := Vector3(radius * randf_range(0.5, 0.8), 0.25, radius * randf_range(0.35, 0.55))
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		if material != null:
			mesh.material_override = material
		var tilt := deg_to_rad(randf_range(15.0, 35.0))
		# Long side around the rim; tilted up toward the outside.
		var basis := Basis(Vector3.UP, -angle + PI * 0.5) * Basis(Vector3.RIGHT, -tilt)
		mesh.transform = Transform3D(basis, out * radius * randf_range(0.8, 1.0) + Vector3.UP * 0.02)
		add_child(mesh)


func _exit_tree() -> void:
	_all.erase(self)
