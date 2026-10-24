extends SceneTree
## Wrist pin probe (user report 2026-10-24: "hand and arms are still disjointed at the wrist"). For each loadout in
## WRIST_LOADOUTS (right/left weapon file names, "-" = empty; ";" between loadouts) the player runs the
## WRIST_STEPS (name:actions:frames, actions joined by "+", ";" between steps). Every frame, during
## skeleton_updated (the pose with the modifiers), it measures per hand the distance from the center of the
## forearm's wrist pin (the dark joint at the forearm end, see wrist_pin.gd) to the center of the jointed hand's own wrist joint
## (mesh "Wrist" of the hand model). Prints the largest and the mean per step, plus the offset of the hand
## wrist from the pin in the hand bone's frame (first step only). For a hand that holds a grip it also gives
## the largest miss (the fist hollow to the grip center) and the largest arm reach (HandTarget offset). Headless:
##   godot --headless --path . --script res://tools/godot/measure_wrist_pin.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const WristPin := preload("res://tools/godot/wrist_pin.gd")
const DEFAULT_LOADOUTS := "-/-;smg/small_shield;shotgun/-;heavy_rifle/-;auto_cannon/-;beam_rifle/-;beam_sniper/-"
const DEFAULT_STEPS := "stand::60;walk:move_forward:120;guard:move_forward+use_left_arm:90;aim:aim:60;fire:use_right_arm:60;boost:move_forward+boost:120;stop::90"

var _worst: Dictionary = {}
var _sum: Dictionary = {}
var _count: Dictionary = {}
var _local: Dictionary = {}


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
	for spec in _env("WRIST_LOADOUTS", DEFAULT_LOADOUTS).split(";", false):
		var names := spec.split("/")
		var loadout := switcher.current_loadout.duplicate() as Loadout
		loadout.weapon_right = _weapon(names[0])
		loadout.weapon_left = _weapon(names[1])
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(30)
		var player := switcher.mech
		var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
		var control := player.find_child("MechHandControl", true, false) as MechHandControl
		_local = {}
		var sample := func() -> void: _sample(skeleton, control)
		skeleton.skeleton_updated.connect(sample)
		for step in _env("WRIST_STEPS", DEFAULT_STEPS).split(";", false):
			var parts := step.split(":")
			var actions := parts[1].split("+", false)
			_worst = {}
			_sum = {}
			_count = {}
			for action in actions:
				Input.action_press(action)
			await _frames(int(parts[2]))
			for action in actions:
				Input.action_release(action)
			var text := "%s %s:" % [spec, parts[0]]
			for side in ["R", "L"]:
				var n := float(_count.get(side, 0))
				text += " %s max %.3f mean %.3f" % [side, float(_worst.get(side, -1.0)), float(_sum.get(side, 0.0)) / maxf(n, 1.0)]
				if _worst.has(side + " miss"):
					text += " (fist miss max %.3f mean %.3f, frames over 0.1: %d of %d, reach %.3f)" % [float(_worst[side + " miss"]),
							float(_sum[side + " miss"]) / maxf(n, 1.0), int(_count.get(side + " over", 0)), int(n), float(_worst[side + " reach"])]
			print(text)
		print("%s forearm weight share at the pin: R %.3f L %.3f" % [spec, WristPin.forearm_share(skeleton, "R"), WristPin.forearm_share(skeleton, "L")])
		for side in _local:
			var v: Vector3 = _local[side]
			print("%s %s hand wrist minus pin, hand bone frame: (%.3f, %.3f, %.3f)" % [spec, side, v.x, v.y, v.z])
		skeleton.skeleton_updated.disconnect(sample)
	quit()


func _weapon(name: String) -> WeaponData:
	return null if name == "-" else load("res://data/weapons/%s.tres" % name) as WeaponData


func _sample(skeleton: Skeleton3D, control: MechHandControl) -> void:
	for side in ["R", "L"]:
		var hand: MechHand = control.hand_right if side == "R" else control.hand_left
		if hand == null or not is_instance_valid(hand) or not hand.is_visible_in_tree():
			continue
		var wrist := hand.find_child("Wrist", true, false) as MeshInstance3D
		if wrist == null:
			continue
		var wrist_center := wrist.global_transform * wrist.get_aabb().get_center()
		var pin := WristPin.center(skeleton, side)
		var d := wrist_center.distance_to(pin)
		_worst[side] = maxf(float(_worst.get(side, -1.0)), d)
		_sum[side] = float(_sum.get(side, 0.0)) + d
		_count[side] = int(_count.get(side, 0)) + 1
		var state: Dictionary = control._sides[side]
		if is_instance_valid(state.socket):
			var socket := state.socket as Node3D
			if socket != null:
				var hollow := MechHandControl.RIGHT_HOLLOW if side == "R" else MechHandControl.LEFT_HOLLOW
				hollow.z = MechHandControl.PALM_FACE_Z - float(socket.get_meta(&"grip_radius", control.grip_radius))
				hollow.x += float(socket.get_meta(&"hold_drop", 0.0)) * (-1.0 if side == "R" else 1.0)
				var miss := (hand.global_transform * hollow).distance_to(control._socket_place(side, socket).origin)
				_worst[side + " miss"] = maxf(float(_worst.get(side + " miss", 0.0)), miss)
				_sum[side + " miss"] = float(_sum.get(side + " miss", 0.0)) + miss
				_count[side + " over"] = int(_count.get(side + " over", 0)) + (1 if miss > 0.1 else 0)
				_worst[side + " reach"] = maxf(float(_worst.get(side + " reach", 0.0)), (state.offset as Vector3).length())
		if not _local.has(side):
			var bone_pose := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side))
			_local[side] = bone_pose.affine_inverse() * wrist_center - bone_pose.affine_inverse() * pin
