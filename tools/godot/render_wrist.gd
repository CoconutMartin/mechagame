extends SceneTree
## Wrist close views (user report 2026-10-24: hand and arm disjointed at the wrist). Gives the player
## WRIST_RIGHT / WRIST_LEFT (weapon file names, "-" = empty), holds WRIST_ACTIONS (input actions joined by
## "+") for WRIST_FRAMES frames, then saves close pictures of each hand from its outer side, from above
## (the back of the hand) and from an oblique back-and-above place into WRIST_OUT as <tag>_<side>_<view>.png. xvfb:
##   WRIST_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_wrist.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const WristPin := preload("res://tools/godot/wrist_pin.gd")
## Camera distance from the hand (meters) and the hand frame point the camera looks at.
const DISTANCE := 4.5
const LOOK_AT := Vector3(0.0, 0.25, 0.1)


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
	var out := _env("WRIST_OUT", ProjectSettings.globalize_path("user://wrist_renders"))
	var tag := _env("WRIST_TAG", "w")
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	for layer in map.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = _weapon(_env("WRIST_RIGHT", "-"))
	loadout.weapon_left = _weapon(_env("WRIST_LEFT", "-"))
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(30)
	var actions := _env("WRIST_ACTIONS", "").split("+", false)
	for action in actions:
		Input.action_press(action)
	await _frames(int(_env("WRIST_FRAMES", "90")))
	var control := switcher.mech.find_child("MechHandControl", true, false) as MechHandControl
	var marks := _env("WRIST_MARKS", "") == "1"
	var marks_now := {}
	var skeleton := switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D
	var record := func() -> void:
		for side in ["R", "L"]:
			var h: MechHand = control.hand_right if side == "R" else control.hand_left
			if h != null and is_instance_valid(h):
				marks_now[side] = _mark_places(h, skeleton, side)
	skeleton.skeleton_updated.connect(record)
	await _frames(2)
	skeleton.skeleton_updated.disconnect(record)
	var camera := Camera3D.new()
	camera.fov = 30.0
	map.add_child(camera)
	camera.current = true
	for side in _env("WRIST_SIDES", "RL"):
		var hand: MechHand = control.hand_right if side == "R" else control.hand_left
		if hand == null or not is_instance_valid(hand):
			continue
		if marks:
			_add_marks(map, marks_now[side])
		var outward := 1.0 if side == "R" else -1.0
		# Hand frame: +X toward the thumb side of the right hand (inner), so outer is -X on the right hand.
		var views := {"side": Vector3(-outward, 0.0, 0.0), "top": Vector3(0.0, 0.0, 1.0), "oblique": Vector3(-outward * 0.7, 0.5, 0.7)}
		for view: String in views:
			var look := hand.global_transform * LOOK_AT
			var from := hand.global_transform * (LOOK_AT + (views[view] as Vector3).normalized() * DISTANCE)
			var up := hand.global_basis.y if view == "top" else Vector3.UP
			camera.look_at_from_position(from, look, up)
			await _frames(2)
			map.get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, tag, side, view])
	for action in actions:
		Input.action_release(action)
	quit()


## The marker places this frame (they come from the pose with the modifiers, so call it during skeleton_updated).
func _mark_places(hand: MechHand, skeleton: Skeleton3D, side: String) -> Dictionary:
	var bone_pose := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side))
	var wrist := hand.find_child("Wrist", true, false) as MeshInstance3D
	return {Color(1, 0, 0): bone_pose.origin, Color(0, 0.4, 1): WristPin.center(skeleton, side),
			Color(0, 1, 0): wrist.global_transform * wrist.get_aabb().get_center()}


## Small balls on top of everything: red = hand bone origin, blue = the forearm's end center (the wrist pin),
## green = the hand model's own wrist joint.
func _add_marks(map: Node, places: Dictionary) -> void:
	for color: Color in places:
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.04
		sphere.height = 0.08
		ball.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		ball.material_override = material
		map.add_child(ball)
		ball.global_position = places[color]
