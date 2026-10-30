extends SceneTree
## Headless test of the FreeAim crosshair kick (play test fixes 2026-10-24, round 2): with no box the kick
## stays on the crosshair (no automatic return), a mouse move against it brings it back before the camera
## turns, and a long burst stops at max_kick_offset_deg (the rest turns the camera).
## Run: godot --headless --path . --script res://tools/godot/test_crosshair_kick.gd

var _failures: int = 0


func _initialize() -> void:
	var aim := FreeAim.new()
	root.add_child(aim)
	var dt := 1.0 / 60.0
	aim.kick(2.0, 0.0)
	for i in 120:
		aim._physics_process(dt)
	var camera := aim.take_camera_kick()
	print("after 2 s: crosshair %.3f deg up, camera %.3f deg" % [aim.aim_offset.y, camera.y])
	_check(absf(aim.aim_offset.y - 2.0) < 0.01, "kick stays on the crosshair (2 deg up)")
	_check(camera.length() < 0.001, "no automatic camera return")
	var turn := aim.take_motion(Vector2(0.5, -1.5))
	aim._physics_process(dt)
	print("mouse down 1.5, left 0.5: turn (%.3f, %.3f), crosshair %.3f" % [turn.x, turn.y, aim.aim_offset.y])
	_check(absf(turn.y) < 0.001 and absf(turn.x - 0.5) < 0.001, "pull against the kick does not turn the camera")
	_check(aim.aim_offset.y > 1.5, "the crosshair glides back, no snap (one frame after the pull: %.3f deg)" % aim.aim_offset.y)
	for i in 60:
		aim._physics_process(dt)
	_check(absf(aim.aim_offset.y - 0.5) < 0.01, "crosshair back by the pull (0.5 deg of kick remain, %.3f after 1 s)" % aim.aim_offset.y)
	turn = aim.take_motion(Vector2(0.0, -1.0))
	_check(absf(turn.y + 0.5) < 0.001, "the move past the center turns the camera")
	aim.kick(20.0, 0.0)
	for i in 120:
		aim._physics_process(dt)
	camera = aim.take_camera_kick()
	print("20 deg kick: crosshair %.3f, camera %.3f" % [aim.aim_offset.y, camera.y])
	_check(absf(aim.aim_offset.y - aim.max_kick_offset_deg) < 0.01, "crosshair stops at the kick limit")
	_check(absf(camera.y - (20.0 - aim.max_kick_offset_deg)) < 0.05, "the rest of the kick turns the camera")
	print("CROSSHAIR KICK: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	aim.free()
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print(("PASS " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1
