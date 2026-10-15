extends SceneTree
## Makes one full hammer swing from the retargeted Mixamo hammer combo (user request 2026-10-15: the
## directional hammer swings looked incomplete, they were halves of the 2-swing combo cut at 1.9 s).
##
## How: the part from <start> to <end> seconds of the source clip is copied at 30 fps (wind-up, swing
## through, follow-through), then a recovery of <recovery> seconds is keyframed: each bone eases from its
## pose at <end> back to its pose at <start> (the ready pose; rotations by slerp over the shortest way,
## positions by lerp, smoothstep ease), so the body ends where it began and the clip blends out cleanly.
## The travel curve is cut the same way (zero at <start>, held through the recovery). The source swings
## from the right to the left (mirror it with mirror_clip.gd for the other side).
##
## Run: godot --headless --path . --script res://tools/godot/make_hammer_swing.gd -- <in anim .res> <in travel .tres> <out anim .res> <out travel .tres> <start> <end> <recovery>
## Example: ... -- res://data/animations/melee_hammer_combo.res res://data/animations/melee_hammer_combo_travel.tres \
##   res://data/animations/melee_hammer_swing.res res://data/animations/melee_hammer_swing_travel.tres 0.3 2.4 0.7

const FPS := 30.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source := load(args[0]) as Animation
	var travel := load(args[1]) as Curve
	var start := float(args[4])
	var end := minf(float(args[5]), source.length)
	var recovery := float(args[6])
	var swing_length := end - start
	var out := Animation.new()
	out.length = swing_length + recovery
	out.step = 1.0 / FPS
	var swing_frames := int(ceil(swing_length * FPS))
	var recovery_frames := int(ceil(recovery * FPS))
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		var new_track := out.add_track(type)
		out.track_set_path(new_track, source.track_get_path(track))
		var ready: Variant = _sample(source, track, type, start)
		var last: Variant = _sample(source, track, type, end)
		for frame in swing_frames + 1:
			var time := minf(frame / FPS, swing_length)
			_insert(out, new_track, type, time, _sample(source, track, type, start + time))
		for frame in range(1, recovery_frames + 1):
			var k := minf(frame / FPS, recovery) / recovery
			var ease := smoothstep(0.0, 1.0, k)
			var value: Variant
			if type == Animation.TYPE_ROTATION_3D:
				value = (last as Quaternion).slerp(ready as Quaternion, ease)
			else:
				value = (last as Vector3).lerp(ready as Vector3, ease)
			_insert(out, new_track, type, minf(swing_length + frame / FPS, out.length), value)

	var curve := Curve.new()
	curve.min_value = -0.5
	curve.max_value = 1.5
	var base := travel.sample(start / source.length)
	var total_frames := int(ceil(out.length * FPS))
	for frame in total_frames + 1:
		var time := minf(frame / FPS, out.length)
		var along := travel.sample(minf(start + minf(time, swing_length), source.length) / source.length) - base
		curve.add_point(Vector2(time / out.length, along), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.set_meta(&"travel_m", travel.get_meta(&"travel_m"))
	curve.set_meta(&"travel_direction", travel.get_meta(&"travel_direction"))
	print("length %.2f s (swing %.2f + recovery %.2f), travel %.1f m" % [out.length, swing_length, recovery, curve.sample(1.0) * float(travel.get_meta(&"travel_m"))])
	print("save anim ", ResourceSaver.save(out, args[2]), " curve ", ResourceSaver.save(curve, args[3]))
	quit()


func _sample(animation: Animation, track: int, type: int, time: float) -> Variant:
	if type == Animation.TYPE_ROTATION_3D:
		return animation.rotation_track_interpolate(track, time)
	return animation.position_track_interpolate(track, time)


func _insert(animation: Animation, track: int, type: int, time: float, value: Variant) -> void:
	if type == Animation.TYPE_ROTATION_3D:
		animation.rotation_track_insert_key(track, time, value)
	else:
		animation.position_track_insert_key(track, time, value)
