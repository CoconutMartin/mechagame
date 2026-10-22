extends SceneTree
## Walk test (user reports 2026-10-16: the feet "double bounce" each step; 2026-10-22: the foot kicks
## the ground twice, the walk looks like a rooster). The player walks forward for WALK_TIME seconds
## (default 4). Each frame, inside Skeleton3D.skeleton_updated (the only place where the bone poses
## have every modifier applied), it measures both feet and the body, and prints one line:
##   frame speed phase | per foot: sole height, ankle height, forward speed on the ground | pelvis
##   height, pelvis and head forward offset from the mech origin, head height.
## The sole height is the lowest of the heel and the toe (the foot shape of SkeletalAnklePitch).
## Forward speed is the foot's world speed along the mech front: a planted foot reads about 0, a
## swinging foot reads more than the body speed. Pitch is the foot's toes-up angle in degrees.
## WALK_CSV: file that gets the same table as comma separated values. With a window it saves a side
## picture every WALK_STEP frames (default 0 = none). WALK_OFF turns skeleton modifiers off,
## WALK_SPEED sets the walk speed, WALK_CAM_H and WALK_CAM_D the picture's aim height and distance.
## WALK_FROM skips the first frames in the pictures (default 0). WALK_LEGACY is the path of an older
## SkeletalAnklePitch script (no class_name) that replaces the current one, to measure before and after.
## Run: WALK_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_walk.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## Foot shape (m from the foot bone): sole below it, heel behind it, toe in front of it.
const SOLE_DEPTH := 1.05
const HEEL_LENGTH := 0.91
const TOE_LENGTH := 1.73

var _skeleton: Skeleton3D
var _player: Mech
var _bones: Array[int] = []
var _bone_pelvis: int
var _bone_head: int
## Latest measurement (filled in skeleton_updated).
var _sole: Array[float] = [0.0, 0.0]
var _ankle: Array[float] = [0.0, 0.0]
var _foot_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _pelvis_y: float = 0.0
var _pelvis_fwd: float = 0.0
var _head_y: float = 0.0
var _head_fwd: float = 0.0
var _pitch: Array[float] = [0.0, 0.0]


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _on_skeleton_updated() -> void:
	var ground := _player.global_position.y
	var forward := -_player.global_basis.z
	var to_world := _skeleton.global_transform
	for side in 2:
		var pose := to_world * _skeleton.get_bone_global_pose(_bones[side])
		var heel := pose * Vector3(0.0, -HEEL_LENGTH, -SOLE_DEPTH)
		var toe := pose * Vector3(0.0, TOE_LENGTH, -SOLE_DEPTH)
		_sole[side] = minf(heel.y, toe.y) - ground
		_ankle[side] = pose.origin.y - ground
		_foot_pos[side] = pose.origin
		_pitch[side] = rad_to_deg(asin(clampf(pose.basis.y.y, -1.0, 1.0)))
	var pelvis := to_world * _skeleton.get_bone_global_pose(_bone_pelvis)
	var head := to_world * _skeleton.get_bone_global_pose(_bone_head)
	_pelvis_y = pelvis.origin.y - ground
	_pelvis_fwd = (pelvis.origin - _player.global_position).dot(forward)
	_head_y = head.origin.y - ground
	_head_fwd = (head.origin - _player.global_position).dot(forward)


