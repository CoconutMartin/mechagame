extends SceneTree
## Raised shield render and clearance check (user request 2026-10-22: LMB raises the shield, no clipping).
## Builds the player with a shield in the left hand and a gun in the right, holds LMB, and per view saves a
## picture with the shield down and one with it up. In every frame (inside skeleton_updated, where the
## modifier poses exist) it measures the distance (m, positive = clear, negative = inside) from the sampled
## points of the shield to the body armor boxes (torso, head, pelvis, neck, waist, legs, the right arm), and
## to the right-hand weapon and the shoulder cannons, plus the left hand to the body. The boxes are the rest
## boxes of each skinned mesh per bone, 0.05 m smaller (the same boxes as render_jump.gd).
## Environment: SHIELD_LEFT (warden_shield), SHIELD_RIGHT (smg; "-" = empty), SHIELD_BACK ("cannon" = a
## shoulder cannon on each shoulder, "-" = none, default none), SHIELD_VIEWS (front_left,side), SHIELD_OUT,
## SHIELD_RENDER=0 (numbers only), SHIELD_SHOTS=0 (no pictures but the numbers stay).
##   SHIELD_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_shield.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MARGIN := 0.05
const BODY := ["Torso", "Head_001", "Pelvis", "Waist_Joint", "Neck_joint", "Arm_R_01", "Arm_R_02", "Arm_R_Shoulder_Joint",
		"Elbow_R_Joint_01", "Leg_L_01", "Leg_L_02", "Leg_L_03", "Leg_R_01", "Leg_R_02", "Leg_R_03", "Leg_R_04",
		"Leg_L_Hip_Joint", "Leg_R_Hip_Joint", "Leg_L_Knee_Joint", "Leg_R_Knee_Joint", "Pelvis_Connector_R"]
const NOT_RIGHT_ARM := ["Torso", "Head_001", "Pelvis", "Waist_Joint", "Neck_joint", "Leg_L_01", "Leg_L_02", "Leg_L_03",
		"Leg_R_01", "Leg_R_02", "Leg_R_03", "Leg_R_04", "Leg_L_Hip_Joint", "Leg_R_Hip_Joint", "Arm_L_01", "Arm_L_Shoulder_Joint"]
## The left shoulder block belongs to the shield arm; it is measured on its own line.
const LEFT_ARM := ["Arm_L_01", "Arm_L_Shoulder_Joint"]


## Collects the bone poses after all modifiers (it is the last modifier of the skeleton).
class Probe extends SkeletonModifier3D:
	var globals: Array[Transform3D] = []
	var boxes := {}

	func _process_modification_with_delta(_delta: float) -> void:
		var skeleton := get_skeleton()
		var list: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			var parent := skeleton.get_bone_parent(bone)
			var local := skeleton.get_bone_pose(bone)
			list.append(list[parent] * local if parent >= 0 else local)
		globals = list

	## [[bone, AABB], ...] of a skinned mesh: per bone the rest box of the vertices it moves most.
	func boxes_of(skeleton: Skeleton3D, mesh: MeshInstance3D) -> Array:
		if boxes.has(mesh):
			return boxes[mesh]
		var per_bone := {}
		for s in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(s)
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
				var p := mesh.skin.get_bind_pose(index) * vertices[v]
				per_bone[index] = (per_bone[index] as AABB).expand(p) if per_bone.has(index) else AABB(p, Vector3.ZERO)
		var out := []
		for index: int in per_bone:
			var bone := mesh.skin.get_bind_bone(index)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(index))
			out.append([bone, (per_bone[index] as AABB).grow(-MARGIN)])
		boxes[mesh] = out
		return out


