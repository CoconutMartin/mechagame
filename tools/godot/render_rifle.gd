extends SceneTree
## Pictures of the gun on the forearm and the shoulders (user requests 2026-10-24). Holds RIFLE_RIGHT /
## RIFLE_LEFT (weapon file names, "-" = empty; defaults heavy_rifle / -), presses RIFLE_ACTIONS (input
## actions joined by ",", e.g. "use_right_arm" to raise a one-hand gun; default none = rest), waits
## RIFLE_FRAMES frames (default 90), logs the arm numbers (measure_arms_probe.gd) and saves pictures into
## RIFLE_OUT (rifle_<view>.png). RIFLE_VIEWS: comma list of side, front, top (orthographic, centred on the
## chest, RIFLE_SIZE m tall, default 8) and p_side, p_front, p_back (perspective close-ups). With
## RIFLE_LINES=1 the forearm bone line (red), the forearm armor axis (yellow) and the gun's bore line (green)
## are drawn through the arm. RIFLE_BACK=left/right sets the back weapons (e.g. auto_cannon_shoulder/auto_cannon_shoulder). RIFLE_SIDE (R or L) picks the arm the close-ups look at.
##   RIFLE_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_rifle.gd

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


func _weapon(name: String) -> WeaponData:
	return null if name == "-" or name == "" else load("res://data/weapons/%s.tres" % name) as WeaponData


