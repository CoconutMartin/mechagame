extends SceneTree
## Arm clearance and knee bend of the player mech in the game (Haliya legs-only refit, user choice 2026-11-08): stand, walk and boost
## run. Each sampled frame it poses the arm pieces and the hip pieces (skirt plates, thigh armor, hip and belt pieces) and prints, per
## state, how deep an arm vertex goes into a hip piece (the pieces are convex: inside all its face planes, depth to the nearest face),
## the smallest gap between an arm piece and a hip piece (largest face plane distance, a lower bound of the true gap), and the knee
## bend (angle between the thigh and the shin, degrees). MECH=haliya runs it on Haliya (tools/godot/test_mech_choice.gd); without MECH
## only the knee bend is measured (SGG's parts are not single-bone pieces). Headless:
##   MECH=haliya godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_haliya_arm_clearance.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MechChoice := preload("res://tools/godot/test_mech_choice.gd")
## Hip pieces (name prefixes) the arms must clear.
const HIP_PREFIXES: Array[String] = ["Skirt_", "Legs_thigh", "Legs_hip", "Core_belt", "Core_hip"]
## Frames per state after SETTLE frames; every SAMPLE_EVERY-th frame is measured.
const FRAMES := 180
const SETTLE := 60
const SAMPLE_EVERY := 6

var _mech: Mech
var _skeleton: Skeleton3D
var _arms: Array[MeshInstance3D] = []
var _hips: Array[MeshInstance3D] = []
var _depth := 0.0
var _depth_pair := ""
var _gap := INF
var _gap_pair := ""
var _knees: Array[float] = []
var _frame := 0


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
	switcher.rebuild(MechChoice.apply(switcher.current_loadout.duplicate() as Loadout), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	_mech = switcher.mech
	_skeleton = _mech.find_child("Skeleton3D", true, false) as Skeleton3D
	for node in _skeleton.get_children():
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.skin == null or not MechChoice.mech() == "haliya":
			continue
		var slot: StringName = mesh.get_meta(SkeletalPartModels.SLOT_META, &"")
		if slot == &"arm_left" or slot == &"arm_right":
			_arms.append(mesh)
		elif HIP_PREFIXES.any(func(p: String) -> bool: return String(mesh.name).begins_with(p)):
			_hips.append(mesh)
	print("mech %s (%s): %d arm pieces, %d hip pieces" % [_mech.name, _mech.scene_file_path, _arms.size(), _hips.size()])
	for state: Array in [["stand", []], ["walk", [&"move_forward"]], ["boost run", [&"move_forward", &"boost"]]]:
		for action: StringName in state[1]:
			Input.action_press(action)
		await _frames(SETTLE)
		_depth = 0.0
		_gap = INF
		_knees.clear()
		var measure := _measure
		_skeleton.skeleton_updated.connect(measure)
		await _frames(FRAMES)
		_skeleton.skeleton_updated.disconnect(measure)
		for action: StringName in state[1]:
			Input.action_release(action)
		_knees.sort()
		var mean := 0.0
		for k in _knees:
			mean += k
		mean /= maxf(_knees.size(), 1)
		var text := "%s %-9s knee bend mean %.1f, max %.1f deg" % [_mech.name_code, state[0], mean, _knees.back() if not _knees.is_empty() else 0.0]
		if not _arms.is_empty():
			text += "; arms into hip pieces %.3f m (%s); smallest gap %.3f m (%s)" % [_depth, _depth_pair, _gap, _gap_pair]
		print(text)
		await _frames(60)
	quit()


func _measure() -> void:
	_frame += 1
	if _frame % SAMPLE_EVERY != 0:
		return
	for side in ["L", "R"]:
		var thigh := _skeleton.get_bone_global_pose(_skeleton.find_bone("thigh_" + side)).basis.y
		var shin := _skeleton.get_bone_global_pose(_skeleton.find_bone("shin_" + side)).basis.y
		_knees.append(rad_to_deg(thigh.angle_to(shin)))
	var arm_points := {}
	for arm in _arms:
		arm_points[arm] = _points(arm)
	for hip in _hips:
		var planes := _planes(hip)
		for arm in _arms:
			for p: Vector3 in arm_points[arm]:
				var outside := -INF
				for plane in planes:
					outside = maxf(outside, plane.distance_to(p))
				if outside < 0.0 and -outside > _depth:
					_depth = -outside
					_depth_pair = "%s in %s" % [arm.name, hip.name]
				if outside >= 0.0 and outside < _gap:
					_gap = outside
					_gap_pair = "%s to %s" % [arm.name, hip.name]


## The piece's main bone move (pose times bind), for a rigid piece.
func _move(mesh: MeshInstance3D) -> Transform3D:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 1)
	var best := 0
	for k in per:
		if weights[k] > weights[best]:
			best = k
	var index := bones[best]
	var bone := _skeleton.find_bone(mesh.skin.get_bind_name(index))
	return _skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(index)


func _points(mesh: MeshInstance3D) -> PackedVector3Array:
	var move := _move(mesh)
	var out := PackedVector3Array()
	for s in mesh.mesh.get_surface_count():
		for v: Vector3 in (mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			out.append(move * v)
	return out


## Face planes, normals out of the piece.
func _planes(mesh: MeshInstance3D) -> Array[Plane]:
	var move := _move(mesh)
	var faces := mesh.mesh.get_faces()
	var planes: Array[Plane] = []
	for f in faces.size() / 3:
		var a := move * faces[f * 3]
		var b := move * faces[f * 3 + 1]
		var c := move * faces[f * 3 + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() > 0.000001:
			# Godot winds front faces clockwise: this normal points inward.
			planes.append(Plane(-normal.normalized(), a))
	return planes
