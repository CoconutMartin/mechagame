extends SceneTree
## Dodge exit test (user report 2026-10-22: steps after a dodge step slow the mech down). The player
## holds a move key, double taps the jump key, and keeps the key held. The tool logs the horizontal speed
## of every physics frame for 2 s after the double tap, for the four directions, and checks that once
## the dodge hands the mech back (animation off) the speed never drops below the walk speed of that
## direction (less DIP_TOLERANCE). START=walk starts the dodge from a walk, START=stand from a standstill.
## Exits with code 1 on a dip. DODGE_CSV=<file> writes every frame.
## Run: godot --headless --path . --script res://tools/godot/test_dodge_exit.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## Seconds logged after the double tap.
const SECONDS := 2.0
## Allowed dip below the target speed, in m/s.
const DIP_TOLERANCE := 0.15
## [name, move action, side strafe?]
const CASES := [["forward", "move_forward", false], ["left", "move_left", true], ["right", "move_right", true],
		["back", "move_back", false]]

var _failures: int = 0
var _csv: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var starts: Array[String] = ["stand", "walk"]
	if OS.get_environment("START") != "":
		starts = [OS.get_environment("START")]
	for start in starts:
		for entry: Array in CASES:
			switcher.rebuild(switcher.current_loadout.duplicate() as Loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
			await _frames(40)
			await _case(switcher.mech, entry[0], entry[1], entry[2], start)
	if _csv != "" and OS.get_environment("DODGE_CSV") != "":
		var file := FileAccess.open(OS.get_environment("DODGE_CSV"), FileAccess.WRITE)
		file.store_string(_csv)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _case(player: Mech, label: String, action: String, strafe: bool, start: String) -> void:
	var dodge := player.dodge
	var animation := dodge.animation
	var target := player.walk_speed * (player.strafe_speed_multiplier if strafe else 1.0)
	if action == "move_back":
		target = player.walk_speed * player.back_speed_multiplier
	if start == "walk":
		Input.action_press(action)
		await _frames(150)
	else:
		await _frames(30)
		Input.action_press(action)
	# Double tap.
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	await _frames(5)
	Input.action_press("jump")
	var frames := int(SECONDS * 60.0)
	var min_after := 1000.0
	var min_frame := -1
	var released := -1
	var dodge_started := false
	var peak := 0.0
	var line := ""
	for i in frames:
		await _frames(1)
		if i == 2:
			Input.action_release("jump")
		var speed := player.get_horizontal_speed()
		var playing := animation.is_playing
		if dodge.is_dodging:
			dodge_started = true
		if dodge_started and not playing and not dodge.is_dodging and released < 0:
			released = i
		peak = maxf(peak, speed)
		if released >= 0 and i >= released + 1 and speed < min_after:
			min_after = speed
			min_frame = i
		line += "%.1f " % speed
		_csv += "%s,%s,%d,%.3f,%d,%d\n" % [start, label, i, speed, 1 if playing else 0, 1 if dodge.is_busy() else 0]
	Input.action_release(action)
	Input.action_release("jump")
	var ok := dodge_started and released >= 0 and min_after >= target - DIP_TOLERANCE
	print("%s %s: target %.2f, peak %.2f, released at frame %d, min after release %.2f (frame %d) -> %s" % [
			start, label, target, peak, released, min_after, min_frame, "ok" if ok else "FAIL"])
	if OS.get_environment("DODGE_VERBOSE") != "":
		print("  speeds: " + line)
	if not ok:
		_failures += 1
