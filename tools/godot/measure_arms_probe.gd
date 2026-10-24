extends RefCounted
## Arm pose probe (user requests 2026-10-24: one-hand guns along the forearm, Beam Sniper elbow out,
## level shoulders with one weapon). Used by measure_arms.gd and render_rifle.gd; not a tool of its own.
## Call snapshot() inside Skeleton3D.skeleton_updated (the bone poses with the modifiers exist only there).
## All places and directions are in the BODY frame: origin at the middle between the two shoulder bones,
## axes of the torso bone (+X right, +Y up, -Z forward), so the jump guard's frame lift does not count.
## Per side ("L", "R"): sh (shoulder bone), el (elbow), wr (wrist) places; block_tilt (degrees of the shoulder
## block's top face from the body up), block_roll (+ = outer edge up), block_pitch (+ = front up),
## block_yaw (+ = turned to the body's left), block_top (height of the block's top face centre above the
## shoulder bone, m); and for a gun in that hand: gun_dir, forearm angles (see below).

const SIDES := ["L", "R"]
## Body meshes a gun is tested against (the right hand's own meshes are the hand and the forearm armor).
const CLIP_MESHES := ["Torso", "Head_001", "Neck_joint", "Pelvis", "Waist_Joint", "Arm_R_01", "Arm_R_02", "Arm_R_Shoulder_Joint", "Elbow_R_Joint_01",
		"Arm_L_01", "Arm_L_02", "Leg_R_01", "Leg_R_02", "Leg_R_03", "Leg_R_04", "Leg_L_01", "Leg_L_02", "Leg_L_03",
		"Pelvis_Connector_R"]
## Rest boxes of the body meshes are made this much smaller (m), like the jump clearance check.
const CLIP_MARGIN := 0.05

## True: a snapshot also holds the gun's clip check (clip_check) per side with a gun.
var with_clip := false
var _ready_rest := false
var _rest := {}
var _boxes := {}


## Body frame (world) from the torso bone.
func body_frame(player: Node3D, skeleton: Skeleton3D) -> Transform3D:
	var torso := skeleton.find_bone("torso")
	var skin := skeleton.global_basis.orthonormalized()
	var turn := skin * skeleton.get_bone_global_pose(torso).basis.orthonormalized() \
			* skeleton.get_bone_global_rest(torso).basis.orthonormalized().inverse() * skin.inverse()
	var basis := (turn * player.global_basis.orthonormalized()).orthonormalized()
	var mid := Vector3.ZERO
	for name in ["upper_arm_L", "upper_arm_R"]:
		mid += skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin * 0.5
	return Transform3D(basis, mid)


func _setup(skeleton: Skeleton3D) -> void:
	_ready_rest = true
	for side: String in SIDES:
		var armor := skeleton.get_node("Arm_%s_01" % side) as MeshInstance3D
		var bone := skeleton.find_bone("upper_arm_" + side)
		var arrays := armor.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var top := (armor.transform.basis * SkeletalArmRig._top_normal(armor.mesh)).normalized()
		var flat := Basis(Quaternion(top, Vector3.UP))
		# Skeleton-space rest data of the block: the top face points and the forward face normal.
		var top_points := PackedVector3Array()
		var forward := Vector3.ZERO
		for v in vertices.size():
			var n := (armor.transform.basis * normals[v]).normalized()
			if n.dot(top) > 0.9:
				top_points.append(armor.transform * vertices[v])
			var flat_n := flat * n
			var horizontal := Vector3(flat_n.x, 0.0, flat_n.z)
			# Skeleton space at rest: +Z is the mech's front.
			if horizontal.length() > 0.8 and horizontal.normalized().dot(Vector3.BACK) > 0.8:
				forward += n
		_rest[side] = {"top": top, "top_points": top_points, "forward": forward.normalized(), "bone": bone}
	_rest["torso_rest"] = skeleton.get_bone_global_rest(skeleton.find_bone("torso")).basis.orthonormalized()
	for side: String in SIDES:
		_rest[side].armor_axis = _armor_axis(skeleton, side)


## The visible long axis of the forearm armor in the forearm bone's rest space, pointing from the elbow
## toward the wrist: from the middle of the vertices in the elbow-end fifth of its length to the middle of
## the wrist-end fifth (the principal component is skewed by the bulges; the bone axis is the other
## reference).
func _armor_axis(skeleton: Skeleton3D, side: String) -> Vector3:
	var mesh := skeleton.get_node("Arm_%s_02" % side) as MeshInstance3D
	var bone := skeleton.find_bone("forearm_" + side)
	var rest := skeleton.get_bone_global_rest(bone)
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	var points: Array[Vector3] = []
	var low := INF
	var high := -INF
	for v in vertices.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		var index := bones[v * per + best]
		var owner := skeleton.find_bone(mesh.skin.get_bind_name(index))
		var p := rest.affine_inverse() * (skeleton.get_bone_global_rest(owner) * (mesh.skin.get_bind_pose(index) * vertices[v]))
		points.append(p)
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var near := Vector3.ZERO
	var far := Vector3.ZERO
	var near_count := 0
	var far_count := 0
	for p in points:
		if p.y < low + 0.2 * (high - low):
			near += p
			near_count += 1
		elif p.y > high - 0.2 * (high - low):
			far += p
			far_count += 1
	return (far / far_count - near / near_count).normalized()