func _run() -> void:
	var out := OS.get_environment("WALK_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://walk_renders")
	DirAccess.make_dir_recursive_absolute(out)
	var seconds := float(OS.get_environment("WALK_TIME")) if OS.get_environment("WALK_TIME") != "" else 4.0
	var step := int(OS.get_environment("WALK_STEP")) if OS.get_environment("WALK_STEP") != "" else 0
	var from := int(OS.get_environment("WALK_FROM")) if OS.get_environment("WALK_FROM") != "" else 0
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	switcher.rebuild(switcher.current_loadout.duplicate() as Loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	_player = switcher.mech
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	# WALK_OFF: skeleton modifier names to turn off (comma list, "all" = every one), to find which one
	# changes the feet.
	var off := OS.get_environment("WALK_OFF")
	for modifier in _skeleton.find_children("*", "SkeletonModifier3D", false, false):
		if off == "all" or modifier.name in off.split(","):
			(modifier as SkeletonModifier3D).active = false
			print("off: %s" % modifier.name)
	# WALK_SPEED: walk speed in m/s (default: the mech's own).
	if OS.get_environment("WALK_SPEED") != "":
		_player.walk_speed = float(OS.get_environment("WALK_SPEED"))
	# WALK_LEGACY: path of an older SkeletalAnklePitch script (without class_name) to put in place of the
	# current one, to compare before and after.
	if OS.get_environment("WALK_LEGACY") != "":
		var found := _skeleton.find_children("*", "SkeletalAnklePitch", false, false)
		if not found.is_empty():
			found[0].set_script(load(OS.get_environment("WALK_LEGACY")))
			found[0].set("mech", _player)
			print("legacy ankle pitch script in place")
	_bones = [_skeleton.find_bone("foot_L"), _skeleton.find_bone("foot_R")]
	_bone_pelvis = _skeleton.find_bone("pelvis")
	_bone_head = _skeleton.find_bone("head")
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	var locomotion := _player.find_child("Locomotion", true, false) as SkeletalLocomotion
	var frame := [0]
	if locomotion != null:
		locomotion.footstep.connect(func(strength: float) -> void: print("  footstep frame %d strength %.2f" % [frame[0], strength]))
	var camera := Camera3D.new()
	camera.fov = 35.0
	map.add_child(camera)
	if step > 0:
		camera.current = true
	var csv: FileAccess = null
	if OS.get_environment("WALK_CSV") != "":
		csv = FileAccess.open(OS.get_environment("WALK_CSV"), FileAccess.WRITE)
		csv.store_line("frame,speed,phase,soleL,soleR,ankleL,ankleR,fvL,fvR,pelvisY,pelvisF,headY,headF,addL,addR,pitchL,pitchR")
	Input.action_press("move_forward")
	var shot := 0
	var last_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	print("frame  speed  phase  soleL  soleR  ankleL ankleR  fvL    fvR   pelvisY pelvisF headY  headF")
	while frame[0] < int(seconds * 60.0):
		await _frames(1)
		frame[0] += 1
		var forward := -_player.global_basis.z
		var foot_speed: Array[float] = [0.0, 0.0]
		for side in 2:
			if frame[0] > 1:
				foot_speed[side] = (_foot_pos[side] - last_pos[side]).dot(forward) * 60.0
			last_pos[side] = _foot_pos[side]
		var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		var phase: float = locomotion.get("_phase") if locomotion != null else 0.0
		print("%4d  %5.2f  %.3f  %5.2f  %5.2f  %5.2f  %5.2f  %6.2f %6.2f  %6.3f  %6.3f  %6.3f  %6.3f" % [frame[0], speed, phase, _sole[0], _sole[1], _ankle[0], _ankle[1], foot_speed[0], foot_speed[1], _pelvis_y, _pelvis_fwd, _head_y, _head_fwd])
		if csv != null:
			var added := PackedFloat32Array([0.0, 0.0])
			if locomotion != null and locomotion.ankle_pitch != null:
				added = locomotion.ankle_pitch.added_deg
			csv.store_line("%d,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f" % [frame[0], speed, phase, _sole[0], _sole[1], _ankle[0], _ankle[1], foot_speed[0], foot_speed[1], _pelvis_y, _pelvis_fwd, _head_y, _head_fwd, added[0], added[1], _pitch[0], _pitch[1]])
		if step > 0 and frame[0] >= from and frame[0] % step == 0:
			var side := _player.global_basis.x
			var height := float(OS.get_environment("WALK_CAM_H")) if OS.get_environment("WALK_CAM_H") != "" else 3.0
			var distance := float(OS.get_environment("WALK_CAM_D")) if OS.get_environment("WALK_CAM_D") != "" else 30.0
			var at := _player.global_position + Vector3.UP * height
			camera.look_at_from_position(at + side * distance, at)
			await process_frame
			map.get_viewport().get_texture().get_image().save_png("%s/walk_%03d.png" % [out, shot])
			shot += 1
	Input.action_release("move_forward")
	if csv != null:
		csv.close()
	quit()
