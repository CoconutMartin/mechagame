extends SceneTree
## Jump clip poses (user report 2026-10-22: two fall animations from the top of a jump). Prints, for each
## clip and time, how far (degrees) the bones in CLIP_BONES are turned from a reference pose: the fall
## clip (Jumping_Down) at its hold time. Shows how far the landing clip's air frames are from the fall pose.
## Run: godot --headless --path . --script res://tools/godot/measure_jump_clips.gd

const BONES := ["pelvis", "torso", "head", "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]


func _initialize() -> void:
	var clips := {
		"jump_up": load("res://data/jump_clips/jump_up.tres") as AirClip,
		"fall_start": load("res://data/jump_clips/fall_start.tres") as AirClip,
		"landing": load("res://data/jump_clips/landing.tres") as AirClip,
	}
	var fall: AirClip = clips.fall_start
	var reference := _pose(fall.animation, fall.get_hold_time())
	for key: String in clips:
		var clip: AirClip = clips[key]
		var length := clip.animation.length
		print("%s: length %.2f s, contact %.2f, hold %.2f" % [key, length, clip.contact_time, clip.get_hold_time()])
		var time := 0.0
		while time <= minf(length, clip.get_hold_time() + 0.01):
			var pose := _pose(clip.animation, time)
			var line := "  t %.2f:" % time
			for bone: String in BONES:
				if pose.has(bone) and reference.has(bone):
					line += " %s %.0f" % [bone, rad_to_deg((pose[bone] as Quaternion).angle_to(reference[bone] as Quaternion))]
			print(line)
			time += 0.05
	quit()


func _pose(animation: Animation, time: float) -> Dictionary:
	var out := {}
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var name := String(animation.track_get_path(track).get_concatenated_subnames())
		out[name] = animation.rotation_track_interpolate(track, time)
	return out
