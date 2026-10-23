extends RefCounted
## Test helper (user request 2026-10-22, thumb over the grip): how deep the fingers and the thumb of a
## MechHand go into a gun's real mesh. Used by render_thumb.gd and test_thumb_wrap.gd.


## Per finger name: [deepest depth in meters, where (hand space)]. Sample points are centers along each
## segment; depth = the finger radius minus the distance to the nearest gun triangle (0 = clear). The first
## 3/8 of the first segment of each finger is skipped (the hand's own knuckle and thumb mount).
## handle_only keeps the triangles within 0.1 m of the grip surface (the handle, not the gun body).
## shift moves the hand's points (world, to test a hand placed lower on the grip); first_joint starts
## at that joint of each finger.
static func depths(hand: MechHand, gun: Node3D, shift: Vector3 = Vector3.ZERO, first_joint: int = 0,
		handle_only: bool = false) -> Dictionary:
	var triangles := gun_triangles(gun)
	if handle_only:
		triangles = handle_triangles(triangles, hand.grip_center, hand.grip_axis.normalized(), hand.grip_radius + 0.1)
	var out := {}
	var to_hand := hand.global_transform.affine_inverse()
	for name: String in hand._joints:
		var joints: Array = hand._joints[name]
		var radius := hand.thumb_radius if name == "Thumb" else hand.finger_radius
		var worst := 0.0
		var where := Vector3.ZERO
		for i in range(first_joint, 3):
			var joint := joints[i] as Node3D
			var length: float = (joints[i + 1] as Node3D).position.length() if i < 2 else hand._tip[name]
			for k in range(0, 9):
				if i == 0 and k < 3:
					continue
				var p: Vector3 = joint.global_transform * Vector3(0.0, length * k / 8.0, 0.0) + shift
				var depth := depth_at(p, radius, triangles)
				if depth > worst:
					worst = depth
					where = to_hand * p
		out[name] = [worst, where]
	return out


## The gun's mesh triangles in world space (muzzle flash and shield meshes skipped). A forearm gun keeps
## its model on the forearm, so that model is used.
static func gun_triangles(gun: Node3D) -> PackedVector3Array:
	var root := gun
	if gun.has_method(&"get_model") and gun.call(&"get_model") != null:
		root = gun.call(&"get_model")
	var out := PackedVector3Array()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var path := String(root.get_path_to(mesh))
		if mesh.mesh == null or not mesh.visible or "Muzzle" in path or "Flash" in path or "Shield" in path:
			continue
		var to_world := mesh.global_transform
		for v in mesh.mesh.get_faces():
			out.append(to_world * v)
	return out


## The triangles whose center is within reach of the grip axis (world space).
static func handle_triangles(triangles: PackedVector3Array, center: Vector3, axis: Vector3, reach: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for t in range(0, triangles.size(), 3):
		var mid := (triangles[t] + triangles[t + 1] + triangles[t + 2]) / 3.0
		var off := mid - center
		if (off - axis * off.dot(axis)).length() <= reach:
			out.append_array(triangles.slice(t, t + 3))
	return out


## How deep a ball (point p, radius r) is inside the triangles (world space): the radius minus the
## distance to the nearest triangle, 0 when it is clear. (A point buried deep in a solid made of
## overlapping boxes would read as clear; the finger points sit near the surface.)
static func depth_at(p: Vector3, r: float, triangles: PackedVector3Array) -> float:
	var nearest := INF
	for t in range(0, triangles.size(), 3):
		var d := point_triangle(p, triangles[t], triangles[t + 1], triangles[t + 2])
		# A comparison with NaN (a zero-area triangle) is false, so such a triangle is skipped.
		if d < nearest:
			nearest = d
	return maxf(0.0, r - nearest)


## Distance from a point to a triangle (Ericson, Real-Time Collision Detection).
static func point_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return p.distance_to(a)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return p.distance_to(b)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return p.distance_to(a + ab * (d1 / (d1 - d3)))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return p.distance_to(c)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return p.distance_to(a + ac * (d2 / (d2 - d6)))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return p.distance_to(b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))))
	var denom := 1.0 / (va + vb + vc)
	return p.distance_to(a + ab * (vb * denom) + ac * (vc * denom))
