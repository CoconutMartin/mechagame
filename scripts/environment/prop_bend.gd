class_name PropBend
extends RefCounted
## BEND reaction (lampposts, traffic lights): the pole bends at its base away from the mech, more at
## higher speed, up to PropDef.bend_max_deg. Its collision turns with it.

## Bend angle per m/s of mech speed, plus a minimum, in degrees.
const DEG_PER_SPEED := 7.0
const MIN_DEG := 25.0
const BEND_TIME := 0.35


static func play(prop: UrbanProp, direction: Vector3, speed: float) -> void:
	var angle := deg_to_rad(minf(MIN_DEG + DEG_PER_SPEED * speed, prop.def.bend_max_deg))
	# Turn axis: across the push direction, in the prop's own space.
	var local_dir := prop.global_basis.inverse() * direction
	local_dir.y = 0.0
	if local_dir.length_squared() < 0.0001:
		local_dir = Vector3.FORWARD
	var axis := Vector3.UP.cross(local_dir.normalized()).normalized()
	var nodes: Array[Node3D] = []
	var starts: Array[Transform3D] = []
	for child in prop.get_children():
		if child is Node3D and child.name != "Contact":
			nodes.append(child)
			starts.append((child as Node3D).transform)
	var tween := prop.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_method(func(t: float) -> void:
		var turn := Transform3D(Basis(axis, angle * t), Vector3.ZERO)
		for i in nodes.size():
			if is_instance_valid(nodes[i]):
				nodes[i].transform = turn * starts[i], 0.0, 1.0, BEND_TIME)
