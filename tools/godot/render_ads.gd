extends SceneTree
## Two-hand rifle ADS render and check (user request 2026-10-18: the left hand sits too close to the
## right hand while aiming down sights; move it forward along the forestock). Gives the player
## ADS_WEAPON (weapon file name, default beam_rifle) in the right hand, holds "aim" until the rifle is
## at full aim, then per physics frame (inside skeleton_updated, where the modifier poses exist) logs for
## the left hand: the wrist gap (jointed hand to the forearm's hand bone), the fist hollow to the left
## aim socket, the hand reach offset (MechHandControl), the wrist turn, the upper arm swing against its
## limit, the left shoulder-to-target distance against the arm length, and how far the arm rig had to
## drag the rifle to the hands (0 = both hands reach their markers). Also the suggested left aim marker
## (GripLeft + reach offset: where the arm puts the fist hollow on the socket; at full aim that is the
## GripLeftAim place, or GripLeftAimLow at full low aim).
## ADS_PROBE (comma list of socket z values, weapon space): measure only; for each value the left aim
## socket and the GripLeftAim marker move along the gun to that z (and to the height ADS_PROBE_Y, if
## set; the marker keeps its offset from the socket). ADS_PITCHES (comma list of degrees): measure at
## each aim pitch (camera rig target pitch; -27.5 to 15). ADS_POLE "x,y,z": left_pole_aim for the run. ADS_RENDER 0: no pictures.
## Low aim (2026-10-18): each row also gives the rifle pitch (world) and WeaponPose
## low_aim_amount, and the fist is measured to the socket MechHandControl uses now (it slides to
## GripSocketLeftAimLow). ADS_NO_LOW 1: remove the low aim markers first (the hold before the slide).
## Pictures (ads_<weapon>_<view>.png in ADS_OUT, HUD hidden): right_front (like the user's screenshot),
## left side, top, front, and a close right_front of the forestock; at the camera start pitch, or at
## ADS_PICTURE_PITCH (degrees). ADS_LOW_SPEED: WeaponPose low_aim_speed for the run. ADS_SAMPLE_MOVE 1: each row also covers the move from the pitch before
## (the camera turning), so a pop or a short drag while the hand slides shows up.
##   ADS_WEAPON=beam_sniper ADS_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##     --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_ads.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _player: Mech
var _skeleton: Skeleton3D
var _weapons: WeaponController
var _control: MechHandControl
var _rig: SkeletalArmRig
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _run() -> void:
	var weapon_name := _env("ADS_WEAPON", "beam_rifle")
	var out := _env("ADS_OUT", ProjectSettings.globalize_path("user://ads_renders"))
	var render := _env("ADS_RENDER", "1") == "1"
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
	loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon_name) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	_player = switcher.mech
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_weapons = _player.get_node("WeaponController") as WeaponController
	_control = _player.find_child("MechHandControl", true, false) as MechHandControl
	_rig = _player.find_children("*", "SkeletalArmRig", true, false)[0] as SkeletalArmRig
	if _env("ADS_LOW_SPEED", "") != "":
		_weapons.weapon_pose.low_aim_speed = float(_env("ADS_LOW_SPEED", ""))
	var pole := _env("ADS_POLE", "").split_floats(",", false)
	if pole.size() == 3:
		_weapons.weapon_pose.left_pole_aim = Vector3(pole[0], pole[1], pole[2])
	var gun := _weapons.right_weapon
	if _env("ADS_NO_LOW", "0") == "1":
		for low_name: String in ["GripLeftAimLow", "GripSocketLeftAimLow"]:
			var low_node := gun.get_node_or_null(low_name)
			if low_node != null:
				gun.remove_child(low_node)
				low_node.free()
	var socket := gun.get_node("GripSocketLeftAim") as Node3D
	var marker := gun.get_node("GripLeftAim") as Node3D
	print("%s: GripLeftAim %s, GripSocketLeftAim %s, GripRightAim %s, left_pole_aim %s" % [weapon_name,
			marker.position, socket.position, (gun.get_node("GripRightAim") as Node3D).position,
			_weapons.weapon_pose.left_pole_aim])
	var low_marker := gun.get_node_or_null("GripLeftAimLow") as Node3D
	var low_socket := gun.get_node_or_null("GripSocketLeftAimLow") as Node3D
	print("  low aim: GripLeftAimLow %s, GripSocketLeftAimLow %s, slide from %.1f to %.1f deg" % [
			low_marker.position if low_marker != null else "none", low_socket.position if low_socket != null else "none",
			_weapons.weapon_pose.low_aim_start_deg, _weapons.weapon_pose.low_aim_full_deg])
	if render:
		root.disable_3d = true
	Input.action_press("aim")
	await _frames(150)
	_skeleton.skeleton_updated.connect(_sample)
	var probes := _env("ADS_PROBE", "").split_floats(",", false)
	var pitches := _env("ADS_PITCHES", "").split_floats(",", false)
	var marker_gap := marker.position - socket.position
	var probe_y := _env("ADS_PROBE_Y", "")
	var moving := _env("ADS_SAMPLE_MOVE", "0") == "1"
	for z in probes if not probes.is_empty() else PackedFloat64Array([NAN]):
		var label := "full aim"
		if not is_nan(z):
			socket.position.z = z
			if probe_y != "":
				socket.position.y = float(probe_y)
			marker.position = socket.position + marker_gap
			label = "socket z %.2f" % z
		for pitch in pitches if not pitches.is_empty() else PackedFloat64Array([NAN]):
			if not is_nan(pitch):
				_player.input.camera_rig._target_pitch = deg_to_rad(pitch)
			_rows.clear()
			await _frames(60 if not is_nan(z) or not is_nan(pitch) else 0)
			if not moving:
				_rows.clear()
			await _frames(30)
			_report(label + ("" if is_nan(pitch) else ", aim pitch %.0f deg" % pitch))
	# Pictures at the start pitch (or ADS_PICTURE_PITCH).
	var picture_pitch := _env("ADS_PICTURE_PITCH", "")
	if not pitches.is_empty() or picture_pitch != "":
		var degrees := float(picture_pitch) if picture_pitch != "" else _player.input.camera_rig.start_pitch_deg
		_player.input.camera_rig._target_pitch = deg_to_rad(degrees)
		await _frames(90)
	_skeleton.skeleton_updated.disconnect(_sample)
	if render:
		await _pictures(map, out, weapon_name)
	Input.action_release("aim")
	quit()


