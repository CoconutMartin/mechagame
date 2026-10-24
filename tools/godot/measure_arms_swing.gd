extends SceneTree
## Arm swing numbers while moving (user request 2026-10-24: "arms currently dead hang"). For each loadout in
## SWING_LOADOUTS (right/left weapon file names, "-" = empty; ";" between loadouts) the player holds
## move_forward for SWING_WALK frames (walk), then also boost until it runs (run) and until it boosts (boost),
## SWING_HOLD frames in each. Every frame, during skeleton_updated, it records per arm (body frame of
## measure_arms_probe.gd) the upper arm's swing (forward + / back -, degrees in the side plane), its raise to
## the side, the elbow bend (degrees between the upper arm and the forearm; 0 = straight) and the palm's nearest
## distance to the leg bone lines. For each mode it prints per arm: the swing's mean and range (largest - smallest),
## the elbow bend's mean and range, the largest angular acceleration of the swing and of the bend (deg/s2,
## second difference of the frames) and the nearest leg distance. SWING_CSV=<path> also saves every frame.
## Headless:  SWING_LOADOUTS="-/-" godot --headless --path . --script res://tools/godot/measure_arms_swing.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const Probe := preload("res://tools/godot/measure_arms_probe.gd")
const MODES := ["walk", "run", "boost"]

## mode -> side -> {swing: [], bend: [], raise: [], leg: float}
var _data: Dictionary = {}
var _mode: String = ""
## Frames since the mode flags changed (steady frames only count).
var _since: int = 0
var _last_flags: String = ""
var _count: Dictionary = {}
## mode -> mesh name -> deepest gun point inside its box (m) over the run.
var _clip_worst: Dictionary = {}
var _clip_who: Dictionary = {}
var _floor_frames: Dictionary = {}
var _phase_travel: Dictionary = {}
var _last_phase: float = 0.0
var _csv: PackedStringArray = []
var _frame: int = 0


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
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	for spec in _env("SWING_LOADOUTS", "-/-").split(";", false):
		var names := spec.split("/")
		var loadout := switcher.current_loadout.duplicate() as Loadout
		loadout.weapon_right = _weapon(names[0])
		loadout.weapon_left = _weapon(names[1])
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(40)
		_data = {}
		_floor_frames = {}
		_count = {}
		_phase_travel = {}
		_last_flags = ""
		var player := switcher.mech
		var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
		var weapons := player.get_node("WeaponController") as WeaponController
		var probe := Probe.new()
		probe.with_clip = _env("SWING_CLIP", "1") == "1"
		_clip_worst = {}
		var hook := _hook(probe, player, skeleton, weapons)
		skeleton.skeleton_updated.connect(hook)
		Input.action_press("move_forward")
		await _frames(int(_env("SWING_WALK", "150")))
		_mode = "auto"
		# Walk, then hold boost: run starts after some walk steps and boost after some run steps.
		await _frames(int(_env("SWING_HOLD", "120")))
		Input.action_press("boost")
		var waited := 0
		while not player.is_boosting and waited < 1200:
			await _frames(1)
			waited += 1
		await _frames(int(_env("SWING_HOLD", "120")) + 60)
		_mode = ""
		Input.action_release("boost")
		Input.action_release("move_forward")
		skeleton.skeleton_updated.disconnect(hook)
		print("== %s (speed at the end %.1f m/s, walk speed %.1f)" % [spec, player.get_horizontal_speed(), player.walk_speed])
		_report()
		await _frames(120)
	var path := _env("SWING_CSV", "")
	if path != "":
		FileAccess.open(path, FileAccess.WRITE).store_string("\n".join(_csv))
	quit()


