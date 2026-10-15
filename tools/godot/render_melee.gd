extends SceneTree
## Melee test and render tool. Plays every fist and hammer attack against a target mech 7 m in
## front of the player and logs the damage. With a window it also saves a strip of frames per attack.
## Headless (damage log only):
##   godot --headless --path . --script res://tools/godot/render_melee.gd
## Render (frames in user://melee_renders/ or the folder in MELEE_OUT):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_melee.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"
const FIST := "res://data/weapons/fist.tres"
const HAMMER := "res://data/weapons/hammer.tres"
## Distance from the player to the target (m).
const TARGET_DISTANCE := 7.0
## Frames saved per attack.
const FRAMES_PER_ATTACK := 9

## [name, weapon ("fist" or "hammer"), button ("right" or "left"), move key ("" or an action),
##  second press for the hammer combo ([key, frame after the first press]) or []].
const ATTACKS := [
	["fist_straight_r", "fist", "right", "", []],
	["fist_straight_l", "fist", "left", "", []],
	["fist_uppercut_W", "fist", "right", "move_forward", []],
	["fist_swipe_S", "fist", "right", "move_back", []],
	["fist_hook_A", "fist", "left", "move_left", []],
	["fist_hook_D", "fist", "right", "move_right", []],
	["hammer_none", "hammer", "right", "", []],
	["hammer_S", "hammer", "right", "move_back", []],
	["hammer_A_then_D", "hammer", "right", "move_left", ["move_right", 50]],
	["hammer_A_only", "hammer", "right", "move_left", []],
]

var _out_dir := ""
var _render := false
var _damage_log: Array = []


func _initialize() -> void:
	_render = DisplayServer.get_name() != "headless"
	_out_dir = OS.get_environment("MELEE_OUT")
	if _out_dir == "":
		_out_dir = ProjectSettings.globalize_path("user://melee_renders")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	_hide_spawner_enemies(map)
	var only := OS.get_environment("MELEE_ONLY")
	for attack: Array in ATTACKS:
		if only != "" and not (attack[0] as String).contains(only):
			continue
		await _play(map, switcher, attack)
	print("MELEE SUMMARY")
	for line: String in _damage_log:
		print("  ", line)
	quit()


## The spawner enemies would walk into the test and shoot.
func _hide_spawner_enemies(map: Node) -> void:
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false


