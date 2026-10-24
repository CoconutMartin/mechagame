extends SceneTree
## Wrist pin probe in the garage (user report 2026-10-24). Opens the garage (the tree pauses), then for each
## loadout in WRIST_LOADOUTS (right/left weapon file names, "-" = empty; ";" between loadouts) changes the
## garage build so the mech is rebuilt and settles while paused, waits GARAGE_WAIT frames, and prints the
## distance between the forearm's wrist pin and the hand's wrist joint (wrist_pin.gd) at the last skeleton update. Headless:
##   godot --headless --path . --script res://tools/godot/measure_wrist_garage.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const WristPin := preload("res://tools/godot/wrist_pin.gd")
const DEFAULT_LOADOUTS := "smg/small_shield;heavy_rifle/-;auto_cannon/-;beam_rifle/-;beam_sniper/-;shotgun/-;baton/-;pile_bunker/-;-/-"

var _worst: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _weapon(name: String) -> WeaponData:
	return null if name == "-" else load("res://data/weapons/%s.tres" % name) as WeaponData


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(60)
	var garage := current_scene.get_node("Garage") as Garage
	garage.open()
	await _frames(10)
	for spec in _env("WRIST_LOADOUTS", DEFAULT_LOADOUTS).split(";", false):
		var names := spec.split("/")
		var edit := Garage._copy(garage.switcher.current_loadout)
		edit.weapon_right = _weapon(names[0])
		edit.weapon_left = _weapon(names[1])
		garage._edit = edit
		garage._rebuild()
		var mech := garage.switcher.mech
		var skeleton := mech.find_child("Skeleton3D", true, false) as Skeleton3D
		var control := mech.find_child("MechHandControl", true, false) as MechHandControl
		_worst = {}
		# The skeleton updates while the new mech settles; the last update is the pose that stays on screen.
		var sample := func() -> void: _sample(skeleton, control)
		skeleton.skeleton_updated.connect(sample)
		await _frames(int(_env("GARAGE_WAIT", "60")))
		skeleton.skeleton_updated.disconnect(sample)
		print("garage %s: R %.3f L %.3f (last update; %d samples)" % [spec, float(_worst.get("R", -1.0)), float(_worst.get("L", -1.0)), int(_worst.get("n", 0))])
	quit()


func _sample(skeleton: Skeleton3D, control: MechHandControl) -> void:
	for side in ["R", "L"]:
		var hand: MechHand = control.hand_right if side == "R" else control.hand_left
		if hand == null or not is_instance_valid(hand) or not hand.is_visible_in_tree():
			continue
		var wrist := hand.find_child("Wrist", true, false) as MeshInstance3D
		var d := (wrist.global_transform * wrist.get_aabb().get_center()).distance_to(WristPin.center(skeleton, side))
		_worst[side] = d
		_worst["n"] = int(_worst.get("n", 0)) + 1