var _player: Mech
var _skeleton: Skeleton3D
var _probe: Probe
var _points := {}
var _frame := 0
var _quick_label := ""


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		_frame += 1


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _run() -> void:
	var out := _env("SHIELD_OUT", ProjectSettings.globalize_path("user://shield_renders"))
	DirAccess.make_dir_recursive_absolute(out)
	var render := DisplayServer.get_name() != "headless" and _env("SHIELD_RENDER", "1") != "0"
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_left = _weapon(_env("SHIELD_LEFT", "warden_shield"))
	loadout.weapon_right = _weapon(_env("SHIELD_RIGHT", "smg"))
	var back := _env("SHIELD_BACK", "-")
	loadout.back_left = _weapon("auto_cannon_shoulder" if back == "cannon" else ("missile_pod_l" if back == "pods" else "-"))
	loadout.back_right = _weapon("auto_cannon_shoulder" if back == "cannon" else ("missile_pod_r" if back == "pods" else "-"))
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	_player = switcher.mech
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_probe = Probe.new()
	_skeleton.add_child(_probe)
	var camera := Camera3D.new()
	camera.fov = 32.0
	map.add_child(camera)
	camera.current = true
	for layer in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_hide_trees(map)
	var shield := _player.get_node("MechShield") as MechShield
	# SHIELD_HAND="x,y,z" and SHIELD_POLE="x,y,z": try another raised hand place and elbow direction.
	var pose := _player.find_child("ShieldPose", true, false) as ShieldPose
	if _env("SHIELD_HAND", "") != "":
		var v := _env("SHIELD_HAND", "").split_floats(",")
		pose.raised.position = Vector3(v[0], v[1], v[2])
	if _env("SHIELD_EXP", "") != "":
		var v := _env("SHIELD_EXP", "").split_floats(",")
		pose._path = Vector3(v[0], v[1], v[2])
	if _env("SHIELD_POLE", "") != "":
		var v := _env("SHIELD_POLE", "").split_floats(",")
		pose.pole_raised = Vector3(v[0], v[1], v[2])
	# SHIELD_SLOW=1: the shield moves slowly, so the transition is sampled densely.
	var slow := _env("SHIELD_SLOW", "") == "1"
	if slow:
		shield.raise_speed = 0.4
		shield.lower_speed = 0.4
	await _frames(30)
	if _env("SHIELD_BRACE", "") == "1":
		await _brace_check(camera, out, render)
		quit()
		return
	if _env("SHIELD_SWEEP", "") == "1":
		await _sweep(shield)
		quit()
		return
	var views := _env("SHIELD_VIEWS", "front_left,side").split(",", false)
	var down := _measure("down")
	print(down)
	var shots: Dictionary = {}
	if render:
		for view in views:
			shots["down_" + view] = await _shot(camera, view, out, "down_" + view)
	# LMB: the shield comes up.
	Input.action_press("use_left_arm")
	# SHIELD_AIM=1: RMB too, so the right-hand gun is raised and fires beside the shield.
	if _env("SHIELD_AIM", "") == "1":
		Input.action_press("use_right_arm")
	var raise_frames := 0
	var worst_up := INF
	var worst_up_at := 0.0
	var worst_label := ""
	while shield.amount < 0.999 and raise_frames < 400:
		await _frames(1)
		raise_frames += 1
		if raise_frames % 3 == 0:
			var now := _quick()
			if now < worst_up:
				worst_up = now
				worst_up_at = shield.amount
				worst_label = _quick_label
	print("CLEAR while raising: shield to body / weapon / cannons, worst %.3f m at amount %.2f (%s)" % [worst_up, worst_up_at, worst_label])
	await _frames(40)
	print("raised after %d frames (%.2f s), amount %.2f" % [raise_frames, raise_frames / 60.0, shield.amount])
	var worst := ""
	var up := _measure("up")
	print(up)
	if render:
		for view in views:
			shots["up_" + view] = await _shot(camera, view, out, "up_" + view)
	Input.action_release("use_left_arm")
	Input.action_release("use_right_arm")
	var worst_down := INF
	var worst_down_at := 0.0
	for i in (300 if slow else 70):
		await _frames(1)
		if i % 3 == 0:
			var now := _quick()
			if now < worst_down:
				worst_down = now
				worst_down_at = shield.amount
	print("CLEAR while lowering: worst %.3f m at amount %.2f" % [worst_down, worst_down_at])
	await _frames(30)
	print(_measure("lowered again"))
	print("shield amount after release: %.2f" % shield.amount)
	quit()


