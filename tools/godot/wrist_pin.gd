extends RefCounted
## The wrist pin of the rigged mech: the dark round joint at the end of the forearm armor. The forearm mesh
## (Arm_L_02 / Arm_R_02) has no separate pin mesh, so the pin center is the center of the box around the
## forearm vertices within SLAB meters of its end (along the hand bone's -Y at rest). Every vertex there is
## weighted 100% to the forearm bone (checked in center_share), so the center moves rigidly with that bone.
## This is the measuring side: it reads the mesh itself and does not use MechHandControl's stored pin.

## Length of the forearm end that holds the pin (meters).
const SLAB := 0.12

## Per Mesh resource: the center at rest (skeleton space) and the share of the end vertices' weight that
## goes to the forearm bone (1.0 = all).
static var _found := {}


## World center of the wrist pin this frame (call it during skeleton_updated).
static func center(skeleton: Skeleton3D, side: String) -> Vector3:
	var forearm := skeleton.find_bone("forearm_" + side)
	var rest_center: Vector3 = _slab(skeleton, side).center
	return skeleton.global_transform * skeleton.get_bone_global_pose(forearm) \
			* skeleton.get_bone_global_rest(forearm).affine_inverse() * rest_center


## Share (0..1) of the end vertices' weight that goes to the forearm bone.
static func forearm_share(skeleton: Skeleton3D, side: String) -> float:
	return _slab(skeleton, side).share


static func _slab(skeleton: Skeleton3D, side: String) -> Dictionary:
	var mesh := skeleton.find_child("Arm_%s_02" % side, true, false) as MeshInstance3D
	if _found.has(mesh.mesh):
		return _found[mesh.mesh]
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var forearm := skeleton.find_bone("forearm_" + side)
	var hand_rest := skeleton.get_bone_global_rest(skeleton.find_bone("hand_" + side))
	var to_hand := hand_rest.affine_inverse() * mesh.transform
	var box := AABB()
	var first := true
	var total := 0.0
	var on_forearm := 0.0
	for k in vertices.size():
		if (to_hand * vertices[k]).y < -SLAB:
			continue
		var point: Vector3 = mesh.transform * vertices[k]
		box = AABB(point, Vector3.ZERO) if first else box.expand(point)
		first = false
		for j in 4:
			var bind := bones[k * 4 + j]
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			total += weights[k * 4 + j]
			if bone == forearm:
				on_forearm += weights[k * 4 + j]
	var result := {"center": box.get_center(), "share": on_forearm / maxf(total, 0.0001)}
	_found[mesh.mesh] = result
	return result