## One snapshot: {side: {...}} plus "body" (the body frame) and "guard" (the jump guard amount).
func snapshot(player: Node3D, skeleton: Skeleton3D, weapons: WeaponController) -> Dictionary:
	if not _ready_rest:
		_setup(skeleton)
	var body := body_frame(player, skeleton)
	var to_body := body.affine_inverse()
	var skin := skeleton.global_transform
	var out := {"body": body}
	for side: String in SIDES:
		var right := side == "R"
		var sign := 1.0 if right else -1.0
		var bone := _rest[side].bone as int
		var pose := skeleton.get_bone_global_pose(bone)
		var rest_full := skeleton.get_bone_global_rest(bone)
		var turn := skin.basis.orthonormalized() * pose.basis.orthonormalized() * rest_full.basis.orthonormalized().inverse()
		var data := {}
		data.sh = to_body * (skin * pose.origin)
		data.el = to_body * (skin * skeleton.get_bone_global_pose(skeleton.find_bone("forearm_" + side)).origin)
		data.wr = to_body * (skin * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side)).origin)
		var normal: Vector3 = body.basis.inverse() * (turn * (_rest[side].top as Vector3))
		data.block_tilt = rad_to_deg(normal.angle_to(Vector3.UP))
		data.block_roll = rad_to_deg(atan2(normal.x * sign, normal.y))
		data.block_pitch = rad_to_deg(atan2(-normal.z, normal.y))
		var front: Vector3 = body.basis.inverse() * (turn * (_rest[side].forward as Vector3))
		front.y = 0.0
		data.block_yaw = rad_to_deg(Vector3.FORWARD.signed_angle_to(front.normalized(), Vector3.UP)) if front.length() > 0.01 else 0.0
		var top_sum := Vector3.ZERO
		for p: Vector3 in _rest[side].top_points:
			top_sum += p
		var center := top_sum / maxf(float((_rest[side].top_points as PackedVector3Array).size()), 1.0)
		var top_world := skin * (pose * rest_full.affine_inverse() * center)
		data.block_top = (to_body * top_world).y - (data.sh as Vector3).y
		# A gun in this hand.
		var gun: Node3D = weapons.right_weapon if right else weapons.left_weapon
		if gun != null and is_instance_valid(gun) and not gun is MeleeWeapon and not gun is ForearmGunWeapon \
				and gun.get_node_or_null(^"Muzzle") != null:
			var gun_dir: Vector3 = (body.basis.inverse() * -gun.global_basis.z).normalized()
			var fore: Vector3 = ((data.wr as Vector3) - (data.el as Vector3)).normalized()
			data.gun_dir = gun_dir
			var forearm_pose := skeleton.get_bone_global_pose(skeleton.find_bone("forearm_" + side))
			var armor: Vector3 = body.basis.inverse() * (skin.basis.orthonormalized() * forearm_pose.basis.orthonormalized() \
					* (_rest[side].armor_axis as Vector3))
			data.armor_dir = armor
			data.armor_angle = rad_to_deg(gun_dir.angle_to(armor))
			data.armor_side = _side_angle(gun_dir) - _side_angle(armor)
			data.armor_front = _front_angle(gun_dir, sign) - _front_angle(armor, sign)
			data.fore_dir = fore
			data.gun_angle = rad_to_deg(gun_dir.angle_to(fore))
			data.gun_side = _side_angle(gun_dir) - _side_angle(fore)
			data.gun_front = _front_angle(gun_dir, sign) - _front_angle(fore, sign)
			var socket := gun.get_node_or_null(^"GripSocketRight") as Node3D
			var grip: Vector3 = to_body * (socket.global_position if socket != null else gun.global_position)
			var muzzle: Vector3 = to_body * (gun.get_node(^"Muzzle") as Node3D).global_position
			data.grip = grip
			data.muzzle = muzzle
			if with_clip:
				data.clip = clip_check(skeleton, gun)
			data.grip_to_line = _line_distance(grip, data.el, fore)
			data.muzzle_to_line = _line_distance(muzzle, data.el, fore)
		out[side] = data
	return out


## Pitch down from forward in the side view (YZ plane), degrees.
static func _side_angle(dir: Vector3) -> float:
	return rad_to_deg(atan2(-dir.y, -dir.z))


## Lean to the outside from straight down in the front view (XY plane), degrees.
static func _front_angle(dir: Vector3, sign: float) -> float:
	if absf(dir.y) < 0.35:
		return NAN  # Pointing level: the front view has no lean to read.
	return rad_to_deg(atan2(dir.x * sign, -dir.y))


