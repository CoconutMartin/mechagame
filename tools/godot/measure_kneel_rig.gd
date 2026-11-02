extends SceneTree
## Prints the rest pose of the rigged mech's legs, torso and head (skeleton space) and the camera's kneel drop.
func _initialize() -> void:
	_run.call_deferred()
func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame
func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(40)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	print("skeleton xform ", skeleton.global_transform, " model ", player.get_node("Visual/Model").global_transform.basis.get_euler())
	for b in ["pelvis", "torso", "head", "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R", "upper_arm_L", "hand_L"]:
		var i := skeleton.find_bone(b)
		print(b, " rest ", skeleton.get_bone_global_rest(i).origin, " pose ", skeleton.get_bone_global_pose(i).origin, " world ", skeleton.global_transform * skeleton.get_bone_global_pose(i).origin)
	var cam := player.get_node("CameraRig") as MechCameraRig
	print("kneel_height_drop ", cam.kneel_height_drop, " scale ", cam.size_scale if "size_scale" in cam else "?")
	for c in skeleton.get_children():
		print("child ", c.name, " ", c.get_class())
	quit()
