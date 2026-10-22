extends SceneTree
## Wrist gap probe (user report 2026-10-22: "hands are misaligned with the wrist joints"). For each loadout in
## WRIST_LOADOUTS (right/left weapon file names, "-" = empty; ";" between loadouts) the player runs the
## WRIST_STEPS (name:actions:frames, actions joined by "+", ";" between steps). Every frame, during
## skeleton_updated (the pose with the modifiers), it measures per hand:
##   bone: the hand bone origin to the forearm bone's end (the arm itself comes apart),
##   node: the jointed hand's wrist to the hand bone origin (MechHandControl moved the hand off the wrist).
## Prints the largest of each per step. Headless:
##   godot --headless --path . --script res://tools/godot/measure_wrist_gap.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const DEFAULT_LOADOUTS := "smg/small_shield;heavy_rifle/small_shield;shotgun/-;-/-;beam_sniper/-"
const DEFAULT_STEPS := "stand::60;walk:move_forward:120;guard:move_forward+use_left_arm:90;aim:aim:60;fire:use_right_arm:60;boost:move_forward+boost:120;stop::90"

var _worst: Dictionary = {}


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
		var sample := func() -> void: _sample(skeleton, control)
		skeleton.skeleton_updated.connect(sample)
		for step in _env("WRIST_STEPS", DEFAULT_STEPS).split(";", false):
			var parts := step.split(":")
			var actions := parts[1].split("+", false)
			_worst = {}
			for action in actions:
				Input.action_press(action)
			await _frames(int(parts[2]))
			for action in actions:
				Input.action_release(action)
			var text := "%s %s:" % [spec, parts[0]]
			for key in ["R bone", "R node", "L bone", "L node"]:
				text += " %s %.3f" % [key, float(_worst.get(key, 0.0))]
			print(text)
		skeleton.skeleton_updated.disconnect(sample)
	quit()


func _weapon(name: String) -> WeaponData:
	return null if name == "-" else load("res://data/weapons/%s.tres" % name) as WeaponData


func _sample(skeleton: Skeleton3D, control: MechHandControl) -> void:
	for side in ["R", "L"]:
		var forearm := skeleton.find_bone("forearm_" + side)
		var hand_bone := skeleton.find_bone("hand_" + side)
		var hand_pose := skeleton.global_transform * skeleton.get_bone_global_pose(hand_bone)
		# The forearm's end: the hand bone's rest offset from the forearm.
		var end := skeleton.global_transform * skeleton.get_bone_global_pose(forearm) * skeleton.get_bone_rest(hand_bone).origin
		_keep("%s bone" % side, end.distance_to(hand_pose.origin))
		var hand: MechHand = control.hand_right if side == "R" else control.hand_left
		if hand != null and is_instance_valid(hand) and hand.is_visible_in_tree():
			_keep("%s node" % side, hand.global_position.distance_to(hand_pose.origin))


func _keep(key: String, value: float) -> void:
	_worst[key] = maxf(float(_worst.get(key, 0.0)), value)