## SHIELD_BRACE=1: the left cannon key is held. When the brace is set (and the shot is out) the points of the held
## items (the right weapon, the shield, the shoulder cannons) are measured against the leg, pelvis and torso
## boxes, the same at rest for comparison, and the pelvis drop is printed. With a picture per view when rendering.
func _brace_check(camera: Camera3D, out: String, render: bool) -> void:
	var brace = _player.get_node("WeaponController").shoulder_brace
	# SHIELD_BRACE_PARAMS="lean,hips_back,knee,knee_out": try other stance values.
	if _env("SHIELD_BRACE_PARAMS", "") != "":
		var v := _env("SHIELD_BRACE_PARAMS", "").split_floats(",")
		var stance := _skeleton.get_node("BracePose")
		stance.lean_deg = v[0]
		stance.hips_back = v[1]
		stance.knee_deg = v[2]
		stance.knee_out = v[3]
	var pelvis := _skeleton.find_bone("pelvis")
	var rest_pelvis := (_probe.globals[pelvis] as Transform3D).origin
	var rest := _held_distances()
	print("BRACE rest: held items to legs/torso: %s" % rest)
	if render:
		await _shot(camera, "left", out, "brace_rest_left")
	Input.action_press("fire_back_left")
	var frames := 0
	while brace.amount < 0.999 and frames < 200:
		await _frames(1)
		frames += 1
	await _frames(20)
	var drop: float = rest_pelvis.y - (_probe.globals[pelvis] as Transform3D).origin.y
	print("BRACE set after %d frames, amount %.2f, pelvis drop %.2f m, speed %.2f" % [frames, brace.amount, drop, _player.get_horizontal_speed()])
	print("BRACE braced: held items to legs/torso: %s" % _held_distances())
	if render:
		for view in _env("SHIELD_VIEWS", "left").split(",", false):
			await _shot(camera, view, out, "brace_" + view)
	Input.action_release("fire_back_left")


## "item min distance (m)" for the right weapon, the shield and the cannons against the legs, pelvis and torso.
func _held_distances() -> String:
	var parts := ["Torso", "Pelvis", "Waist_Joint", "Leg_L_01", "Leg_L_02", "Leg_L_03", "Leg_R_01", "Leg_R_02", "Leg_R_03", "Leg_R_04",
			"Leg_L_Hip_Joint", "Leg_R_Hip_Joint", "Leg_L_Knee_Joint", "Leg_R_Knee_Joint", "Pelvis_Connector_R"]
	var text := ""
	for item in ["RightWeapon", "Shield", "BackLeft", "BackRight", "LeftWeapon"]:
		var node := _player.find_child(item, true, false)
		if node == null:
			continue
		if node.has_method(&"get_model"):
			node = node.call(&"get_model")
		var d := _body_distance(_world_points(_meshes([node])), parts)
		text += "%s %.3f (%s); " % [item, d[0], d[1]]
	return text


## SHIELD_SWEEP=1: the raise amount is set by hand from 0 to 1 and back (the arm is not waited for) and the
## shield's distance to the body, the right weapon and the cannons is measured at each step: a fast check of the
## path of the shield (ShieldPose.place_at).
func _sweep(shield: MechShield) -> void:
	shield.set_physics_process(false)
	var worst := INF
	var worst_at := 0.0
	var farthest := 0.0
	var shoulder := _player.find_child("ShieldPose", true, false) as ShieldPose
	for i in 41:
		shield.amount = i / 40.0
		await _frames(3)
		var now := _quick()
		var local := _player.global_transform.affine_inverse()
		var hand_to_shoulder := (shoulder.hand_target.position - Vector3(-1.35, 2.46, 0.03)).length()
		farthest = maxf(farthest, hand_to_shoulder)
		print("SWEEP amount %.3f: min clearance %.3f m (%s)  hand to shoulder %.2f m" % [shield.amount, now, _quick_label, hand_to_shoulder])
		if now < worst:
			worst = now
			worst_at = shield.amount
	print("SWEEP worst %.3f m at amount %.3f, hand reach at most %.2f m (arm length 4.25)" % [worst, worst_at, farthest])