func _run() -> void:
	var out := _env("RIFLE_OUT", ProjectSettings.globalize_path("user://rifle_renders"))
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = _weapon(_env("RIFLE_RIGHT", "heavy_rifle"))
	loadout.weapon_left = _weapon(_env("RIFLE_LEFT", "-"))
	# RIFLE_BACK: "left/right" back weapon file names ("-" = empty); unset keeps the loadout's.
	# RIFLE_PACK: back pack file name in data/parts/backpacks (e.g. backpack_heavy); unset keeps the loadout's.
	if OS.has_environment("RIFLE_PACK"):
		loadout.back_pack = load("res://data/parts/backpacks/%s.tres" % OS.get_environment("RIFLE_PACK")) as BackPackPart
	if OS.has_environment("RIFLE_BACK"):
		var backs := OS.get_environment("RIFLE_BACK").split("/")
		loadout.back_left = _weapon(backs[0])
		loadout.back_right = _weapon(backs[1] if backs.size() > 1 else "-")
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var weapons := player.get_node("WeaponController") as WeaponController
	var actions := _env("RIFLE_ACTIONS", "").split(",", false)
	for action in actions:
		Input.action_press(action)
	await _frames(int(_env("RIFLE_FRAMES", "90")))
	# RIFLE_CLIP=<seconds>: plays the Pile Bunker punch clip of the right weapon and takes the pictures at that clip time.
	if OS.has_environment("RIFLE_CLIP"):
		var bunker := (weapons.left_weapon if _env("RIFLE_CLIP_SIDE", "R") == "L" else weapons.right_weapon) as PileBunkerWeapon
		var melee := player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
		if bunker != null and OS.has_environment("RIFLE_CLIP_NUMBER"):
			bunker.clip_number = int(OS.get_environment("RIFLE_CLIP_NUMBER"))
		if bunker != null and melee != null and bunker._start_clip():
			while melee.is_playing and melee.external_time(bunker) < float(OS.get_environment("RIFLE_CLIP")) - 0.05:
				await _frames(1)
	var probe := Probe.new()
	var sample := func() -> void:
		_snap = probe.snapshot(player, skeleton, weapons)
	skeleton.skeleton_updated.connect(sample)
	await _frames(3)
	skeleton.skeleton_updated.disconnect(sample)
	for side: String in Probe.SIDES:
		print(Probe.describe(side, _snap[side]))
	var body: Transform3D = _snap.body
	if _env("RIFLE_LINES", "") == "1":
		for side: String in Probe.SIDES:
			_draw_lines(map, body, _snap[side])
	var camera := Camera3D.new()
	map.add_child(camera)
	camera.current = true
	var ortho := float(_env("RIFLE_SIZE", "8"))
	var side_name := _env("RIFLE_SIDE", "R")
	var arm_data: Dictionary = _snap[side_name]
	var chest: Vector3 = body * Vector3(0.0, -1.3, -0.8)
	var right := body.basis.x
	var forward := -body.basis.z
	var arm_center: Vector3 = body * ((arm_data.el as Vector3).lerp(arm_data.wr, 0.5) + Vector3(0.0, -0.4, 0.0))
	var out_dir := right if side_name == "R" else -right
	for view in _env("RIFLE_VIEWS", "side,front,top").split(",", false):
		match view:
			"side":
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = ortho
				camera.look_at_from_position(chest + right * 40.0, chest, Vector3.UP)
			"front":
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = ortho
				camera.look_at_from_position(chest + forward * 40.0, chest, Vector3.UP)
			"top":
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = ortho
				camera.look_at_from_position(chest + Vector3.UP * 40.0, chest, -forward)
			"p_side":
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 30.0
				camera.look_at_from_position(arm_center + out_dir * 22.0, arm_center, Vector3.UP)
			"p_front":
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 30.0
				camera.look_at_from_position(arm_center + forward * 22.0 + out_dir * 1.0, arm_center, Vector3.UP)
			"far":
				# Whole mech from its right side, level, from the mech root (not the torso frame).
				var center := player.global_position + Vector3.UP * 5.0
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = 14.0
				camera.look_at_from_position(center + player.global_basis.x * 40.0, center, Vector3.UP)
			"far_front":
				var center_f := player.global_position + Vector3.UP * 5.0
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = 14.0
				camera.look_at_from_position(center_f - player.global_basis.z * 40.0, center_f, Vector3.UP)
			"p_inner":
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 20.0
				camera.look_at_from_position(arm_center - out_dir * 14.0 + forward * 6.0, arm_center, Vector3.UP)
			"p_below":
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 20.0
				camera.look_at_from_position(arm_center + forward * 10.0 - Vector3.UP * 8.0 + out_dir * 4.0, arm_center, Vector3.UP)
			"p_hand":
				# The right fist from in front, a little below and outside (user picture 2026-10-30).
				var fist := (player.find_child("MechHandControl", true, false) as MechHandControl).hand_right.global_position
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 25.0
				camera.look_at_from_position(fist + forward * 9.0 - Vector3.UP * 3.0 + out_dir * 3.0, fist, Vector3.UP)
			"p_back":
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 30.0
				camera.look_at_from_position(arm_center - forward * 22.0, arm_center, Vector3.UP)
		await _frames(2)
		map.get_viewport().get_texture().get_image().save_png("%s/rifle_%s.png" % [out, view])
	for action in actions:
		Input.action_release(action)
	quit()


## Thin unshaded lines through one arm: forearm bone (red), forearm armor axis (yellow), gun bore (green).
func _draw_lines(map: Node, body: Transform3D, data: Dictionary) -> void:
	var elbow: Vector3 = body * data.el
	var wrist: Vector3 = body * data.wr
	var forearm := (wrist - elbow).normalized()
	_line(map, elbow - forearm * 1.0, wrist + forearm * 5.0, Color(1, 0.1, 0.1))
	if data.has("armor_dir"):
		var armor: Vector3 = body.basis * data.armor_dir
		_line(map, elbow - armor * 1.0, elbow + armor * 7.0, Color(1, 0.9, 0.1))
	if data.has("gun_dir"):
		var muzzle: Vector3 = body * data.muzzle
		var gun_dir: Vector3 = body.basis * data.gun_dir
		_line(map, muzzle - gun_dir * 7.0, muzzle + gun_dir * 1.0, Color(0.1, 1, 0.1))


func _line(map: Node, from: Vector3, to: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 100
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	map.add_child(node)
	var middle := (from + to) * 0.5
	var y := (to - from).normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	node.global_transform = Transform3D(Basis(x, y, x.cross(y)), middle)
