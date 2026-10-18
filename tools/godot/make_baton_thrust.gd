extends SceneTree
## Makes the Baton two-hand thrust (user request 2026-10-18: W + RMB with the Baton, a straight forward
## jab with both hands, the baton tip toward the target). Keyframed by code, like make_straight_punch.gd.
##
## How: the body starts and ends in the ready pose of the full hammer swing (melee_hammer_swing.res at
## 0 s, so a chain blends from and into the hammer clips the Baton plays too). The baton is a rigid
## line on the right hand (the shaft of scenes/weapons/baton.tscn: hand space (-0.25, 0.88, z), the
## right hand at z = 0, the left hand at z = LEFT_GRIP). Key poses of the shaft (grip point, direction,
## torso turn and lean) are eased frame by frame; both arms are solved onto the shaft with two-bone IK
## (the elbows point down and out), the hands turn with the shaft. Ready -> chamber and extend ->
## ready blend the bone rotations (the ready pose has the left hand off the shaft). The head turns
## back against the torso turn and keeps looking forward. The legs hold the ready pose; the travel
## curve gives a short step forward with the jab.
##
## Run: godot --headless --path . --script res://tools/godot/make_baton_thrust.gd -- <out anim .res> <out travel .tres>
## Example: ... -- res://data/animations/melee_baton_thrust.res res://data/animations/melee_baton_thrust_travel.tres

const MODEL := "res://models/new_mech/new_mech_exploded.glb"
const READY_CLIP := "res://data/animations/melee_hammer_swing.res"
const FPS := 30.0
const LENGTH := 1.4
## Key times (seconds): ready, chamber (pulled back), full reach, hold end, ready again.
const KEYS := [0.0, 0.3, 0.52, 0.72, 1.4]
## Shaft line in hand_R space (x, y); the right hand grips at z = 0, the left hand at LEFT_GRIP.
const SHAFT := Vector2(-0.25, 0.88)
const LEFT_GRIP := 1.3
## The left hand's grip offset in its own space (the mirror of the right hand's, as MeleeWeapon).
const LEFT_HAND_GRIP := Vector3(0.25, 0.88, 0.0)
## Right grip point (model space: +Z forward, +X left, y up; m) at the chamber and at full reach.
const GRIP_CHAMBER := Vector3(-0.9, 5.6, 0.9)
const GRIP_REACH := Vector3(-0.35, 6.0, 3.6)
## Shaft direction (model space) at the chamber and at full reach: forward, a little in and down.
const AIM_CHAMBER := Vector3(0.12, 0.05, 1.0)
const AIM_REACH := Vector3(0.04, -0.04, 1.0)
## Torso turn about up (degrees; negative = to the right, the left shoulder comes forward) and forward
## lean (degrees) at the chamber and at full reach.
const TURN_CHAMBER_DEG := -12.0
const TURN_REACH_DEG := -28.0
const LEAN_CHAMBER_DEG := -4.0
const LEAN_REACH_DEG := 8.0
## Elbow pole (model space, per side): down and out.
const POLE_R := Vector3(-0.8, -1.0, -0.2)
const POLE_L := Vector3(0.8, -1.0, -0.2)
## Step forward with the jab (m).
const TRAVEL_M := 1.2

