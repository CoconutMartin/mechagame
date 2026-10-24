extends SceneTree
## Arm twitch probe (user reports 2026-10-24: the Beam Rifle and the left fingers twitched in ADS; after the fix the
## right forearm twitches fast in ADS and in charged firing). Builds the Beam Rifle loadout and runs STEPS
## (action+action:frames, ";" between steps; actions are held for the step). Inside skeleton_updated it prints:
##   - every hinge angle step over 1 deg of SkeletalArmRig side.hinge (pitch, elbow turn, bend) ("jump" lines),
##   - FINGERS=1: per gripping MechHand the finger fit target / curl, the hinge angles and the hand place (torso frame),
##   - OFFS=1: the MechHandControl reach offsets and the rifle place (torso frame).
## Example (aim, then 4 charged shots):
##   STEPS="aim:150;aim+use_right_arm:70;aim:50;aim+use_right_arm:70;aim:50" FINGERS=1 \
##     godot --headless --path . --script res://tools/godot/measure_arm_twitch.gd
func _initialize() -> void:
	_run.call_deferred()
func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame
var _last := {}
var _rig: SkeletalArmRig
var _frame := 0
var _hands: Array = []
var _last_fit := {}
func _physics() -> void:
	pass
func _sample() -> void:
	_frame += 1
	if OS.has_environment("OFFS"):
		var ctl := _rig.get_tree().current_scene.find_children("*", "MechHandControl", true, false)[0] as MechHandControl
		var w := _rig.weapons.right_weapon
		print("f%d offR %s offL %s weapon %s" % [_frame, ctl._sides["R"].offset, ctl._sides["L"].offset, _rig.torso.global_transform.affine_inverse() * w.global_position])
	if OS.has_environment("FINGERS"):
		for hand in _hands:
			var h := hand as MechHand
			if h.mode != MechHand.Mode.GRIP:
				continue
			var to_local := h.global_transform.affine_inverse()
			var line := ""
			for name: String in h._joints:
				if name == "Thumb":
					continue
				line += "%s %.2f/%.2f " % [name.substr(0, 2), h._fit(name, to_local * h.grip_center, (to_local.basis * h.grip_axis).normalized()), h._curl[name]]
			var hl: Vector3 = _rig._sides[0 if h.name.ends_with("L") else 1].get("hinge", Vector3.ZERO)
			print("f%d %s %s hinge %.2f %.2f %.2f pos %s" % [_frame, h.name, line, rad_to_deg(hl.x), rad_to_deg(hl.y), rad_to_deg(hl.z), _rig.torso.global_transform.affine_inverse() * h.global_position])
	for i in 2:
		var side: Dictionary = _rig._sides[i]
		if not side.has("hinge"):
			continue
		var h: Vector3 = side.hinge
		var key := "L" if i == 0 else "R"
		if _last.has(key):
			var d: Vector3 = (h - (_last[key] as Vector3))
			if absf(d.x) > 0.017 or absf(d.y) > 0.017 or absf(d.z) > 0.017:
				print("f%d %s jump pitch %.1f turn %.1f bend %.1f -> now (%.1f %.1f %.1f)" % [_frame, key, rad_to_deg(d.x), rad_to_deg(d.y), rad_to_deg(d.z), rad_to_deg(h.x), rad_to_deg(h.y), rad_to_deg(h.z)])
		_last[key] = h
func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/beam_rifle.tres") as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	_rig = switcher.mech.find_children("*", "SkeletalArmRig", true, false)[0] as SkeletalArmRig
	var skeleton := switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton.skeleton_updated.connect(_sample)
	_hands = switcher.mech.find_children("*", "MechHand", true, false)
	print("hands ", _hands.map(func(x): return x.get_path()))
	for step in OS.get_environment("STEPS").split(";"):
		var parts := step.split(":")
		print("== ", parts[0])
		for a in parts[0].split("+", false):
			Input.action_press(a)
		await _frames(int(parts[1]))
		for a in parts[0].split("+", false):
			Input.action_release(a)
	quit()