func _play(map: Node, switcher: LoadoutSwitcher, attack: Array) -> void:
	var name: String = attack[0]
	# A fresh player with the weapon, at the map start place.
	var loadout := switcher.current_loadout.duplicate() as Loadout
	if attack[1] == "fist":
		loadout.weapon_right = load(FIST)
		loadout.weapon_left = load(FIST)
	else:
		loadout.weapon_right = load(HAMMER)
		loadout.weapon_left = null
	var place := Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	switcher.rebuild(loadout, place)
	await _frames(40)
	var player := switcher.mech
	var players := map.get_tree().get_nodes_in_group(&"player")
	var group_ok := players.size() > 0 and players[0] == player and is_instance_valid(player)
	var yaw := player.get_aim_yaw()
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	# The target: the same mech, no input, no camera, high HP.
	var target := (load(MECH_SCENE) as PackedScene).instantiate() as Mech
	target.name = "MeleeTarget"
	map.add_child(target)
	target.remove_from_group(&"player")
	for child_name in ["MechInput", "CameraRig"]:
		var node := target.find_child(child_name, true, false)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is Node3D:
				for camera in node.find_children("*", "Camera3D", true, false):
					(camera as Camera3D).current = false
	target.global_position = player.global_position + forward * TARGET_DISTANCE
	target.look_at(player.global_position, Vector3.UP)
	await _frames(20)
	var health := target.health
	for key: String in health.max_hp:
		health.max_hp[key] = 100000.0
		health.hp[key] = 100000.0
	var hits: Array = []
	health.damaged.connect(func(key: String, amount: float) -> void: hits.append("%s %.0f" % [key, amount]))
	var melee := player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	var side_camera := _side_camera(map, player, target)
	_hide_trees_near(map, side_camera.global_position, (player.global_position + target.global_position) * 0.5)
	# Press: the move key first (read in the aim frame), then the button.
	var key: String = attack[3]
	if key != "":
		Input.action_press(key)
	await _frames(3)
	var button := "use_right_arm" if attack[2] == "right" else "use_left_arm"
	print("[%s] group_ok=%s can_attack=%s dist=%.2f" % [name, group_ok, melee._can_attack(),
			player.global_position.distance_to(target.global_position)])
	Input.action_press(button)
	await _frames(2)
	Input.action_release(button)
	var started := melee.is_playing
	var combo: Array = attack[4]
	var frame := 0
	var length := melee._attack.animation.length / melee._attack.speed_scale if melee._attack != null else 2.0
	var total := int(length * 60.0) + 30
	var step := maxi(total / FRAMES_PER_ATTACK, 1)
	var min_distance := INF
	var continued := false
	while frame < total:
		if combo.size() == 2 and frame == combo[1]:
			Input.action_release(key)
			Input.action_press(combo[0])
			await _frames(1)
			Input.action_press(button)
			await _frames(2)
			Input.action_release(button)
			frame += 3
		await _frames(1)
		frame += 1
		if melee.is_playing and melee._continue and not continued:
			continued = true
		if melee.is_playing and is_instance_valid(melee._weapon):
			var point := melee._weapon.get_strike_point()
			for hitbox in target.find_children("*", "PartHitbox", true, false):
				min_distance = minf(min_distance, (hitbox as Node3D).global_position.distance_to(point))
			if OS.get_environment("MELEE_TRACE") != "" and frame % 3 == 0:
				var local := player.global_transform.affine_inverse() * point
				print("  t=%.2f strike_local=(%.1f, %.1f, %.1f) player_moved=%.1f" % [melee._time, local.x, local.y, local.z,
						player.global_position.distance_to(place.origin)])
		_follow(side_camera, player, target)
		if _render and frame % step == 0:
			await RenderingServer.frame_post_draw
			var image := root.get_viewport().get_texture().get_image()
			image.save_png("%s/%s_%02d.png" % [_out_dir, name, frame / step])
	if key != "":
		Input.action_release(key)
	if combo.size() == 2:
		Input.action_release(combo[0])
	var line := "%s: started=%s combo=%s hits=%s closest_hitbox_to_strike=%.2f m" % [name, started, continued, hits, min_distance]
	print(line)
	_damage_log.append(line)
	side_camera.queue_free()
	target.queue_free()
	await _frames(5)


## A camera to the side of the two mechs, looking at the middle.
func _side_camera(map: Node, player: Mech, target: Mech) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 50.0
	map.add_child(camera)
	_follow(camera, player, target)
	camera.current = true
	return camera


func _follow(camera: Camera3D, player: Mech, target: Mech) -> void:
	var middle := (player.global_position + target.global_position) * 0.5 + Vector3(0, 6, 0)
	var along := (target.global_position - player.global_position)
	along.y = 0.0
	var side := along.normalized().cross(Vector3.UP)
	camera.global_position = middle + side * 26.0 + Vector3(0, 3, 0)
	camera.look_at(middle, Vector3.UP)


## Trees between the camera and the mechs block the view.
func _hide_trees_near(map: Node, from: Vector3, to: Vector3) -> void:
	for node in map.find_children("*", "Node3D", true, false):
		var lower := String(node.name).to_lower()
		if not (lower.contains("tree") or lower.contains("palm")):
			continue
		var point := (node as Node3D).global_position
		var segment := Geometry3D.get_closest_point_to_segment(point, from, to)
		if Vector2(point.x - segment.x, point.z - segment.z).length() < 8.0:
			(node as Node3D).visible = false
