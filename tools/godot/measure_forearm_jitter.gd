extends SceneTree
## Forearm jitter probe (user report 2026-10-30: "right forearm moves erratically while walking/running - twisting,
## twitching, turning" with the Pile Bunker). Holds WEAPON (default pile_bunker) in the right hand, walks (W) then
## runs (W + boost) and reads the forearm bones in the skeleton update (with the arm modifiers) every frame: the
## turn of the forearm axis and its twist about the axis from the frame before (degrees), for both arms. Prints the
## largest values, the count of frames with a turn or twist step over SPIKE degrees, and the sign changes of the twist
## step (a back and forth twitch). TRACE=1 prints every frame. Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_forearm_jitter.gd

const SPIKE := 4.0

var _last := {}
var _stats := {}


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var weapon := OS.get_environment("WEAPON") if OS.has_environment("WEAPON") else "pile_bunker"
	loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon) if weapon != "-" else null
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var skeleton := switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D
	var phase := ["walk"]
	var on_update := func() -> void:
		for side in ["R", "L"]:
			var pose := skeleton.get_bone_global_pose(skeleton.find_bone("forearm_" + side)).basis.orthonormalized()
			var key: String = phase[0] + side
			if _last.has(side):
				var before: Basis = _last[side]
				var turn := rad_to_deg(before.y.angle_to(pose.y))
				# Twist: the turn of the x axis about the forearm axis, after lining the axes up.
				var lined := Basis(Quaternion(before.y, pose.y)) * before
				var twist := rad_to_deg(lined.x.signed_angle_to(pose.x, pose.y))
				var s: Dictionary = _stats.get(key, {"turn": 0.0, "twist": 0.0, "spikes": 0, "flips": 0, "last": 0.0, "n": 0})
				s.turn = maxf(s.turn, turn)
				s.twist = maxf(s.twist, absf(twist))
				if turn > SPIKE or absf(twist) > SPIKE:
					s.spikes += 1
				if absf(twist) > 0.5 and absf(s.last) > 0.5 and signf(twist) != signf(s.last):
					s.flips += 1
				s.last = twist
				s.n += 1
				_stats[key] = s
				if OS.has_environment("TRACE") and side == "R":
					print("%s turn %.2f twist %.2f" % [key, turn, twist])
			_last[side] = pose
	skeleton.skeleton_updated.connect(on_update)
	Input.action_press("move_forward")
	await _frames(180)
	phase[0] = "run"
	Input.action_press("boost")
	await _frames(180)
	Input.action_release("boost")
	Input.action_release("move_forward")
	skeleton.skeleton_updated.disconnect(on_update)
	for key: String in _stats:
		var s: Dictionary = _stats[key]
		print("%s %s: largest turn %.2f deg/frame, twist %.2f deg/frame, spikes over %.0f: %d of %d, twist reversals %d" % [weapon, key,
				s.turn, s.twist, SPIKE, s.spikes, s.n, s.flips])
	quit()