## Inside skeleton_updated: the left hand and arm numbers of this frame.
func _sample() -> void:
	var gun := _weapons.right_weapon
	var ik := _weapons.arm_ik_left
	var hand := _control.hand_left
	var state: Dictionary = _control._sides["L"]
	var hand_socket := state.socket as Node3D if is_instance_valid(state.socket) else gun.get_node("GripSocketLeftAim") as Node3D
	var socket := _control._socket_place("L", hand_socket)
	var wrist := (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_L"))).origin
	var hollow := MechHandControl.LEFT_HOLLOW
	hollow.z = MechHandControl.PALM_FACE_Z - float(hand_socket.get_meta(&"grip_radius", 0.15))
	var base: Transform3D = state.base
	var turn := (base.basis.orthonormalized().inverse() * hand.transform.basis.orthonormalized()).get_rotation_quaternion()
	var torso_basis := _weapons.torso.global_basis.orthonormalized()
	var arm := torso_basis.inverse() * (ik.mid_joint.global_position - ik.root_joint.global_position).normalized()
	var torso := _weapons.torso.global_transform.affine_inverse()
	var fore := (hand.global_position - ik.mid_joint.global_position).normalized()
	_rows.append({
		"aim": _weapons.weapon_pose.aim_amount,
		"wrist": hand.global_position.distance_to(wrist),
		"fist": (hand.global_transform * hollow).distance_to(socket.origin),
		"offset": (state.offset as Vector3).length(),
		"suggest": (gun.get_node("GripLeft") as Node3D).position + (state.offset as Vector3),
		"turn": rad_to_deg(turn.get_angle()),
		"lean": rad_to_deg(asin(clampf(-arm.z, -1.0, 1.0))),
		"limit": rad_to_deg(_rig.swing_limit(false)),
		"stretch": ik.root_joint.global_position.distance_to(ik.target.global_position) / (ik.upper_length + ik.lower_length),
		"drag": gun.transform.origin.distance_to(_rig._weapon_base[1].origin),
		"elbow": torso * ik.mid_joint.global_position,
		"shoulder": torso * ik.root_joint.global_position,
		"palm": torso * socket.origin,
		"fore_axis": rad_to_deg(fore.angle_to(socket.basis.y)),
		"pitch": rad_to_deg(asin(clampf(-gun.global_basis.z.normalized().y, -1.0, 1.0))),
		"low": _weapons.weapon_pose.low_aim_amount,
	})


func _report(label: String) -> void:
	var worst := {"wrist": 0.0, "fist": 0.0, "offset": 0.0, "turn": 0.0, "lean": 0.0, "stretch": 0.0, "drag": 0.0}
	for row in _rows:
		for key: String in worst:
			worst[key] = maxf(worst[key], absf(float(row[key])))
	var last: Dictionary = _rows[-1] if not _rows.is_empty() else {}
	print("%s (%d frames, aim %.2f, weapon pitch %.1f deg, low aim %.2f): wrist gap %.3f m, fist to socket %.3f m, reach offset %.3f m, wrist turn %.1f deg, upper arm swing %.1f of %.1f deg, shoulder to target %.2f of the arm, rifle drag %.3f m" % [
			label, _rows.size(), float(last.get("aim", 0.0)), float(last.get("pitch", 0.0)),
			float(last.get("low", 0.0)), worst["wrist"], worst["fist"], worst["offset"],
			worst["turn"], worst["lean"], float(last.get("limit", 0.0)), worst["stretch"], worst["drag"]])
	if not last.is_empty():
		print("    torso space: shoulder %s elbow %s socket %s; forearm to grip axis %.1f deg; suggested GripLeftAim %s" % [
				last["shoulder"], last["elbow"], last["palm"], last["fore_axis"], last["suggest"]])


## Pictures of the aim hold: right front (like the user's screenshot), left side, top.
func _pictures(map: Node, out: String, weapon_name: String) -> void:
	var camera := Camera3D.new()
	camera.fov = 30.0
	map.add_child(camera)
	camera.current = true
	var gun := _weapons.right_weapon
	var forward := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	for layer in map.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var middle := gun.global_transform * Vector3(0.0, 0.0, -2.6)
	var fore := gun.global_transform * Vector3(0.0, -0.3, -3.6)
	var right_front := (forward * 0.75 + side).normalized()
	var views := {"right_front": [middle + right_front * 15.0 + Vector3.UP * 2.0, middle],
			"left": [middle - side * 15.0, middle], "top": [middle + Vector3.UP * 15.0 + forward * 0.01, middle],
			"front": [middle + forward * 15.0 + Vector3.UP * 1.0, middle],
			"close": [fore + right_front * 7.0 + Vector3.UP * 0.5, fore]}
	for view: String in views:
		camera.look_at_from_position(views[view][0], views[view][1])
		root.disable_3d = false
		await _frames(1)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		root.disable_3d = true
		var path := "%s/ads_%s_%s.png" % [out, weapon_name, view]
		image.save_png(path)
		print("saved %s" % path)
