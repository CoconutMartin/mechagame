extends SceneTree
## Exports a built mech (all parts on the frame, rest pose) as one .glb, for the Blender kit guide.
## Run from the project root:
##   godot --headless --script res://tools/godot/export_guide.gd -- res://scenes/mech/og_mech.tscn models/guides/og_guide.glb
## Hitboxes, flames, lights and hidden nodes are left out.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://scenes/mech/og_mech.tscn"
	var out := args[1] if args.size() > 1 else "models/guides/og_guide.glb"
	var mech := (load(scene_path) as PackedScene).instantiate() as Node3D
	get_root().add_child(mech)
	mech.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var visual := mech.get_node("Visual") as Node3D
	for node in visual.find_children("*", "", true, false):
		# Hidden nodes are left out too: Blender 4.0 cannot read the glTF node visibility extension.
		var hidden: bool = node is Node3D and not (node as Node3D).visible
		if hidden or node is PartHitbox or node is Light3D or node.is_in_group(&"booster_flame") or node.is_in_group(&"brake_flame"):
			node.get_parent().remove_child(node)
			node.queue_free()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var error := doc.append_from_scene(visual, state)
	if error == OK:
		error = doc.write_to_filesystem(state, ProjectSettings.globalize_path("res://" + out) if not out.is_absolute_path() else out)
	print("export ", out, " -> ", error_string(error))
	quit()