## Smallest distance of the shield to the body boxes, the right weapon and the shoulder cannons now.
func _quick() -> float:
	var shield_pts := _world_points(_meshes(_player.find_children("Shield", "Node3D", true, false)))
	var body := _body_distance(shield_pts, BODY)
	var best: float = body[0]
	_quick_label = body[1]
	var gun := _player.find_child("RightWeapon", true, false)
	if gun != null:
		best = minf(best, _pair_distance(shield_pts, _world_points(_meshes([gun]))))
	for n in ["BackLeft", "BackRight"]:
		var node := _player.find_child(n, true, false)
		if node != null:
			best = minf(best, _pair_distance(shield_pts, _world_points(_meshes([node]))))
	return best


func _weapon(name: String) -> WeaponData:
	return null if name == "-" else load("res://data/weapons/%s.tres" % name) as WeaponData


## Distances from the shield points to the body boxes, the right weapon and the shoulder cannons.
func _measure(label: String) -> String:
	var shield_meshes := _meshes(_player.find_children("Shield", "Node3D", true, false))
	var gun := _player.get_node_or_null("WeaponController/RightWeapon")
	if gun == null:
		gun = _player.find_child("RightWeapon", true, false)
	var gun_meshes := _meshes([gun] if gun != null else [])
	var cannons: Array[MeshInstance3D] = []
	for n in ["BackLeft", "BackRight"]:
		var node := _player.find_child(n, true, false)
		if node != null:
			cannons.append_array(_meshes([node]))
	var lines: PackedStringArray = []
	var shield_pts := _world_points(shield_meshes)
	var local := _player.global_transform.affine_inverse()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point in shield_pts:
		low = low.min(local * point)
		high = high.max(local * point)
	var joints := ""
	for bone_name in ["upper_arm_L", "forearm_L", "hand_L"]:
		var bone := _skeleton.find_bone(bone_name)
		if bone >= 0 and not _probe.globals.is_empty():
			var at: Vector3 = local * (_skeleton.global_transform * (_probe.globals[bone] as Transform3D).origin)
			joints += " %s(%.2f,%.2f,%.2f)" % [bone_name, at.x, at.y, at.z]
	lines.append("JOINTS %s in mech space:%s" % [label, joints])
	lines.append("BOX %s shield in mech space (x right, y up, -z forward): x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f" % [
			label, low.x, high.x, low.y, high.y, low.z, high.z])
	var body := _body_distance(shield_pts, BODY)
	lines.append("CLEAR %s shield to body: min %.3f m (%s)" % [label, body[0], body[1]])
	var left_arm := _body_distance(shield_pts, LEFT_ARM)
	lines.append("CLEAR %s shield to left shoulder block: min %.3f m (%s)" % [label, left_arm[0], left_arm[1]])
	if not gun_meshes.is_empty():
		lines.append("CLEAR %s shield to right weapon: min %.3f m" % [label, _pair_distance(shield_pts, _world_points(gun_meshes))])
		var gun_body := _body_distance(_world_points(gun_meshes), NOT_RIGHT_ARM)
		lines.append("CLEAR %s right weapon to body (not its own arm): min %.3f m (%s)" % [label, gun_body[0], gun_body[1]])
	if not cannons.is_empty():
		lines.append("CLEAR %s shield to shoulder cannons: min %.3f m" % [label, _pair_distance(shield_pts, _world_points(cannons))])
	return "\n".join(lines)


