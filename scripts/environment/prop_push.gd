class_name PropPush
extends RefCounted
## PUSH reaction (buses): the prop slides away from the mech (PropDef.push_per_speed meters per m/s,
## heavier props less) and gets a dent (a small tilt and squeeze of the model).

const SLIDE_TIME := 0.45


static func play(prop: UrbanProp, direction: Vector3, speed: float) -> void:
	var distance := prop.def.push_per_speed * maxf(speed, 2.0) * 10.0 / (10.0 + prop.def.mass_t)
	var tween := prop.create_tween()
	tween.tween_property(prop, ^"global_position", prop.global_position + direction * distance, SLIDE_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# A small turn: the push hits off center.
	tween.parallel().tween_property(prop, ^"rotation:y", prop.rotation.y + randf_range(-0.12, 0.12), SLIDE_TIME)
	var pivot := prop.get_pivot()
	if pivot != null:
		pivot.rotation.z = clampf(pivot.rotation.z + randf_range(-0.04, 0.04), -0.12, 0.12)
		pivot.scale.x = maxf(pivot.scale.x - 0.03, 0.8)