func _hook(probe: RefCounted, player: Mech, skeleton: Skeleton3D, weapons: WeaponController) -> Callable:
	return func() -> void:
		_frame += 1
		if _mode == "":
			return
		var flags := "boost" if player.is_boosting else ("run" if player.is_running else "walk")
		if flags != _last_flags:
			_last_flags = flags
			_since = 0
		_since += 1
		var locomotion := player.find_children("*", "SkeletalLocomotion", true, false)[0] as SkeletalLocomotion
		_phase_travel[flags] = float(_phase_travel.get(flags, 0.0)) + absf(fposmod(locomotion.get_phase() - _last_phase + 0.5, 1.0) - 0.5)
		_last_phase = locomotion.get_phase()
		_count[flags] = int(_count.get(flags, 0)) + 1
		if player.is_on_floor():
			_floor_frames[flags] = int(_floor_frames.get(flags, 0)) + 1
		if _since < 30 or player.get_horizontal_speed() < 2.0:
			return
		var snap: Dictionary = probe.snapshot(player, skeleton, weapons)
		var legs := _legs(skeleton, snap.body)
		for side: String in Probe.SIDES:
			var arm: Dictionary = snap[side]
			var upper: Vector3 = arm.el - arm.sh
			var fore: Vector3 = arm.wr - arm.el
			var sign := 1.0 if side == "R" else -1.0
			var swing := rad_to_deg(atan2(-upper.z, -upper.y))
			var raise := rad_to_deg(asin(clampf(upper.x * sign / upper.length(), -1.0, 1.0)))
			var bend := rad_to_deg(upper.angle_to(fore))
			var palm: Vector3 = (snap.body as Transform3D) * (arm.wr as Vector3)
			if arm.has("clip"):
				for mesh_name: String in arm.clip:
					var key := "%s %s" % [flags, mesh_name]
					if float(arm.clip[mesh_name][0]) > float(_clip_worst.get(key, 0.0)):
						_clip_worst[key] = float(arm.clip[mesh_name][0])
						_clip_who[key] = "%s at phase %.2f" % [arm.clip[mesh_name][2], _locomotion_phase(player)]
			var entry: Dictionary = _entry(flags, side)
			(entry.swing as Array).append(swing)
			(entry.bend as Array).append(bend)
			(entry.raise as Array).append(raise)
			entry.leg = minf(entry.leg, _leg_distance(palm, legs))
			_csv.append("%d,%s,%s,%.3f,%.3f,%.3f,%.3f" % [_frame, flags, side, swing, bend, raise, player.get_horizontal_speed()])


func _locomotion_phase(player: Mech) -> float:
	return (player.find_children("*", "SkeletalLocomotion", true, false)[0] as SkeletalLocomotion).get_phase()


func _entry(mode: String, side: String) -> Dictionary:
	if not _data.has(mode):
		_data[mode] = {}
	if not (_data[mode] as Dictionary).has(side):
		_data[mode][side] = {"swing": [], "bend": [], "raise": [], "leg": INF}
	return _data[mode][side]


func _legs(skeleton: Skeleton3D, body: Transform3D) -> Array:
	var segments: Array = []
	for names in [["thigh_L", "shin_L", "foot_L"], ["thigh_R", "shin_R", "foot_R"]]:
		var points: Array[Vector3] = []
		for n: String in names:
			points.append(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(n)).origin)
		segments.append([points[0], points[1]])
		segments.append([points[1], points[2]])
	return segments


func _leg_distance(point: Vector3, legs: Array) -> float:
	var nearest := INF
	for segment: Array in legs:
		nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, segment[0], segment[1])))
	return nearest


func _report() -> void:
	for key: String in _clip_worst:
		if float(_clip_worst[key]) > 0.02:
			print("  gun inside body box (%s): %.2f m, %s" % [key, _clip_worst[key], _clip_who.get(key, "")])
	for mode: String in MODES:
		if not _data.has(mode):
			continue
		print("  %s: %d frames, on the floor in %d frames, stride phase travelled %.2f strides" % [mode, int(_count.get(mode, 0)), int(_floor_frames.get(mode, 0)), float(_phase_travel.get(mode, 0.0))])
		for side: String in Probe.SIDES:
			var e: Dictionary = _data[mode][side]
			var swing: Array = e.swing
			var bend: Array = e.bend
			var raise: Array = e.raise
			print("  %-5s %s: frames %d | swing mean %+.1f range %.1f deg, peak accel %.0f deg/s2 | elbow bend mean %.1f range %.1f, peak accel %.0f | raise mean %.1f range %.1f | palm to legs min %.2f m" % [
					mode, side, swing.size(), _mean(swing), _range(swing), _accel(swing), _mean(bend), _range(bend), _accel(bend),
					_mean(raise), _range(raise), e.leg])


static func _mean(values: Array) -> float:
	var sum := 0.0
	for v: float in values:
		sum += v
	return sum / maxf(float(values.size()), 1.0)


static func _range(values: Array) -> float:
	var low := INF
	var high := -INF
	for v: float in values:
		low = minf(low, v)
		high = maxf(high, v)
	return high - low


## Largest second difference of the values in degrees per second squared (60 frames per second).
static func _accel(values: Array) -> float:
	var worst := 0.0
	for i in range(1, values.size() - 1):
		worst = maxf(worst, absf(float(values[i + 1]) - 2.0 * float(values[i]) + float(values[i - 1])) * 3600.0)
	return worst
