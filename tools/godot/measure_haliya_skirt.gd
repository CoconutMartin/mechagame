extends SceneTree
## How deep the skirt plates and the legs of Haliya (key 2) go into each other: stand, walk, ADS and crouch (the Ctrl kneel).
## The pieces are convex, so a vertex of one inside all the face planes of the other is a clip; the depth is its distance to the nearest face.
## Headless: godot --headless --path . --script res://tools/godot/measure_haliya_skirt.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const SAMPLE_FRAMES := 40
## Thigh armor only slides under a side plate by design below this depth (m).
const REPORT_DEPTH := 0.02

var _skeleton: Skeleton3D
var _hitboxes: SkeletalHitboxes
var _plates: Array[MeshInstance3D] = []
var _legs: Array[MeshInstance3D] = []
var _worst := {}
var _turns := {}


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	switcher.switch_to(switcher.loadouts[1])
	await _frames(30)
	var mech := switcher.mech
	_hitboxes = mech.get_node("SkeletalHitboxes") as SkeletalHitboxes
	_skeleton = _hitboxes.skeleton
	for mesh: MeshInstance3D in _hitboxes.mesh_bones:
		if mesh.name.begins_with("Skirt_side") or mesh.name.begins_with("Skirt_rear"):
			_plates.append(mesh)
		elif mesh.name.begins_with("Legs_thigh") or mesh.name.begins_with("Legs_guard") or mesh.name.begins_with("Legs_knee") or mesh.name.begins_with("Legs_calf"):
			_legs.append(mesh)
	print("plates ", _plates.size(), " legs ", _legs.size())
	var pads: Array[MeshInstance3D] = []
	var near: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in _hitboxes.mesh_bones:
		if mesh.name.begins_with("Arm_sleeve"):
			pads.append(mesh)
		elif mesh.name.begins_with("Head_") or mesh.name.begins_with("Core_shell") or mesh.name.begins_with("Core_collar") or mesh.name.begins_with("Arm_fore") or mesh.name.begins_with("Arm_guard") or mesh.name.begins_with("Arm_elbow"):
			near.append(mesh)
	if OS.get_environment("PADS") == "1":
		_plates = pads
		_legs = near
	await _state("stand", [], 30)
	await _state("walk", [&"move_forward"], 60)
	await _state("ADS", [&"aim"], 120)
	await _state("crouch", [&"crouch"], 90)
	await _state("run", [&"move_forward", &"boost"], 90)
	quit()


func _state(label: String, actions: Array, settle: int) -> void:
	for action: StringName in actions:
		Input.action_press(action)
	await _frames(settle)
	_worst.clear()
	_turns.clear()
	var measure := _measure
	_skeleton.skeleton_updated.connect(measure)
	await _frames(SAMPLE_FRAMES)
	_skeleton.skeleton_updated.disconnect(measure)
	for action: StringName in actions:
		Input.action_release(action)
	var pairs := _worst.keys()
	pairs.sort_custom(func(a, b): return _worst[a] > _worst[b])
	print("%s: largest turn, pad %.1f deg, skirt %.1f deg" % [label, _turns.get(&"sleeve_L", 0.0), _turns.get(&"skirt_side_L", 0.0)])
	var text := "%s: worst %.3f m" % [label, _worst[pairs[0]] if not pairs.is_empty() else 0.0]
	for pair in pairs.slice(0, 6):
		text += " | %s %.3f" % [pair, _worst[pair]]
	print(text)
	await _frames(40)


## Vertices in the skeleton's frame now (poses of the modifiers exist only inside the skeleton update).
func _points(mesh: MeshInstance3D) -> PackedVector3Array:
	var bone: int = _hitboxes.mesh_bones[mesh]
	var move := _skeleton.get_bone_global_pose(bone) * _skeleton.get_bone_global_rest(bone).affine_inverse() * mesh.transform
	var out := PackedVector3Array()
	for vertex in (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		out.append(move * vertex)
	return out


func _planes(mesh: MeshInstance3D) -> Array[Plane]:
	var bone: int = _hitboxes.mesh_bones[mesh]
	var move := _skeleton.get_bone_global_pose(bone) * _skeleton.get_bone_global_rest(bone).affine_inverse() * mesh.transform
	var planes: Array[Plane] = []
	for face in mesh.mesh.get_faces().size() / 3:
		var faces := mesh.mesh.get_faces()
		var a := move * faces[face * 3]
		var b := move * faces[face * 3 + 1]
		var c := move * faces[face * 3 + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() > 0.000001:
			# Godot winds front faces clockwise: this normal points inward.
			planes.append(Plane(-normal.normalized(), a))
	return planes


func _depth(points: PackedVector3Array, planes: Array[Plane]) -> float:
	var deepest := 0.0
	for point in points:
		var nearest := INF
		for plane in planes:
			var distance := -plane.distance_to(point)
			if distance <= 0.0:
				nearest = -1.0
				break
			nearest = minf(nearest, distance)
		if nearest != INF and nearest > deepest:
			deepest = nearest
	return deepest


func _measure() -> void:
	for bone_name: StringName in [&"sleeve_L", &"skirt_side_L"]:
		var bone := _skeleton.find_bone(bone_name)
		var turn := rad_to_deg(_skeleton.get_bone_pose_rotation(bone).angle_to(_skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()))
		_turns[bone_name] = maxf(_turns.get(bone_name, 0.0), turn)
	if Engine.get_process_frames() % 8 != 0:
		return
	for plate in _plates:
		var plate_points := _points(plate)
		var plate_planes := _planes(plate)
		for leg in _legs:
			var depth := maxf(_depth(_points(leg), plate_planes), _depth(plate_points, _planes(leg)))
			if depth > REPORT_DEPTH:
				var key := "%s/%s" % [plate.name, leg.name]
				_worst[key] = maxf(_worst.get(key, 0.0), depth)
