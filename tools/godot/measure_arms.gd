extends SceneTree
## Arm pose numbers (user requests 2026-10-24: one-hand guns along the forearm, Beam Sniper right elbow
## out, level shoulders with one weapon). For each loadout in ARMS_LOADOUTS (right/left weapon file names,
## "-" = empty; ";" between loadouts) the player runs the ARMS_STEPS (name:actions:frames, actions joined
## by "+", ";" between steps) and the tool prints, from the last frame of each step, the body-frame
## places and block numbers of both arms (measure_arms_probe.gd). The step named "guard" holds jump 60
## frames, releases, and reports the frame with the largest jump guard. The step "fire" holds both fire
## keys: a one-hand gun is raised then (the aim pose); the shot kick is off unless ARMS_RECOIL=1. Headless:
##   ARMS_LOADOUTS="heavy_rifle/-;-/-" godot --headless --path . --script res://tools/godot/measure_arms.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const Probe := preload("res://tools/godot/measure_arms_probe.gd")
const DEFAULT_LOADOUTS := "heavy_rifle/-;-/heavy_rifle;smg/-;-/smg;shotgun/-;-/shotgun;smg/smg;beam_sniper/-;-/-"
const DEFAULT_STEPS := "rest::90;fire:use_right_arm+use_left_arm:90;guard:jump:0"

var _last: Dictionary = {}
var _best: Dictionary = {}
var _best_guard: float = -1.0
var _jump_pose: Node


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
	for spec in _env("ARMS_LOADOUTS", DEFAULT_LOADOUTS).split(";", false):
		var names := spec.split("/")
		var loadout := switcher.current_loadout.duplicate() as Loadout
		loadout.weapon_right = _weapon(names[0])
		loadout.weapon_left = _weapon(names[1])
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(40)
		var player := switcher.mech
		var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
		var weapons := player.get_node("WeaponController") as WeaponController
		var probe := Probe.new()
		probe.with_clip = _env("ARMS_CLIP", "1") == "1"
		# The shot kick moves the gun in the raised pose: off, so the numbers stay still.
		if _env("ARMS_RECOIL", "0") != "1":
			for pose in player.find_children("*", "WeaponPose", true, false):
				(pose as WeaponPose).recoil = null
		_jump_pose = player.find_children("*", "SkeletalJumpPose", true, false)[0]
		var sample := func() -> void:
			_last = probe.snapshot(player, skeleton, weapons)
			var guard: float = _jump_pose.guard
			if guard > _best_guard:
				_best_guard = guard
				_best = _last
		skeleton.skeleton_updated.connect(sample)
		for step in _env("ARMS_STEPS", DEFAULT_STEPS).split(";", false):
			var parts := step.split(":")
			var actions := parts[1].split("+", false)
			_best_guard = -1.0
			for action in actions:
				Input.action_press(action)
			if parts[0] == "guard":
				await _frames(60)
				Input.action_release("jump")
				await _frames(150)
			else:
				await _frames(int(parts[2]))
			for action in actions:
				Input.action_release(action)
			print("== %s  %s" % [spec, parts[0]])
			var shown := _best if parts[0] == "guard" else _last
			if parts[0] == "guard":
				print("   (guard %.2f)" % _best_guard)
			for side: String in Probe.SIDES:
				print("   " + Probe.describe(side, shown[side]))
			await _frames(120)
		skeleton.skeleton_updated.disconnect(sample)
	quit()


func _weapon(name: String) -> WeaponData:
	return null if name == "-" else load("res://data/weapons/%s.tres" % name) as WeaponData