func _meshes(roots: Array) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for root_node: Node in roots:
		if root_node is MeshInstance3D:
			out.append(root_node as MeshInstance3D)
		for n in root_node.find_children("*", "MeshInstance3D", true, false):
			var mesh := n as MeshInstance3D
			if mesh.is_visible_in_tree() and mesh.mesh != null and not String(mesh.name).begins_with("HPIndicator") \
					and mesh.skin == null and not mesh.get_parent().name.begins_with("MuzzleFlash"):
				out.append(mesh)
	return out


## Sampled mesh points in world space.
func _world_points(meshes: Array[MeshInstance3D]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mesh in meshes:
		if not _points.has(mesh):
			var pts := PackedVector3Array()
			var all := mesh.mesh.get_faces()
			var stride := maxi(1, all.size() / 300)
			for i in range(0, all.size(), stride):
				pts.append(all[i])
			_points[mesh] = pts
		var to_world := mesh.global_transform
		for p: Vector3 in _points[mesh]:
			out.append(to_world * p)
	return out


## [smallest signed distance from the points to the named armor boxes, label]. Negative = inside the box.
func _body_distance(points: PackedVector3Array, names: Array) -> Array:
	var inverse := _skeleton.global_transform.affine_inverse()
	var best := INF
	var label := ""
	for name: String in names:
		var mesh := _skeleton.get_node_or_null(name) as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree():
			continue
		for box: Array in _probe.boxes_of(_skeleton, mesh):
			var to_box := (_probe.globals[box[0]] as Transform3D).affine_inverse() * inverse
			var aabb := box[1] as AABB
			for point in points:
				var q := to_box * point
				var d := _box_distance(aabb, q)
				if d < best:
					best = d
					label = "%s@(%.1f,%.1f,%.1f)" % [name, point.x - _player.global_position.x, point.y - _player.global_position.y, point.z - _player.global_position.z]
	return [best, label]


## Signed distance from a point to a box (negative inside, the depth to the nearest face).
static func _box_distance(aabb: AABB, q: Vector3) -> float:
	var center := aabb.get_center()
	var half := aabb.size * 0.5
	var d := (q - center).abs() - half
	var outside := Vector3(maxf(d.x, 0.0), maxf(d.y, 0.0), maxf(d.z, 0.0)).length()
	return outside + minf(maxf(d.x, maxf(d.y, d.z)), 0.0)


static func _pair_distance(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var best := INF
	for p in a:
		for q in b:
			best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


func _shot(camera: Camera3D, view: String, out: String, name: String) -> Image:
	var origin := _player.global_position
	var forward := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	# "front_left": in front of the mech and to its left (camera on the shield side).
	var direction := side
	match view:
		"front_left":
			direction = (forward * cos(deg_to_rad(35.0)) - side * sin(deg_to_rad(35.0))).normalized()
		"front":
			direction = forward
		"left":
			direction = -side
	var distance := 30.0
	# "flA_D": A degrees from the front toward the left side, D meters away (a building may be in the way).
	if view.begins_with("fl") and view.length() > 2:
		var parts := view.substr(2).split("_")
		direction = (forward * cos(deg_to_rad(float(parts[0]))) - side * sin(deg_to_rad(float(parts[0])))).normalized()
		distance = float(parts[1])
	var middle := origin + Vector3(0, 5.0, 0)
	# A building in the way: the camera comes closer.
	var query := PhysicsRayQueryParameters3D.create(middle, middle + direction * distance, 1)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		distance = maxf(middle.distance_to(hit.position) - 1.0, 8.0)
	camera.global_position = middle + direction * distance
	camera.fov = 32.0 * clampf(30.0 / distance, 1.0, 2.0)
	camera.look_at(middle, Vector3.UP)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [out, name])
	return image


func _hide_trees(map: Node) -> void:
	for node in map.find_children("*", "Node3D", true, false):
		var lower := String(node.name).to_lower()
		if lower.contains("tree") or lower.contains("palm"):
			if Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z).length() < 60.0:
				(node as Node3D).visible = false
