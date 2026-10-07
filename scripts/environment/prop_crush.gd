class_name PropCrush
extends RefCounted
## CRUSH reaction (cars): the model squashes to PropDef.crush_scale of its height, with sparks.
## The collision box shrinks with it.

const SQUASH_TIME := 0.18


static func play(prop: UrbanProp) -> void:
	var pivot := prop.get_pivot()
	if pivot == null:
		return
	var tween := prop.create_tween()
	tween.tween_property(pivot, ^"scale:y", prop.def.crush_scale, SQUASH_TIME).set_ease(Tween.EASE_OUT)
	for child in prop.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
			box.size.y *= prop.def.crush_scale
			shape.shape = box
			shape.position.y *= prop.def.crush_scale
	_sparks(prop, prop.global_position + Vector3.UP * prop.def.size.y * 0.6)


static func _sparks(prop: Node3D, point: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.emitting = true
	sparks.amount = 40
	sparks.lifetime = 0.6
	sparks.explosiveness = 0.95
	sparks.direction = Vector3.UP
	sparks.spread = 70.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 9.0
	sparks.gravity = Vector3(0.0, -15.0, 0.0)
	sparks.scale_amount_min = 0.04
	sparks.scale_amount_max = 0.08
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.7, 0.3)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.6, 0.2)
	glow.emission_energy_multiplier = 4.0
	mesh.material = glow
	sparks.mesh = mesh
	prop.get_parent().add_child(sparks)
	sparks.global_position = point
	sparks.finished.connect(sparks.queue_free)
