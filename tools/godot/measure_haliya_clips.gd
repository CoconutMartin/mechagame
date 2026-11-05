extends SceneTree
## Prints bone places of the baked Haliya clips, in Blender space, to compare with models/haliya/haliya.blend (DESIGN "Three rigs").
## Headless: godot --headless --path . --script res://tools/godot/measure_haliya_clips.gd

const RIG := "res://models/mechs/haliya/haliya_rig.glb"
const BONES: Array[String] = ["pelvis", "head", "hand_L", "foot_L", "foot_R", "skirt_side_L", "forearm_L"]
const SAMPLES := {"Walk": [1, 16, 31, 46], "Jog": [1, 16], "biped_run_full": [0, 15], "Idle": [1, 61]}
const FPS := 24.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rig := (load(RIG) as PackedScene).instantiate()
	root.add_child(rig)
	var player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	print("clips ", player.get_animation_list())
	for clip: String in SAMPLES:
		var first := 0.0 if clip == "biped_run_full" else 1.0
		for frame: float in SAMPLES[clip]:
			player.play(clip)
			player.seek((frame - first) / FPS, true)
			player.pause()
			await process_frame
			await process_frame
			var text := "%s %d" % [clip, frame]
			for bone in BONES:
				var p := skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
				text += " %s (%.3f %.3f %.3f)" % [bone, p.x, -p.z, p.y]
			print(text)
	quit()
