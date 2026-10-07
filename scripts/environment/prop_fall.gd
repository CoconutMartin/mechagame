class_name PropFall
extends RefCounted
## FALL reaction (trees): the prop tips over at its base away from the mech, slow at first, and lands
## with a puff of dust. Its collision is turned off.

const FALL_TIME := 1.3


static func play(prop: UrbanProp, direction: Vector3) -> void:
	var pivot := prop.get_pivot()
	if pivot == null:
		return
	for child in prop.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(&"disabled", true)
	var local_dir := prop.global_basis.inverse() * direction
	local_dir.y = 0.0
	if local_dir.length_squared() < 0.0001:
		local_dir = Vector3.FORWARD
	var axis := Vector3.UP.cross(local_dir.normalized()).normalized()
	var tween := prop.create_tween()
	var start := pivot.transform
	tween.tween_method(func(t: float) -> void:
		pivot.transform = Transform3D(Basis(axis, deg_to_rad(88.0) * t), Vector3.ZERO) * start, 0.0, 1.0, FALL_TIME) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		var tip := prop.global_position + direction * prop.def.size.y * 0.7 + Vector3.UP * 0.5
		DustBurst.create(prop.get_parent(), tip, Vector3(2.0, 1.0, 2.0)))
