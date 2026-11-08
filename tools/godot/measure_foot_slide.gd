extends SceneTree
## Foot slide of the player mech in the game (HLY refit, 2026-11-08): walk, boost run, and a stop. Each physics frame it takes the
## lower foot (the foot bone nearer the ground) and, while that foot is planted (within PLANT_HEIGHT of the lowest foot height of the
## run), its speed over the ground. A foot that does not slide has a speed near 0 while the mech moves. Also prints the lowest foot
## height (feet on the ground) and the mech speed. MECH=haliya runs it on Haliya (tools/godot/test_mech_choice.gd). Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_foot_slide.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MechChoice := preload("res://tools/godot/test_mech_choice.gd")
## A foot counts as planted within this height (m) of the lowest foot height seen in the run.
const PLANT_HEIGHT := 0.08
## Frames per state, after SETTLE frames to get up to speed.
const FRAMES := 240
const SETTLE := 60

var _mech: Mech
var _skeleton: Skeleton3D
var _last := {}
var _samples: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	switcher.rebuild(MechChoice.apply(switcher.current_loadout.duplicate() as Loadout), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	_mech = switcher.mech
	_skeleton = _mech.find_child("Skeleton3D", true, false) as Skeleton3D
	print("mech %s (%s)" % [_mech.name, _mech.scene_file_path])
	for state: Array in [["walk", [&"move_forward"]], ["boost run", [&"move_forward", &"boost"]], ["strafe", [&"move_right"]]]:
		for action: StringName in state[1]:
			if InputMap.has_action(action):
				Input.action_press(action)
		await _frames(SETTLE)
		_samples.clear()
		_last.clear()
		for i in FRAMES:
			await physics_frame
			_sample()
		for action: StringName in state[1]:
			if InputMap.has_action(action):
				Input.action_release(action)
		_report(state[0])
		await _frames(90)
	quit()


func _sample() -> void:
	var now := {}
	for bone_name in ["foot_L", "foot_R"]:
		now[bone_name] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name))).origin
	if not _last.is_empty():
		var low: String = "foot_L" if (now.foot_L as Vector3).y < (now.foot_R as Vector3).y else "foot_R"
		var step: Vector3 = now[low] - _last[low]
		var mech_v := _mech.velocity
		_samples.append([(now[low] as Vector3).y - _mech.global_position.y, Vector2(step.x, step.z).length() * Engine.physics_ticks_per_second,
				Vector2(mech_v.x, mech_v.z).length()])
	_last = now


func _report(label: String) -> void:
	var lowest := INF
	for s: Array in _samples:
		lowest = minf(lowest, s[0])
	var slide := []
	var speed := 0.0
	for s: Array in _samples:
		speed += s[2]
		if s[0] <= lowest + PLANT_HEIGHT:
			slide.append(s[1])
	slide.sort()
	var mean := 0.0
	for v: float in slide:
		mean += v
	mean /= maxf(slide.size(), 1)
	var median: float = slide[slide.size() / 2] if slide.size() > 0 else 0.0
	print("%s %-9s mech speed %.2f m/s; planted foot speed mean %.2f, median %.2f m/s (%d of %d frames planted); lowest ankle %.3f m above the mech" % [
			_mech.name_code, label, speed / maxf(_samples.size(), 1), mean, median, slide.size(), _samples.size(), lowest])
