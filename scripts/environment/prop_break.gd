class_name PropBreak
extends RefCounted
## BREAK reaction (bus stops, benches, fences, hydrants): the model breaks into PropDef.debris_pieces
## small tumbling boxes in its colors, with dust; a hydrant sprays water. The prop is removed.

## Debris life in seconds (Checkpoint 2 moves this to the shared DebrisPool).
const DEBRIS_LIFE := 8.0
const SPRAY_TIME := 8.0


static func play(prop: UrbanProp, direction: Vector3, speed: float) -> void:
	var world := prop.get_parent()
	var center := prop.global_position + Vector3.UP * prop.def.size.y * 0.5
	var meshes := prop.find_children("*", "MeshInstance3D", true, false)
	var count := maxi(prop.def.debris_pieces, 1)
	for i in count:
		var source := meshes[i % meshes.size()] as MeshInstance3D if not meshes.is_empty() else null
		_piece(world, prop, source, center, direction, speed)
	DustBurst.create(world, center, prop.def.size)
	if prop.def.water_spray:
		_spray(world, prop.global_position + Vector3.UP * 0.5)
	prop.queue_free()


static func _piece(world: Node, prop: UrbanProp, source: MeshInstance3D, center: Vector3, direction: Vector3, speed: float) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	var size := prop.def.size * randf_range(0.2, 0.4)
	size = size.clamp(Vector3.ONE * 0.08, Vector3.ONE * 1.2)
	var look := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	look.mesh = box
	if source != null:
		look.material_override = source.get_active_material(0)
	body.add_child(look)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.mass = maxf(prop.def.mass_t * 1000.0 / maxf(prop.def.debris_pieces, 1), 5.0)
	world.add_child(body)
	body.global_position = center + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), randf_range(-0.5, 0.5)) * prop.def.size
	body.linear_velocity = direction * maxf(speed, 3.0) * randf_range(0.4, 0.9) + Vector3.UP * randf_range(2.0, 5.0)
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	body.get_tree().create_timer(DEBRIS_LIFE).timeout.connect(body.queue_free)


static func _spray(world: Node, point: Vector3) -> void:
	var water := CPUParticles3D.new()
	water.amount = 60
	water.lifetime = 1.4
	water.direction = Vector3.UP
	water.spread = 12.0
	water.initial_velocity_min = 7.0
	water.initial_velocity_max = 10.0
	water.gravity = Vector3(0.0, -9.8, 0.0)
	water.scale_amount_min = 0.15
	water.scale_amount_max = 0.3
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.85, 0.95, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mesh.material = mat
	water.mesh = mesh
	world.add_child(water)
	water.global_position = point
	water.emitting = true
	water.get_tree().create_timer(SPRAY_TIME).timeout.connect(func() -> void:
		water.emitting = false
		water.get_tree().create_timer(water.lifetime + 0.2).timeout.connect(water.queue_free))