var _skeleton: Skeleton3D
var _ready_pose := {}
var _pelvis_position := Vector3.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	get_root().add_child(model)
	await process_frame
	for player in model.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).active = false
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var ready_clip := load(READY_CLIP) as Animation
	var paths := {}
	for track in ready_clip.get_track_count():
		var bone := String(ready_clip.track_get_path(track).get_concatenated_subnames())
		if ready_clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			_ready_pose[bone] = ready_clip.rotation_track_interpolate(track, 0.0)
			paths[bone] = ready_clip.track_get_path(track)
		elif ready_clip.track_get_type(track) == Animation.TYPE_POSITION_3D and bone == "pelvis":
			_pelvis_position = ready_clip.position_track_interpolate(track, 0.0)

	var chamber := _solve(0.0)
	var reach := _solve(1.0)
	var anim := Animation.new()
	anim.length = LENGTH
	anim.step = 1.0 / FPS
	var tracks := {}
	for bone: String in _ready_pose:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, paths[bone])
		tracks[bone] = track
	var pelvis_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pelvis_track, NodePath("MechRig/Skeleton3D:pelvis"))
	var frames := int(ceil(LENGTH * FPS))
	for frame in frames + 1:
		var time := minf(frame / FPS, LENGTH)
		var pose: Dictionary
		if time <= KEYS[1]:
			pose = _blend(_ready_pose, chamber, smoothstep(0.0, 1.0, time / KEYS[1]))
		elif time <= KEYS[2]:
			# The jab: fast out, slowing into full reach.
			var k := (time - KEYS[1]) / (KEYS[2] - KEYS[1])
			pose = _solve(1.0 - pow(1.0 - k, 2.5))
		elif time <= KEYS[3]:
			pose = reach
		else:
			pose = _blend(reach, _ready_pose, smoothstep(0.0, 1.0, (time - KEYS[3]) / (KEYS[4] - KEYS[3])))
		for bone: String in _ready_pose:
			anim.rotation_track_insert_key(tracks[bone], time, pose.get(bone, _ready_pose[bone]))
		anim.position_track_insert_key(pelvis_track, time, _pelvis_position)
	_report(reach)

	var curve := Curve.new()
	curve.min_value = -0.5
	curve.max_value = 1.5
	for frame in frames + 1:
		var time := minf(frame / FPS, LENGTH)
		var k := clampf((time - KEYS[1]) / (KEYS[2] - KEYS[1]), 0.0, 1.0)
		curve.add_point(Vector2(time / LENGTH, smoothstep(0.0, 1.0, k)), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.set_meta(&"travel_m", TRAVEL_M)
	curve.set_meta(&"travel_direction", Vector3.BACK)
	print("save anim ", ResourceSaver.save(anim, args[0]), " curve ", ResourceSaver.save(curve, args[1]))
	quit()


## The pose with the shaft at k (0 = chamber, 1 = full reach): torso turned and leaned, both arms on
## the shaft.
func _solve(k: float) -> Dictionary:
	var pose := _ready_pose.duplicate()
	var turn := deg_to_rad(lerpf(TURN_CHAMBER_DEG, TURN_REACH_DEG, k))
	var lean := deg_to_rad(lerpf(LEAN_CHAMBER_DEG, LEAN_REACH_DEG, k))
	var body_turn := Quaternion(Vector3.UP, turn) * Quaternion(Vector3.RIGHT, lean)
	_apply(pose)
	_set_global(pose, "torso", body_turn * _global_rotation("torso"))
	_apply(pose)
	# The head looks forward again (the turn back, not the lean).
	_set_global(pose, "head", Quaternion(Vector3.UP, -turn) * _global_rotation("head"))
	var grip := GRIP_CHAMBER.lerp(GRIP_REACH, k)
	var aim := AIM_CHAMBER.normalized().slerp(AIM_REACH.normalized(), k).normalized()
	# The right hand: its ready turn, swung so the shaft (hand +Z) lies along aim.
	var ready_hand := _global_rotation("hand_R")
	var hand_turn := (Quaternion(ready_hand * Vector3.BACK, aim) * ready_hand).normalized()
	var shaft_offset := Vector3(SHAFT.x, SHAFT.y, 0.0)
	var right_wrist := grip - hand_turn * shaft_offset
	var left_wrist := grip + aim * LEFT_GRIP - hand_turn * LEFT_HAND_GRIP
	_arm(pose, "R", right_wrist, hand_turn, POLE_R)
	_arm(pose, "L", left_wrist, hand_turn, POLE_L)
	return pose


## Two-bone IK of one arm onto the wrist point, then the hand turn (both in model space).
func _arm(pose: Dictionary, side: String, wrist: Vector3, hand_turn: Quaternion, pole: Vector3) -> void:
	var upper := "upper_arm_" + side
	var fore := "forearm_" + side
	var hand := "hand_" + side
	_apply(pose)
	var shoulder := _origin(upper)
	var a := shoulder.distance_to(_origin(fore))
	var b := _origin(fore).distance_to(_origin(hand))
	var to_wrist := wrist - shoulder
	var distance := clampf(to_wrist.length(), absf(a - b) + 0.01, a + b - 0.01)
	var along := to_wrist.normalized()
	var cos_shoulder := clampf((a * a + distance * distance - b * b) / (2.0 * a * distance), -1.0, 1.0)
	var bend := (pole - along * pole.dot(along)).normalized()
	var elbow := shoulder + along * a * cos_shoulder + bend * a * sqrt(1.0 - cos_shoulder * cos_shoulder)
	var end := shoulder + along * distance
	_aim_bone(pose, upper, fore, elbow)
	_aim_bone(pose, fore, hand, end)
	_apply(pose)
	_set_global(pose, hand, hand_turn)


## Turns bone (shortest way) so its child's origin moves onto point.
func _aim_bone(pose: Dictionary, bone: String, child: String, point: Vector3) -> void:
	_apply(pose)
	var from := (_origin(child) - _origin(bone)).normalized()
	var to := (point - _origin(bone)).normalized()
	_set_global(pose, bone, (Quaternion(from, to) * _global_rotation(bone)).normalized())


## Rotation blend of two poses (each bone slerps in its parent's space).
func _blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var pose := {}
	for bone: String in a:
		pose[bone] = (a[bone] as Quaternion).slerp(b.get(bone, a[bone]) as Quaternion, k)
	return pose


## Prints how far each hand ended from its point on the shaft at full reach (0 = on it) and the tip.
func _report(reach: Dictionary) -> void:
	_apply(reach)
	var hand_r := _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_R"))
	var hand_l := _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_L"))
	var left_on_shaft := hand_r * Vector3(SHAFT.x, SHAFT.y, LEFT_GRIP)
	print("reach: right grip %s (goal %s), left hand off the shaft %.2f m, tip (z 4.6) %s" % [
			hand_r * Vector3(SHAFT.x, SHAFT.y, 0.0), GRIP_REACH, (hand_l * LEFT_HAND_GRIP).distance_to(left_on_shaft),
			hand_r * Vector3(SHAFT.x, SHAFT.y, 4.6)])


func _set_global(pose: Dictionary, bone: String, rotation: Quaternion) -> void:
	var parent := _skeleton.get_bone_parent(_skeleton.find_bone(bone))
	var parent_rotation := _skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	pose[bone] = (parent_rotation.inverse() * rotation).normalized()


func _global_rotation(bone: String) -> Quaternion:
	return _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).basis.get_rotation_quaternion()


func _origin(bone: String) -> Vector3:
	return _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin


func _apply(pose: Dictionary) -> void:
	_skeleton.reset_bone_poses()
	for bone: String in pose:
		_skeleton.set_bone_pose_rotation(_skeleton.find_bone(bone), pose[bone])
	_skeleton.set_bone_pose_position(_skeleton.find_bone("pelvis"), _pelvis_position)
	_skeleton.force_update_all_bone_transforms()
