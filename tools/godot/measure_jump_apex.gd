extends SceneTree
## Jump apex measure (user report 2026-10-22: rough change from the top of a jump into the fall). Holds
## jump for APEX_CHARGE seconds (default 3, a full jump), releases, and logs per frame, inside
## Skeleton3D.skeleton_updated (the pose with every modifier), the biggest bone turn since the last frame
## (degrees, global poses of all bones) and the jump clip layer weights. A pop shows as a spike near the
## apex, well above the changes inside the clips. Prints a summary: the worst change in the 0.6 s around
## the apex and the worst change in the rise.
## Run: godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_jump_apex.gd
## APEX_VERBOSE=1 prints every frame.

const MAP := "res://maps/urban_small/urban_small.tscn"

var _skeleton: Skeleton3D
var _previous: Array[Basis] = []
var _worst: float = 0.0
var _worst_bone: String = ""
## APEX_BONE: also log this bone's turn per frame and its child's place (model space).
var _watch: int = -1
var _watch_turn: float = 0.0
var _watch_tip: Vector3 = Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _on_updated() -> void:
	var count := _skeleton.get_bone_count()
	for bone in count:
		var basis := _skeleton.get_bone_global_pose(bone).basis.orthonormalized()
		if _previous.size() == count:
			var angle := rad_to_deg(_previous[bone].get_rotation_quaternion().angle_to(basis.get_rotation_quaternion()))
			if angle > _worst:
				_worst = angle
				_worst_bone = _skeleton.get_bone_name(bone)
			if bone == _watch:
				_watch_turn = angle
			_previous[bone] = basis
		else:
			_previous.append(basis)


func _run() -> void:
	var charge := float(OS.get_environment("APEX_CHARGE")) if OS.get_environment("APEX_CHARGE") != "" else 3.0
	var verbose := OS.get_environment("APEX_VERBOSE") == "1"
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	switcher.rebuild(switcher.current_loadout.duplicate() as Loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	_skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_on_updated)
	if OS.get_environment("APEX_BONE") != "":
		_watch = _skeleton.find_bone(OS.get_environment("APEX_BONE"))
	var pose := _skeleton.find_children("*", "SkeletalJumpPose", false, false)[0] as SkeletalJumpPose
	Input.action_press("jump")
	await _frames(int(charge * 60.0))
	Input.action_release("jump")
	var rows: Array = []
	var apex := -1
	var landed := -1
	var was_up := false
	for frame in 360:
		_worst = 0.0
		_worst_bone = ""
		await _frames(1)
		var w: Array[float] = pose.director.weights
		var vy := player.velocity.y
		if vy > 0.5:
			was_up = true
		if was_up and apex < 0 and vy <= 0.0:
			apex = frame
		if apex >= 0 and landed < 0 and player.is_on_floor():
			landed = frame
		rows.append([frame, _worst, _worst_bone, w[0], w[1], w[2], vy, pose.director.times[1]])
		if _watch >= 0:
			var child := _skeleton.get_bone_children(_watch)
			var tip := _skeleton.get_bone_global_pose(child[0]).origin if child.size() > 0 else Vector3.ZERO
			print("%3d %s turn %5.2f  tip %s  moved %.3f" % [frame, _skeleton.get_bone_name(_watch), _watch_turn, tip, tip.distance_to(_watch_tip)])
			_watch_tip = tip
		if verbose:
			print("%3d vy %6.2f  w %.2f %.2f %.2f  t1 %.2f  guard %.2f  max %5.2f deg (%s)%s" % [frame, vy, w[0], w[1], w[2],
					pose.director.times[1], pose.guard, _worst, _worst_bone, "  <- apex" if frame == apex else ""])
		if landed >= 0 and frame > landed + 5:
			break
	var near := 0.0
	var near_bone := ""
	var near_frame := -1
	var rise := 0.0
	for row in rows:
		var f: int = row[0]
		if apex >= 0 and f >= apex - 6 and f <= apex + 30 and float(row[1]) > near:
			near = row[1]
			near_bone = row[2]
			near_frame = f
		if f > 15 and (apex < 0 or f < apex - 12) and float(row[1]) > rise:
			rise = row[1]
	print("APEX charge %.1f: apex frame %d, landed frame %d; worst near apex %.2f deg (%s, frame %d); worst in the rise %.2f deg" % [
			charge, apex, landed, near, near_bone, near_frame, rise])
	Input.action_release("jump")
	quit()