static func _line_distance(point: Vector3, origin: Vector3, direction: Vector3) -> float:
	var along := (point - origin).dot(direction)
	return (point - origin - direction * along).length()


## One line of text for a side of a snapshot.
static func describe(side: String, data: Dictionary) -> String:
	var text := "%s: shoulder %s elbow %s wrist %s | block tilt %.1f (roll %.1f pitch %.1f) yaw %.1f top %.2f" % [
			side, _v(data.sh), _v(data.el), _v(data.wr), data.block_tilt, data.block_roll, data.block_pitch,
			data.block_yaw, data.block_top]
	if data.has("gun_dir"):
		text += "\n     gun vs forearm bone: total %.1f deg, side %+.1f, front %+.1f | vs armor axis: total %.1f, side %+.1f, front %+.1f | grip to forearm line %.2f m, muzzle %.2f m | gun dir %s" % [
				data.gun_angle, data.gun_side, data.gun_front, data.armor_angle, data.armor_side, data.armor_front,
				data.grip_to_line, data.muzzle_to_line, _v(data.gun_dir)]
	if data.has("clip"):
		var parts: PackedStringArray = []
		for mesh_name: String in data.clip:
			var entry: Array = data.clip[mesh_name]
			if entry[1] > 0:
				parts.append("%s %.2f m (%d pts, deepest: %s)" % [mesh_name, entry[0], entry[1], entry[2]])
		text += "\n     gun inside body boxes: " + (", ".join(parts) if not parts.is_empty() else "none")
	return text


static func _v(v: Vector3) -> String:
	return "(%.2f %.2f %.2f)" % [v.x, v.y, v.z]


## How far the gun's mesh points (corners, edge middles, face centres) are inside the body meshes' boxes: per
## mesh name [deepest point (m, 0 = none inside), points inside]. Boxes: per mesh, the rest box (CLIP_MARGIN
## smaller) of each bone's vertices, moved with that bone.
func clip_check(skeleton: Skeleton3D, gun: Node3D) -> Dictionary:
	var points := PackedVector3Array()
	var owners: PackedStringArray = []
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree() or String(mesh_node.get_parent().name).begins_with("MuzzleFlash") \
				or mesh_node.get_parent().name == "Muzzle":
			continue
		var faces := mesh_node.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			var a := faces[i]
			var b := faces[i + 1]
			var c := faces[i + 2]
			for p: Vector3 in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (a + c) * 0.5, (a + b + c) / 3.0]:
				points.append(mesh_node.global_transform * p)
				owners.append(mesh_node.name)
	var out := {}
	for mesh_name: String in CLIP_MESHES:
		var depth := 0.0
		var count := 0
		var culprit := ""
		for entry: Array in _mesh_boxes(skeleton, mesh_name):
			var box: AABB = entry[1]
			# World point to the bone's own space (the space the box is in): undo the bone's pose.
			var pose_inverse := (skeleton.global_transform * skeleton.get_bone_global_pose(entry[0] as int)).affine_inverse()
			for point_index in points.size():
				var p := points[point_index]
				var local := pose_inverse * p
				var inside := minf(minf(minf(local.x - box.position.x, box.position.x + box.size.x - local.x),
						minf(local.y - box.position.y, box.position.y + box.size.y - local.y)),
						minf(local.z - box.position.z, box.position.z + box.size.z - local.z))
				if inside > 0.0:
					if inside > depth:
						culprit = "%s in %s" % [owners[point_index], skeleton.get_bone_name(entry[0] as int)]
					depth = maxf(depth, inside)
					count += 1
		out[mesh_name] = [depth, count, culprit]
	return out


func _mesh_boxes(skeleton: Skeleton3D, mesh_name: String) -> Array:
	if _boxes.has(mesh_name):
		return _boxes[mesh_name]
	var list := []
	var mesh_node := skeleton.get_node_or_null(mesh_name) as MeshInstance3D
	if mesh_node == null or mesh_node.mesh == null or mesh_node.skin == null:
		_boxes[mesh_name] = list
		return list
	var per_bone := {}
	var arrays := mesh_node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(vertices.size(), 1)
	for v in vertices.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		var index := bones[v * per + best]
		var bone := skeleton.find_bone(mesh_node.skin.get_bind_name(index))
		var p := mesh_node.skin.get_bind_pose(index) * vertices[v]  # in the bone's own space
		per_bone[bone] = (per_bone[bone] as AABB).expand(p) if per_bone.has(bone) else AABB(p, Vector3.ZERO)
	for bone: int in per_bone:
		var shrunk := (per_bone[bone] as AABB)
		list.append([bone, AABB(shrunk.position + Vector3.ONE * CLIP_MARGIN, shrunk.size - Vector3.ONE * CLIP_MARGIN * 2.0)])
	_boxes[mesh_name] = list
	return list
