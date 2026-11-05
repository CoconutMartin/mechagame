extends SceneTree
## Lowest foot height above the mech's ground point while standing and walking, for SGG and Haliya (the feet should reach about the same height).
## Headless: godot --headless --path . --script res://tools/godot/measure_foot_ground.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _low := INF
var _high := -INF
var _skeleton: Skeleton3D
var _mech: Mech


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _measure() -> void:
	var lowest := INF
	for bone_name: StringName in [&"foot_L", &"foot_R"]:
		var pose := _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name))
		lowest = minf(lowest, pose.origin.y - _mech.global_position.y)
	_low = minf(_low, lowest)
	_high = maxf(_high, lowest)


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for key in switcher.loadouts.size():
		switcher.switch_to(switcher.loadouts[key])
		await _frames(50)
		_mech = switcher.mech
		_skeleton = (_mech.get_node("SkeletalHitboxes") as SkeletalHitboxes).skeleton
		_skeleton.skeleton_updated.connect(_measure)
		for state in [[], [&"move_forward"]]:
			_low = INF
			_high = -INF
			for action: StringName in state:
				Input.action_press(action)
			await _frames(30)
			_low = INF
			_high = -INF
			await _frames(120)
			for action: StringName in state:
				Input.action_release(action)
			print("%s %s: lower ankle %.3f to %.3f m above the mech origin; mech y %.3f on floor %s" % [_mech.name_code, "walk" if state.size() > 0 else "stand", _low, _high, _mech.global_position.y, _mech.is_on_floor()])
			await _frames(30)
		_skeleton.skeleton_updated.disconnect(_measure)
	quit()
