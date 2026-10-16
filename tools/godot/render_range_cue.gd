extends SceneTree
## Crosshair range rule test (user rule 2026-10-16): the brackets show the target's HP color only
## while the target is inside the active weapon's max range (WeaponData.range_m); past it they stay
## white. Gives the player CUE_WEAPON (default shotgun, max 150 m) in the right hand, puts an enemy mech
## in front of the crosshair at each distance in CUE_DISTANCES (default "100") and prints the
## crosshair state. Exits with code 1 when the color rule fails (or the aim misses the enemy: in
## urban_small a building ends the street at 111 m, and under about 30 m the aim passes over the head).
## Saves range_cue_<distance>.png in CUE_OUT. Needs a window (headless stalls):
##   CUE_WEAPON=fist CUE_DISTANCES=60 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##     --rendering-driver opengl3 --resolution 1280x720 --script res://tools/godot/render_range_cue.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("CUE_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://range_cue")
	var render := DisplayServer.get_name() != "headless"
	if render:
		DirAccess.make_dir_recursive_absolute(out)
	var weapon := OS.get_environment("CUE_WEAPON") if OS.get_environment("CUE_WEAPON") != "" else "shotgun"
	var distances := (OS.get_environment("CUE_DISTANCES") if OS.get_environment("CUE_DISTANCES") != "" else "100").split(",")
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon) as WeaponData
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	# The target: the same mech, no input, no camera, a lockable enemy (as tools/godot/render_melee.gd).
	var enemy := (load(MECH_SCENE) as PackedScene).instantiate() as Mech
	enemy.name = "RangeTarget"
	enemy.position = player.global_position + Vector3(40, 0, 0)
	map.add_child(enemy)
	enemy.remove_from_group(&"player")
	enemy.add_to_group(&"lockable")
	for child_name in ["MechInput", "CameraRig"]:
		var node := enemy.find_child(child_name, true, false)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for camera in node.find_children("*", "Camera3D", true, false):
				(camera as Camera3D).current = false
	await _frames(10)
	var reticle: AimReticle = null
	for node in map.find_children("*", "AimReticle", true, false):
		reticle = node as AimReticle
	var failures := 0
	for text in distances:
		var distance := float(text)
		var aim: MechAim = reticle.mech_aim
		var direction: Vector3 = (aim.target_point - aim.aim_origin.global_position)
		direction.y = 0.0
		direction = direction.normalized()
		var spot := player.global_position + direction * distance
		enemy.global_position = Vector3(spot.x, player.global_position.y, spot.z)
		enemy.velocity = Vector3.ZERO
		await _frames(20)
		var status: float = reticle.get("_status")
		var reach := reticle.get_weapon_range()
		var on_enemy: bool = is_instance_valid(aim.target) and (aim.target == enemy or enemy.is_ancestor_of(aim.target as Node))
		var colored := status >= 0.0
		var want_colored := on_enemy and float(reticle.get("_distance")) <= reach
		print("%s, weapon range %.0f m, enemy at %.0f m: aim on enemy %s, aim distance %.0f m, colored %s (want %s)"
				% [weapon, reach, distance, on_enemy, reticle.get("_distance"), colored, want_colored])
		if not on_enemy or colored != want_colored:
			failures += 1
		if render:
			map.get_viewport().get_texture().get_image().save_png("%s/range_cue_%d.png" % [out, int(distance)])
	print("RESULT: %d failures" % failures)
	quit(1 if failures > 0 else 0)
