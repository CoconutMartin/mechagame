extends SceneTree
## Captures a mech's standing pose (rifle and shield held) for posing a Blender kit.
## Run from the project root:
##   godot --headless --path . --script res://tools/godot/capture_pose.gd -- <loadout.tres> <out_folder>
## Writes into out_folder (project relative):
##   pose.json   frame joints in mech space (feet at 0, front -Z): rest and posed transforms
##   weapons.glb the held weapons in mech space (reference for Blender)
##   mech_posed.glb the whole posed mech in mech space (to check the game result against Blender)

const JOINTS := ["Torso", "Lower", "ShoulderL", "ElbowL", "ShoulderR", "ElbowR", "HipL", "KneeL", "HipR", "KneeR",
		"FootPivotL", "FootPivotR"]
## Physics frames to wait before the capture (the weapon and arm poses settle; idle motion starts later).
const SETTLE_FRAMES := 40


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var loadout_path := args[0] if args.size() > 0 else "res://data/loadouts/medium_mech.tres"
	var out := args[1] if args.size() > 1 else "models/medium_mech/pose"
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	shape.shape = box
	shape.position = Vector3(0, -1, 0)
	ground.add_child(shape)
	get_root().add_child(ground)
	var mech := (load("res://scenes/mech/player_mech.tscn") as PackedScene).instantiate() as Node3D
	(mech.get_node("MechAssembler") as MechAssembler).loadout = load(loadout_path)
	get_root().add_child(mech)
	var visual := mech.get_node("Visual") as Node3D
	var rest := {}
	await physics_frame
	for joint in JOINTS:
		rest[joint] = _in_mech(mech, visual.find_child(joint, true, false))
	for i in SETTLE_FRAMES:
		await physics_frame
	var data := {"loadout": loadout_path, "joints": {}}
	for joint in JOINTS:
		data["joints"][joint] = {"rest": rest[joint], "pose": _in_mech(mech, visual.find_child(joint, true, false))}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	var file := FileAccess.open("res://%s/pose.json" % out, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	_export_weapons(mech, visual, "res://%s/weapons.glb" % out)
	_export_tree(visual, mech, "res://%s/mech_posed.glb" % out)
	quit()


## The whole posed mech (parts and weapons) in mech space, to compare with the Blender kit.
func _export_tree(visual: Node3D, mech: Node3D, path: String) -> void:
	var holder := Node3D.new()
	get_root().add_child(holder)
	holder.global_transform = mech.global_transform
	var copy := visual.duplicate() as Node3D
	holder.add_child(copy)
	copy.global_transform = visual.global_transform
	_save_glb(holder, path)


func _save_glb(holder: Node3D, path: String) -> void:
	var drop: Array[Node] = []
	for node in holder.find_children("*", "", true, false):
		if (node is Node3D and not (node as Node3D).visible) or node is Light3D or node is CollisionObject3D \
				or node is CollisionShape3D or node is GPUParticles3D or node is CPUParticles3D:
			drop.append(node)
	for node in drop:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(holder, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	print(path.get_file(), " -> ", error_string(err))


## Transform of a node in mech space, as 12 numbers: basis columns x, y, z, then origin.
func _in_mech(mech: Node3D, node: Node) -> Array:
	var t := mech.global_transform.affine_inverse() * (node as Node3D).global_transform
	t.basis = t.basis.orthonormalized()
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


## The held weapons (nodes from a weapon scene) as one .glb in mech space.
func _export_weapons(mech: Node3D, visual: Node3D, path: String) -> void:
	var holder := Node3D.new()
	get_root().add_child(holder)
	holder.global_transform = mech.global_transform
	var held: Array[Node3D] = []
	for node in visual.find_children("*", "Node3D", true, false):
		if node.scene_file_path.contains("/weapons/") and node.get_parent().scene_file_path.is_empty():
			held.append(node as Node3D)
	# A shield is attached like a part (its pieces go onto the arm sockets): WeaponController lists them.
	var controller := mech.find_children("*", "WeaponController", true, false)
	if not controller.is_empty():
		for node in (controller[0] as WeaponController).shield_nodes:
			held.append(node)
	for node in held:
		var copy := node.duplicate() as Node3D
		holder.add_child(copy)
		copy.global_transform = node.global_transform
	_save_glb(holder, path)
