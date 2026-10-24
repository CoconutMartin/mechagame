extends SceneTree
## Aim behind the mech test (user report 2026-10-24: a wall behind the mech took the crosshair and the arms
## turned back to it). Puts a wall between the camera and the player mech and checks that the crosshair
## target and the mech aim point are in front of the mech, not on the wall; then removes the wall and
## checks the aim still finds a box in front. Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_aim_behind.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


func _box(parent: Node, place: Transform3D, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	# Layer 5 (buildings): the camera spring arm does not hit it, like a real building wall.
	body.collision_layer = 16
	parent.add_child(body)
	body.global_transform = place
	return body


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(60)
	var player := get_first_node_in_group(&"player") as Mech
	var aim := player.find_child("*Aim*", true, false)
	for node in player.find_children("*", "Node", true, false):
		if node.get_script() != null and (node.get_script() as Script).get_global_name() == &"MechAim":
			aim = node
	var camera := player.get_node("CameraRig/Pitch/SpringArm/Camera") as Camera3D
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# The wall: half way from the camera to the mech, wide and tall, across the view.
	var half := (player.global_position - camera.global_position).dot(forward) * 0.5
	var behind := camera.global_position + forward * half
	# AIM_NO_SKIP=1: the old aim (the ray from the camera), to see the test fail.
	if OS.get_environment("AIM_NO_SKIP") == "1":
		aim.set("start_ahead_of_mech", -1000.0)
	var wall := _box(current_scene, Transform3D(Basis.looking_at(forward), behind), Vector3(30.0, 20.0, 0.5))
	await _frames(20)
	var mech_depth := (player.global_position - camera.global_position).dot(forward)
	var target: Vector3 = aim.get("camera_target")
	var depth := (target - camera.global_position).dot(forward)
	_check(depth > mech_depth, "wall behind: the crosshair target is in front of the mech (depth %.1f m, mech %.1f m)" % [depth, mech_depth])
	var point: Vector3 = aim.get("aim_point")
	_check((point - player.global_position).dot(forward) > 0.0, "wall behind: the mech aim point is in front (%.1f m)" % (point - player.global_position).dot(forward))
	wall.queue_free()
	# A box 30 m in front, on the crosshair line: still the target.
	var ray: Vector3 = camera.project_ray_normal(aim.call("get_crosshair_screen_point"))
	var ahead := camera.global_position + ray * ((mech_depth + 30.0) / ray.dot(forward))
	_box(current_scene, Transform3D(Basis.looking_at(forward), ahead), Vector3(20.0, 20.0, 1.0))
	await _frames(20)
	target = aim.get("camera_target")
	depth = (target - camera.global_position).dot(forward)
	_check(absf(depth - (mech_depth + 30.0)) < 3.0, "a box 30 m in front is the target (depth %.1f m)" % depth)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
