extends SceneTree
## Bare hand render (user report 2026-10-22: "when no weapon is equipped, the hands should be visible -
## currently shows 'fist' weapon"). The player has empty hands. The camera looks at the right hand: pictures
## at rest, and every BARE_EVERY frames from the right straight punch (RMB) against a target 12 m ahead.
## Writes the pictures and strip_rest.png / strip_punch.png into BARE_OUT. The 3D view draws only for the
## pictures (software rendering is slow).
##   BARE_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_bare_hand.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"
## Picture crop around the hand (pixels).
const CROP := Vector2i(520, 520)

var _player: Mech
var _skeleton: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("BARE_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://bare_hand")
	DirAccess.make_dir_recursive_absolute(out)
	var every := int(OS.get_environment("BARE_EVERY")) if OS.get_environment("BARE_EVERY") != "" else 6
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = null
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	_player = switcher.mech
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var forward := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.FORWARD
	var target := (load(MECH_SCENE) as PackedScene).instantiate() as Mech
	target.position = _player.global_position + forward * 12.0
	map.add_child(target)
	target.remove_from_group(&"player")
	target.add_to_group(&"lockable")
	for child_name in ["MechInput", "CameraRig"]:
		var node := target.find_child(child_name, true, false)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is Node3D:
				for camera in node.find_children("*", "Camera3D", true, false):
					(camera as Camera3D).current = false
	target.look_at(_player.global_position, Vector3.UP)
	await _frames(20)
	var camera := Camera3D.new()
	camera.fov = 32.0
	map.add_child(camera)
	camera.current = true
	root.disable_3d = true
	var rest: Array[Image] = []
	rest.append(await _shot(camera, "right", out, "rest_right"))
	rest.append(await _shot(camera, "front", out, "rest_front"))
	rest.append(await _shot(camera, "left", out, "rest_left"))
	_save_strip(rest, out + "/strip_rest.png")
	Input.action_press("use_right_arm")
	await _frames(4)
	Input.action_release("use_right_arm")
	var punch: Array[Image] = []
	var frame := 4
	while frame < 4 + every * 9:
		if (frame - 4) % every == 0:
			punch.append(await _shot(camera, "punch", out, "punch_%02d" % frame))
			frame += 2
		else:
			await _frames(1)
			frame += 1
	_save_strip(punch, out + "/strip_punch.png")
	quit()


## One picture of the right hand (or the left one for "left") from the side, the front or the left.
func _shot(camera: Camera3D, view: String, out: String, name: String) -> Image:
	var forward := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	var bone := _skeleton.find_bone("hand_L" if view == "left" else "hand_R")
	var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin
	# From outside and a little in front, so the shoulder armor does not hide the hand.
	var at := hand + side * 8.0 + forward * 6.0
	if view == "front":
		at = hand + (forward * 11.0 + side * 3.0)
	elif view == "left":
		at = hand - side * 8.0 + forward * 6.0
	var look := hand
	if view == "punch":
		# A fixed view of the right arm from the side while it punches forward.
		var chest := _player.global_position + Vector3.UP * 5.0
		look = chest + forward * 3.0
		at = look + side * 15.0 + forward * 3.0
	camera.look_at_from_position(at + Vector3.UP * 1.0, look)
	root.disable_3d = false
	await _frames(1)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	root.disable_3d = true
	image.save_png("%s/%s.png" % [out, name])
	return image


func _save_strip(images: Array[Image], path: String) -> void:
	if images.is_empty():
		return
	var strip := Image.create(CROP.x * images.size(), CROP.y, false, images[0].get_format())
	for i in images.size():
		var image := images[i]
		var from := Vector2i((image.get_width() - CROP.x) / 2, (image.get_height() - CROP.y) / 2)
		strip.blit_rect(image, Rect2i(from, CROP), Vector2i(CROP.x * i, 0))
	strip.save_png(path)
	print("saved %s" % path)
