extends SceneTree
## Garage hand check (user report 2026-10-22: hands off the wrists). Opens the garage (the tree pauses), changes
## the loadout GARAGE_RIGHT / GARAGE_LEFT (weapon file names, "-" = empty) so the mech is rebuilt while paused,
## and saves close pictures of both hands into GARAGE_OUT. xvfb:
##   GARAGE_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_garage_hands.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _run() -> void:
	var out := _env("GARAGE_OUT", ProjectSettings.globalize_path("user://garage_hands"))
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(60)
	var map := current_scene
	var garage := map.get_node("Garage") as Garage
	garage.open()
	await _frames(10)
	var edit := Garage._copy(garage.switcher.current_loadout)
	var right := _env("GARAGE_RIGHT", "smg")
	var left := _env("GARAGE_LEFT", "small_shield")
	edit.weapon_right = null if right == "-" else load("res://data/weapons/%s.tres" % right) as WeaponData
	edit.weapon_left = null if left == "-" else load("res://data/weapons/%s.tres" % left) as WeaponData
	garage._edit = edit
	garage._rebuild()
	await _frames(30)
	var mech := garage.switcher.mech
	var control := mech.find_child("MechHandControl", true, false) as MechHandControl
	var camera := Camera3D.new()
	camera.fov = 40.0
	map.add_child(camera)
	camera.current = true
	var forward := Basis(Vector3.UP, mech.get_aim_yaw()) * Vector3.FORWARD
	var side_axis := forward.cross(Vector3.UP)
	camera.look_at_from_position(mech.global_position + Vector3.UP * 6.0 + forward * 22.0, mech.global_position + Vector3.UP * 6.0)
	await _frames(2)
	map.get_viewport().get_texture().get_image().save_png("%s/front.png" % out)
	for side in ["R", "L"]:
		var hand: Node3D = control.hand_right if side == "R" else control.hand_left
		if hand == null:
			continue
		var out_dir := side_axis if side == "R" else -side_axis
		camera.look_at_from_position(hand.global_position + forward * 6.0 + out_dir * 2.0 + Vector3.UP * 1.0, hand.global_position)
		await _frames(2)
		map.get_viewport().get_texture().get_image().save_png("%s/hand_%s.png" % [out, side])
	quit()
