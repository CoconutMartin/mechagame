extends SceneTree
## Aim hold search (user request 2026-10-24: Beam Sniper aim, "adjust the rifle position as necessary, mindful of
## collision"). Holds SEARCH_GUN (default beam_sniper) in the right hand with the actions SEARCH_ACTIONS (default
## "aim"), and for each offset (SEARCH_OFFSETS: "x,y,z;x,y,z;..." torso space, added to the weapon's aim
## origin at run time) waits SEARCH_WAIT frames (default 80; the elbow turns slowly) and prints the right arm's
## elbow and wrist, block tilt and yaw, and how far the gun's mesh points are inside the body meshes' boxes
## (measure_arms_probe.gd clip_check). Nothing is saved; the best offset goes into the weapon data by hand.
##   SEARCH_OFFSETS="0,0,0;0.2,0,0" godot --headless --fixed-fps 60 --path . --script res://tools/godot/measure_arms_search.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const Probe := preload("res://tools/godot/measure_arms_probe.gd")

var _snap: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/%s.tres" % _env("SEARCH_GUN", "beam_sniper")) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var weapons := player.get_node("WeaponController") as WeaponController
	var probe := Probe.new()
	probe.with_clip = true
	var hook := func() -> void:
		_snap = probe.snapshot(player, skeleton, weapons)
	skeleton.skeleton_updated.connect(hook)
	for action in _env("SEARCH_ACTIONS", "aim").split(",", false):
		Input.action_press(action)
	var pose := weapons.weapon_pose
	var base := pose.aim_origin
	await _frames(100)
	for spec in _env("SEARCH_OFFSETS", "0,0,0").split(";", false):
		var parts := spec.split(",")
		pose.aim_origin = base + Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		await _frames(int(_env("SEARCH_WAIT", "80")))
		var arm: Dictionary = _snap.R
		var worst := 0.0
		var who := ""
		for mesh_name: String in arm.clip:
			if float(arm.clip[mesh_name][0]) > worst:
				worst = float(arm.clip[mesh_name][0])
				who = "%s (%s)" % [mesh_name, arm.clip[mesh_name][2]]
		print("offset %s: elbow %s wrist %s | R block tilt %.1f yaw %.1f top %.2f | L block tilt %.1f | deepest gun point inside a body box %.2f m %s" % [
				spec, Probe._v(arm.el), Probe._v(arm.wr), arm.block_tilt, arm.block_yaw, arm.block_top, _snap.L.block_tilt, worst, who])
	quit()
