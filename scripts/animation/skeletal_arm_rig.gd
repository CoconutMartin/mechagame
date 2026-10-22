class_name SkeletalArmRig
extends SkeletonModifier3D
## Lets a rigged (skeletal) mech hold weapons with the same weapon code as the part-built mechs.
## It keeps a small node frame that follows the skeleton: Torso (weapon space, same layout as the
## part-built torso: -Z forward, shoulders at shoulder_height), ShoulderL/R and ElbowL/R. The arm IK
## (TwoBoneIK) bends these joint nodes to the weapon grips; this modifier then copies their turn onto
## the arm bones and closes the fingers of each holding hand (Hand_Grip pose). An arm with no IK
## target keeps its animation. While aiming, the torso bone turns right and tilts by the weapon's
## aim twist and tilt (like TorsoPose on the part-built mechs), so the left hand reaches a long rifle.
## Neutral arms (user rule 2026-10-11): the shoulder armor block (the upper arm mesh) is flat on top, so
## the elbow sits under its outer edge. Each upper arm swings from that flat pose, and the elbow stays
## as near to it as the hand target lets it (tucked elbows).
## Relaxed arms (user request 2026-10-18, clip arm swing; it replaces the whole-arm swing about the shoulder
## of the same day): an arm at its relaxed hang (an empty or fist hand) is solved to the still hang marker
## (with FreeArmSwing's small idle sway while standing), then its upper arm, forearm and hand take the arm
## turns of FreeArmSwing's clip ("Slow Run - arm swing", locked to the stride), blended from the hang by
## FreeArmSwing.amount (the speed). The mech's hips are nearly as wide as its shoulders and its torso is
## 3 m deep, so the clip's forearms (they point in toward the middle, like a human runner's) would put the
## fists through the thighs and the chest: the forearm turns out about the torso's up axis at the elbow
## (clip_forearm_out_deg, it points more forward; the hand height stays the clip's) and the upper arm turns a
## little out to the side (clip_out_deg). Where the palm or the wrist
## still comes nearer the legs than swing_leg_clearance, or nearer the torso and pelvis armor than
## swing_body_clearance, the upper arm turns further out (at most swing_max_out_deg, at swing_out_speed_deg).
## Gun and rifle arms (IK to a grip) and melee
## weapon arms (the clip) do not swing. A fist arm that the punch clip drives still gets the hang pose (and
## the clip swing) under the punch clip (WeaponController.fist_hang_target), so the punch fades into it.
## Animated arms while moving (user rule 2026-10-18): an arm that follows the animation (the War Hammer,
## a punch) keeps only moving_raise_scale of the clip's raise to the side, unless the hand or the weapon
## head would come too near a leg.
## A skeleton modifier must be a child of the Skeleton3D; this node moves itself there at start.
## Keep it after SkeletalHipTurn, so it runs after the hip turn and waist twist.

@export var model: Node3D
## Model yaw when the hips face the mech front (the glTF model faces +Z: PI).
@export var model_base_yaw: float = PI
## Weapon frame nodes (made by tools/godot/build_sanggigilid.gd).
@export var torso: Node3D
@export var shoulder_left: Node3D
@export var shoulder_right: Node3D
@export var ik_left: TwoBoneIK
@export var ik_right: TwoBoneIK
## The weapon aim amount and the weapon's torso turn and tilt while aiming (TorsoPose holds the
## weapon data values: aim_twist_deg to the right, aim_tilt_deg).
@export var weapon_pose: WeaponPose
@export var torso_pose: TorsoPose
## The weapons (their weight sets the arm swing limit).
@export var weapons: WeaponController
## Optional. The sniping stance: the head turns back to the aim by its hip turn plus the torso twist.
@export var stance: SkeletalAimStance
## Optional. The jump and landing crouch lifts the weapon frame (SkeletalJumpPose.weapon_offset).
@export var jump_pose: SkeletalJumpPose
## Jump guard (SkeletalJumpPose.guard): free and fist hands go to these places (torso frame: +X right,
## +Y up, -Z forward) in front of the chest.
@export var guard_left: Vector3 = Vector3(-1.3, 0.9, -2.0)
@export var guard_right: Vector3 = Vector3(1.3, 0.9, -2.0)
## Jump guard: the weapon frame moves this far forward (m, level) at full guard.
@export var guard_forward: float = 2.0
@export var head_bone: StringName = &"head"
## In the sniping stance the head looks along the rifle: its pitch against the horizon stays inside this (degrees),
## and it follows the aim at this speed (1 / seconds; a heavy head, not a snap).
@export var head_pitch_limit_deg: float = 30.0
@export var head_follow_speed: float = 12.0
## In the sniping stance the right elbow tucks toward this direction (torso space: out to the side and
## a little down, inside max_lift_deg), like the reference's raised right elbow.
@export var stance_right_elbow: Vector3 = Vector3(1.0, -0.6, 0.15)
## In the sniping stance the torso bends up or down with the aim, this much at most (degrees).
@export var stance_max_pitch_deg: float = 30.0

@export_group("Arm swing limit")
## Largest upper arm swing forward or back from hanging down (degrees), for weapons up to
## light_weapon_t. Heavier weapons: limit_per_ton less per ton, down to min_swing_deg. The limit
## holds the arms below a right angle (user rule 2026-10-11). When an arm stops at its limit, the
## held weapon moves to the hand.
@export var max_swing_deg: float = 50.0
@export var light_weapon_t: float = 2.0
@export var limit_per_ton: float = 5.0
@export var min_swing_deg: float = 30.0
## An elbow turn (to stay inside the swing limit) may not lift the upper arm more than this from
## hanging down in any direction (degrees): no elbows raised high to the side.
@export var max_lift_deg: float = 60.0
@export_group("")
@export var torso_bone: StringName = &"torso"
@export var upper_arm_bones: PackedStringArray = ["upper_arm_L", "upper_arm_R"]
@export var forearm_bones: PackedStringArray = ["forearm_L", "forearm_R"]
## Wrist bones (the clip arm swing turns them too).
@export var hand_bones: PackedStringArray = ["hand_L", "hand_R"]
## Weapon socket bones in the palms: the IK puts these on the weapon grips.
@export var grip_bones: PackedStringArray = ["grip_L", "grip_R"]
## Shoulder height in the Torso node (the part-built frame value, so the weapon data poses fit).
@export var shoulder_height: float = 2.465
## Animation with the closed hand pose, and the finger bone name parts.
@export var grip_animation: StringName = &"Hand_Grip"
@export var finger_names: PackedStringArray = ["index", "middle", "ring", "pinky", "thumb"]
## Finger curl of a holding hand, as a part of the grip_animation curl (above 1 closes the fist more,
## around the grip).
@export var grip_curl: float = 1.4
## Shoulder weapon mounts (left, right; Torso children): on top of the shoulder armor meshes,
## shoulder_mount_gap above them. Each mount turns with its upper arm bone (the shoulder armor).
@export var shoulder_mounts: Array[Node3D] = []
@export var shoulder_armor_meshes: PackedStringArray = ["Arm_L_01", "Arm_R_01"]
@export var shoulder_mount_gap: float = 0.15
## Elbows stay as near as the hand target lets them to their neutral place (under the flat shoulder
## block): the elbow turns around the shoulder-to-hand line. Off: the IK elbow directions (poles) decide.
@export var tuck_elbows: bool = true
## The flat block may turn about the up axis up to this much (degrees) to bring the elbow forward or
## back; its top stays flat. 20 (user, 2026-10-13: "the shoulder blocks can take some angle"; was 0,
## the rule of 2026-10-12 that the shoulders face forward at neutral). At rest only: it fades out
## while aiming.
@export var max_block_yaw_deg: float = 20.0
## Fastest elbow swing around the shoulder-to-hand line (degrees per second), after all the arm steps:
## no elbow jumps, and the shoulder blocks do not fling on a quick aim (RMB tap) but swing back over
## about a second (user request 2026-10-13). The hand stays on its target.
@export var max_elbow_speed_deg: float = 70.0
## How strongly the elbow choice avoids a block turn past max_block_yaw_deg (cost weight).
@export var block_yaw_weight: float = 10.0
## Away from the neutral elbow height the block turn fades out over this many degrees; a raised arm
## swings the block like before.
@export var block_yaw_fade_deg: float = 30.0
@export_group("Moving arms")
## An arm that follows the animation keeps this part of the clip's raise to the side (the walk clips'
## shallow V) while the mech moves: 0.5 = half the angle (user rule 2026-10-18). 1 = the clip as it is.
@export_range(0.0, 1.0) var moving_raise_scale: float = 0.5
## Ground speed (m/s) at which the lower raise is fully on (it fades in from standing).
@export var moving_raise_speed: float = 3.0
## How fast the lower raise fades in and out (per second).
@export var moving_raise_blend: float = 3.0
## The palm (grip bone) and the handle of a held melee weapon stay this far (m) from the leg bone lines
## (thigh armor half width plus a fist): the arm lowers less where it would come nearer.
@export var leg_clearance: float = 1.3
## The same for the melee weapon head (its StrikePoint; the War Hammer head is 1.4 m wide).
@export var weapon_head_clearance: float = 1.7
## How fast the lowering comes back after a leg made it smaller, and how fast a leg makes it smaller
## (part per second; limited both ways, so the arm does not pop).
@export var raise_recover_speed: float = 1.5
@export var raise_drop_speed: float = 3.0
## The melee weapon handle reaches this part of the palm-to-head length behind the palm (the War Hammer's
## butt end); those handle points keep leg_clearance too.
@export var weapon_butt_share: float = 0.35
@export var leg_bones: PackedStringArray = ["thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]
@export_group("Clip arm swing")
## The forearm turns out about the torso's up axis at the elbow this much (degrees, at the full clip amount),
## so it points forward and the fist passes outside the thighs and the chest. 0 since the heavy arm
## (FreeArmSwing, 2026-10-22): the arm swings about its hang pose, which is outside the thighs already.
@export var clip_forearm_out_deg: float = 0.0
## The upper arm turns out to the side this much (degrees, about the torso's forward axis, at the full clip
## amount). 0 for the same reason.
@export var clip_out_deg: float = 0.0
## A relaxed arm in the clip swing keeps its palm and wrist this far (m) from the leg bone lines, or as far
## as in its hang pose where that is nearer (0.8 m: the nearest of the approved whole-arm swing, renders
## 2026-10-18). Nearer, the upper arm turns further out.
@export var swing_leg_clearance: float = 0.8
## The palm and the wrist keep this far (m) from the torso and pelvis armor boxes (about half a fist).
@export var swing_body_clearance: float = 0.5
## Armor meshes (Skeleton3D children) the clip arms keep off, and the bone each one moves with.
@export var body_meshes: PackedStringArray = ["Torso", "Pelvis"]
@export var body_mesh_bones: PackedStringArray = ["torso", "pelvis"]
## The largest further turn out to the side for that (degrees), and how fast it may change (degrees per
## second, both ways; no pop).
@export var swing_max_out_deg: float = 25.0
@export var swing_out_speed_deg: float = 240.0
@export_group("")

var _skeleton: Skeleton3D
var _guard_markers: Array[Marker3D] = [null, null]
var _torso_offset: Transform3D
var _sides: Array[Dictionary] = []
## Seconds since the last modification (the elbow speed limit).
var _delta: float = 1.0 / 60.0
## Shoulder mount place in its upper arm bone's space: [mount, bone, offset].
var _mount_offsets: Array = []
## The right weapon's transform from WeaponPose, and the moved one this rig set (the weapon moves to
## a limited hand; WeaponPose sets it again on its next physics frame). Index 0: the left gun or
## pile bunker (user rule 2026-10-15), index 1: the right weapon.
var _weapon_base: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _weapon_moved: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
## The relaxed arm swing of this mech (found on first use; Mech adds it at runtime).
var _free_swing: FreeArmSwing
## Lower raise of the animated arms now (0 = standing, 1 = moving).
var _raise_amount: float = 0.0
## Armor boxes the clip arms keep off: [bone, AABB in that bone's rest space].
var _body_boxes: Array = []
## The head turn that looks along the aim (local rotation), and how much of it the stance holds now.
var _head_aim: Quaternion = Quaternion.IDENTITY
var _head_blend: float = 0.0


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


## Runs once, at the first modification (the node is under the skeleton then).
func _setup() -> void:
	_skeleton = get_skeleton()
	# The rig solves the arms itself (with the swing limit and the bone twist); the IK nodes' own
	# physics solve would put the joint nodes back to their own twist between frames.
	for ik in [ik_left, ik_right]:
		ik.set_physics_process(false)
	var torso_bone_id := _skeleton.find_bone(torso_bone)
	# Torso node at rest: mech axes, shoulders at shoulder_height above its origin. Mech space = the
	# model with its hips facing the mech front (no hip turn).
	var to_mech := Transform3D(Basis(Vector3.UP, model_base_yaw)) * model.global_transform.affine_inverse() \
			* _skeleton.global_transform
	var shoulder_mid := Vector3.ZERO
	for bone_name in upper_arm_bones:
		shoulder_mid += to_mech * _skeleton.get_bone_global_rest(_skeleton.find_bone(bone_name)).origin * 0.5
	var torso_rest := Transform3D(Basis.IDENTITY, shoulder_mid - Vector3(0.0, shoulder_height, 0.0))
	var bone_rest := _skeleton.get_bone_global_rest(torso_bone_id).orthonormalized()
	_torso_offset = bone_rest.affine_inverse() * (to_mech.affine_inverse() * torso_rest)
	for i in mini(shoulder_mounts.size(), shoulder_armor_meshes.size()):
		var armor := _skeleton.get_node_or_null(NodePath(shoulder_armor_meshes[i])) as MeshInstance3D
		if armor == null or shoulder_mounts[i] == null:
			continue
		# The mount sits level on top of the block in the flat (neutral) pose.
		var bone := _skeleton.find_bone(upper_arm_bones[i])
		var flat_rest := _flat_rest(bone, armor)
		var flat_turn := flat_rest * _skeleton.get_bone_global_rest(bone).orthonormalized().affine_inverse()
		var box := AABB()
		var vertices: PackedVector3Array = armor.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in vertices.size():
			var point := to_mech * flat_turn * armor.transform * vertices[v]
			box = AABB(point, Vector3.ZERO) if v == 0 else box.expand(point)
		var top := Vector3(box.get_center().x, box.end.y + shoulder_mount_gap, box.get_center().z)
		shoulder_mounts[i].position = top - torso_rest.origin
		var mount_rest := to_mech.affine_inverse() * Transform3D(Basis.IDENTITY, top)
		_mount_offsets.append([shoulder_mounts[i], bone, flat_rest.affine_inverse() * mount_rest])
	for i in mini(body_meshes.size(), body_mesh_bones.size()):
		var mesh := _skeleton.get_node_or_null(NodePath(body_meshes[i])) as MeshInstance3D
		var bone := _skeleton.find_bone(body_mesh_bones[i])
		if mesh == null or mesh.mesh == null or bone < 0:
			continue
		var to_bone := _skeleton.get_bone_global_rest(bone).affine_inverse() * mesh.transform
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var box := AABB()
		for v in vertices.size():
			box = AABB(to_bone * vertices[v], Vector3.ZERO) if v == 0 else box.expand(to_bone * vertices[v])
		_body_boxes.append([bone, box])
	var grip_track := _grip_rotations()
	for i in 2:
		var side := {}
		side.ik = ik_left if i == 0 else ik_right
		side.shoulder = shoulder_left if i == 0 else shoulder_right
		side.upper = _skeleton.find_bone(upper_arm_bones[i])
		side.fore = _skeleton.find_bone(forearm_bones[i])
		side.hand = _skeleton.find_bone(hand_bones[i])
		var grip := _skeleton.find_bone(grip_bones[i])
		side.grip = grip
		var p_shoulder := _skeleton.get_bone_global_rest(side.upper).origin
		var p_elbow := _skeleton.get_bone_global_rest(side.fore).origin
		var p_grip := _skeleton.get_bone_global_rest(grip).origin
		# Neutral (flat block) upper arm: its local rotation, and its elbow direction in the parent
		# bone's space.
		var armor := _skeleton.get_node_or_null(NodePath(shoulder_armor_meshes[i])) as MeshInstance3D \
				if i < shoulder_armor_meshes.size() else null
		var flat_rest := _flat_rest(side.upper, armor)
		var parent_rest := _skeleton.get_bone_global_rest(_skeleton.get_bone_parent(side.upper)).orthonormalized()
		side.flat_local = (parent_rest.basis.inverse() * flat_rest.basis).get_rotation_quaternion()
		side.flat_dir = parent_rest.basis.inverse() * (flat_rest.basis \
				* _skeleton.get_bone_global_rest(side.upper).basis.orthonormalized().inverse() * (p_elbow - p_shoulder)).normalized()
		var ik := side.ik as TwoBoneIK
		ik.upper_length = p_shoulder.distance_to(p_elbow)
		ik.lower_length = p_elbow.distance_to(p_grip)
		ik.mid_joint.position = Vector3(0.0, -ik.upper_length, 0.0)
		# The joint nodes point down their -Y axis (TwoBoneIK); the bones point their own way. The
		# offsets turn a joint node's basis into its bone's basis (skeleton space, at rest).
		var across := Vector3.RIGHT if i == 1 else Vector3.LEFT
		side.upper_offset = _joint_basis(p_shoulder, p_elbow, across).inverse() \
				* _skeleton.get_bone_global_rest(side.upper).basis.orthonormalized()
		side.fore_offset = _joint_basis(p_elbow, p_grip, across).inverse() \
				* _skeleton.get_bone_global_rest(side.fore).basis.orthonormalized()
		var fingers := {}
		var suffix := "_L" if i == 0 else "_R"
		for bone_name: String in grip_track:
			if bone_name.ends_with(suffix):
				var bone := _skeleton.find_bone(bone_name)
				var rest := _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
				var curl := rest.inverse() * (grip_track[bone_name] as Quaternion)
				fingers[bone] = rest * Quaternion(curl.get_axis(), curl.get_angle() * grip_curl) \
						if curl.get_angle() > 0.001 else rest
		side.fingers = fingers
		# The hand's index-to-pinky line (the way through a closed fist), in the elbow joint node's space.
		var line := _skeleton.get_bone_global_rest(_skeleton.find_bone("pinky_01" + suffix)).origin \
				- _skeleton.get_bone_global_rest(_skeleton.find_bone("index_01" + suffix)).origin
		side.hand_across = (_joint_basis(p_elbow, p_grip, across).inverse() * line).normalized()
		_sides.append(side)


## The upper arm bone's global rest turned about the shoulder so the armor block's top face is flat.
func _flat_rest(bone: int, armor: MeshInstance3D) -> Transform3D:
	var rest := _skeleton.get_bone_global_rest(bone).orthonormalized()
	if armor == null:
		return rest
	var top := armor.transform.basis * _top_normal(armor.mesh)
	return Transform3D(Basis(Quaternion(top.normalized(), Vector3.UP)) * rest.basis, rest.origin)


## The most upward of the main face directions of a mesh (its top face normal).
static func _top_normal(mesh: Mesh) -> Vector3:
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var counts := {}
	for n in normals:
		var key := n.snapped(Vector3.ONE * 0.1)
		counts[key] = counts.get(key, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a: Vector3, b: Vector3) -> bool: return counts[a] > counts[b])
	var top := Vector3.DOWN
	for key: Vector3 in keys.slice(0, 12):
		if key.normalized().y > top.y:
			top = key.normalized()
	return top


## Finger bone rotations of the closed hand pose (first frame of grip_animation).
func _grip_rotations() -> Dictionary:
	var rotations := {}
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or not player.has_animation(grip_animation):
		return rotations
	var animation := player.get_animation(grip_animation)
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name := String(animation.track_get_path(track).get_concatenated_subnames())
		for part in finger_names:
			if bone_name.begins_with(part):
				rotations[bone_name] = animation.rotation_track_interpolate(track, 0.0)
	return rotations


## Turns the torso bone right (about the up axis) and tilts it by the weapon aim values.
func _aim_twist() -> void:
	if weapon_pose == null or torso_pose == null or weapon_pose.weapon == null:
		return
	var aim := smoothstep(0.0, 1.0, weapon_pose.aim_amount)
	if aim <= 0.0:
		return
	var bone := _skeleton.find_bone(torso_bone)
	var pose := _skeleton.get_bone_global_pose(bone)
	var up := (_skeleton.global_basis.inverse() * Vector3.UP).normalized()
	var turn := Basis(up, -deg_to_rad(torso_pose.aim_twist_deg) * aim)
	# Tilt = roll about the torso's forward axis (the weapon side down), after the turn.
	var forward := turn * (_skeleton.global_basis.inverse() * -torso.global_basis.z).normalized()
	turn = Basis(forward.normalized(), -deg_to_rad(torso_pose.aim_tilt_deg) * aim) * turn
	# Sniping stance: the upper body bends with the aim's height (like a rifleman), so the rifle stays
	# on the shoulder in one hold and only the torso pitches.
	if stance != null and stance.amount > 0.0 and weapon_pose.mech_aim != null:
		var to_aim := _skeleton.global_basis.inverse() * (weapon_pose.mech_aim.aim_point - _skeleton.global_transform * pose.origin)
		var flat := to_aim - up * to_aim.dot(up)
		if flat.length_squared() > 0.0001:
			var limit := deg_to_rad(stance_max_pitch_deg)
			var pitch := clampf(atan2(to_aim.dot(up), flat.length()), -limit, limit)
			turn = Basis(flat.normalized().cross(up).normalized(), pitch * stance.amount) * turn
	var parent := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(bone))
	var local := parent.basis.orthonormalized().inverse() * (turn * pose.basis.orthonormalized())
	_skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


## In the sniping stance the head looks along the rifle (user report 2026-10-22: the head kept its idle scan
## and looked off to the side). The head bone gets its turn from scratch, so the idle head animation (Head_Scan)
## does not count: forward along the aim line (the rifle's bore line, toward the aim point), up as near the
## world up as it can be (no roll), blended in by the stance amount and followed at head_follow_speed.
func _head_to_aim(delta: float) -> void:
	if stance == null or stance.amount <= 0.0 or weapon_pose == null or weapon_pose.weapon == null \
			or weapon_pose.mech_aim == null:
		_head_blend = 0.0
		return
	var head := _skeleton.find_bone(head_bone)
	if head < 0:
		return
	var to_skeleton := _skeleton.global_basis.orthonormalized().inverse()
	var aim_dir := to_skeleton * (weapon_pose.mech_aim.aim_point - weapon_pose.weapon.global_position)
	if aim_dir.length_squared() < 0.0001:
		return
	var up := (to_skeleton * Vector3.UP).normalized()
	aim_dir = aim_dir.normalized()
	# Head pitch against the horizon stays inside head_pitch_limit_deg.
	var limit := deg_to_rad(head_pitch_limit_deg)
	var flat := aim_dir - up * aim_dir.dot(up)
	if flat.length_squared() > 0.0001:
		var pitch := clampf(atan2(aim_dir.dot(up), flat.length()), -limit, limit)
		aim_dir = (flat.normalized() * cos(pitch) + up * sin(pitch)).normalized()
	var rest := _skeleton.get_bone_global_rest(head).basis.orthonormalized()
	# The head's own forward (model +Z at rest) and up in the bone frame.
	var forward_local := rest.inverse() * Vector3.BACK
	var up_local := rest.inverse() * Vector3.UP
	var local_frame := Basis(up_local.cross(forward_local), up_local, forward_local)
	var head_up := (up - aim_dir * up.dot(aim_dir)).normalized()
	var target_frame := Basis(head_up.cross(aim_dir), head_up, aim_dir)
	var parent := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(head)).basis.orthonormalized()
	var wanted := (parent.inverse() * target_frame * local_frame.inverse()).get_rotation_quaternion()
	# Follow the aim a little softly; start from where the animation has the head.
	var from := _skeleton.get_bone_pose_rotation(head)
	if _head_blend <= 0.0:
		_head_aim = from
	_head_blend = stance.amount
	_head_aim = _head_aim.slerp(wanted, 1.0 - exp(-head_follow_speed * delta))
	_skeleton.set_bone_pose_rotation(head, from.slerp(_head_aim, smoothstep(0.0, 1.0, _head_blend)))


## Turns the arm bones to the IK result with no extra twist: each bone swings (shortest turn) from
## its neutral direction (the upper arm: flat block) to the joint node direction, so it keeps the model's own twist about its axis (the shoulder armor stays on the shoulder ball, the palm keeps its side). Then the joint nodes
## take the bones' turn, so the weapons and the shield on them sit on the real arm.
func _pose_arm(side: Dictionary) -> void:
	var skin := _skeleton.global_transform
	var to_skeleton := skin.basis.orthonormalized().inverse()
	var shoulder := side.shoulder as Node3D
	var ik := side.ik as TwoBoneIK
	var upper: int = side.upper
	var fore: int = side.fore
	# Start pose: the neutral pose of the arm under the torso now (the same every frame; the animation does
	# not always key the arm bones, so their pose from the last frame would make the twist drift).
	var parent_pose := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(upper)).orthonormalized()
	var upper_pose := parent_pose * Transform3D(Basis(side.flat_local as Quaternion), _skeleton.get_bone_rest(upper).origin)
	var fore_pose := upper_pose * _skeleton.get_bone_rest(fore)
	var grip_point := (fore_pose * _skeleton.get_bone_global_rest(fore).affine_inverse() \
			* _skeleton.get_bone_global_rest(side.grip)).origin
	# Upper arm: animated shoulder-to-elbow direction to the IK direction.
	var ik_upper := (to_skeleton * (ik.mid_joint.global_position - shoulder.global_position)).normalized()
	# The flat block first turns about the up axis toward the elbow (top stays flat), then swings.
	var neutral := (fore_pose.origin - upper_pose.origin).normalized()
	var up := (to_skeleton * torso.global_basis.y).normalized()
	var yaw := Basis(up, _block_yaw(ik_upper, neutral, up))
	var upper_swing := Basis(Quaternion((yaw * neutral).normalized(), ik_upper)) * yaw
	var upper_basis := upper_swing * upper_pose.basis
	# Forearm: it moved with the upper arm; then elbow-to-palm direction to the IK direction.
	var fore_basis := upper_swing * fore_pose.basis
	var palm_local := fore_pose.basis.inverse() * (grip_point - fore_pose.origin)
	var ik_fore := (to_skeleton * (_hand(ik) - ik.mid_joint.global_position)).normalized()
	fore_basis = Basis(Quaternion((fore_basis * palm_local).normalized(), ik_fore)) * fore_basis
	_skeleton.set_bone_pose_rotation(upper, (parent_pose.basis.inverse() * upper_basis).get_rotation_quaternion())
	_skeleton.set_bone_pose_rotation(fore, (upper_basis.inverse() * fore_basis).get_rotation_quaternion())
	# A holding hand closes; the free (relaxed) left hand stays open.
	if weapons == null or (ik.target != weapons.free_left_hand and ik.target != weapons.free_right_hand):
		for bone: int in side.fingers:
			_skeleton.set_bone_pose_rotation(bone, side.fingers[bone])
	shoulder.global_basis = (skin.basis.orthonormalized() * upper_basis * (side.upper_offset as Basis).inverse()).orthonormalized()
	ik.mid_joint.global_basis = (skin.basis.orthonormalized() * fore_basis * (side.fore_offset as Basis).inverse()).orthonormalized()


## The joint nodes take the arm bones' turn now (after a change of the bones), so the weapons, the shield
## and the hand places on them sit on the real arm.
func _joints_from_bones(side: Dictionary) -> void:
	var skin := _skeleton.global_transform.basis.orthonormalized()
	var upper_basis := _skeleton.get_bone_global_pose(side.upper as int).basis.orthonormalized()
	var fore_basis := _skeleton.get_bone_global_pose(side.fore as int).basis.orthonormalized()
	(side.shoulder as Node3D).global_basis = (skin * upper_basis * (side.upper_offset as Basis).inverse()).orthonormalized()
	(side.ik as TwoBoneIK).mid_joint.global_basis = (skin * fore_basis * (side.fore_offset as Basis).inverse()).orthonormalized()


## Arm IK with the swing limit. The right weapon moves to a limited right hand. A two-hand weapon then
## moves back to a limited left hand (if it falls short), and the right arm takes its grip again.
func _solve_arms(active: Array[Dictionary]) -> void:
	_solve_arms_once(active)
	for side in active:
		_limit_elbow_speed(side.ik as TwoBoneIK, side)


func _solve_arms_once(active: Array[Dictionary]) -> void:
	var left_ik: TwoBoneIK = null
	var right_ik: TwoBoneIK = null
	for side in active:
		if side.ik == ik_left:
			left_ik = ik_left
		else:
			right_ik = ik_right
	if right_ik != null:
		_restore_weapon(weapons.right_weapon if weapons != null else null, 1)
		right_ik.solve()
		_tuck_elbow(right_ik)
		_limit_swing(right_ik, swing_limit(true))
		_move_weapon_to_hand(weapons.right_weapon if weapons != null else null, right_ik, 1)
	if left_ik == null:
		return
	# A gun or the pile bunker in the left hand moves to a limited left hand like the right one.
	var left_gun := _left_gun()
	_restore_weapon(left_gun, 0)
	left_ik.solve()
	_tuck_elbow(left_ik)
	_limit_swing(left_ik, swing_limit(false))
	_move_weapon_to_hand(left_gun, left_ik, 0)
	var weapon := weapons.right_weapon if weapons != null else null
	if right_ik == null or weapon == null or not weapon.is_ancestor_of(left_ik.target):
		return
	var gap := _hand(left_ik) - left_ik.target.global_position
	if gap.length_squared() < 0.0001:
		return
	weapon.global_position += gap
	_weapon_moved[1] = weapon.transform
	right_ik.solve()
	_tuck_elbow(right_ik)
	_limit_swing(right_ik, swing_limit(true))



## Holds the elbow's swing around the shoulder-to-hand line to max_elbow_speed_deg from the last frame.
func _limit_elbow_speed(ik: TwoBoneIK, side: Dictionary) -> void:
	var shoulder := ik.root_joint.global_position
	var reach := ik.target.global_position - shoulder
	if reach.length_squared() < 0.0001:
		return
	reach = reach.normalized()
	var torso_basis := torso.global_basis.orthonormalized()
	var now := (ik.mid_joint.global_position - shoulder).normalized()
	if side.has("last_elbow"):
		var last: Vector3 = torso_basis * (side.last_elbow as Vector3)
		var flat_now := now - reach * now.dot(reach)
		var flat_last := last - reach * last.dot(reach)
		if flat_now.length_squared() > 0.0001 and flat_last.length_squared() > 0.0001:
			var back := flat_now.signed_angle_to(flat_last, reach)
			var limit := deg_to_rad(max_elbow_speed_deg) * _delta
			var turn := back + clampf(-back, -limit, limit)
			if absf(turn) > 0.00001:
				ik.root_joint.global_basis = (Basis(reach, turn) * ik.root_joint.global_basis).orthonormalized()
				now = (ik.mid_joint.global_position - shoulder).normalized()
	side.last_elbow = torso_basis.inverse() * now

## Turns the elbow around the shoulder-to-hand line (the hand stays on its target) to the place
## nearest its neutral places: the elbow height of the flat block, and as little block turn as
## possible (inside max_block_yaw_deg).
func _tuck_elbow(ik: TwoBoneIK) -> void:
	if not tuck_elbows:
		return
	var side: Dictionary = _sides[0] if ik == ik_left else _sides[1]
	var shoulder := ik.root_joint.global_position
	var parent_pose := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(side.upper)).orthonormalized()
	var neutral := (_skeleton.global_basis.orthonormalized() * parent_pose.basis * (side.flat_dir as Vector3)).normalized()
	if ik == ik_right and stance != null and stance.amount > 0.0:
		var raised := (torso.global_basis.orthonormalized() * stance_right_elbow).normalized()
		neutral = neutral.slerp(raised, stance.amount)
	var up := torso.global_basis.y.normalized()
	var reach := ik.target.global_position - shoulder
	if reach.length_squared() < 0.0001:
		return
	reach = reach.normalized()
	var now := (ik.mid_joint.global_position - shoulder).normalized()
	# Coarse search all around, then finer around the best.
	var best := 0.0
	var best_cost := _elbow_cost(now, neutral, up)
	var step := deg_to_rad(5.0)
	var center := 0.0
	for pass_index in 3:
		var found := best
		var reach_steps: int = 36 if pass_index == 0 else 5
		for i in range(-reach_steps, reach_steps + 1):
			var angle: float = center + step * i
			var cost := _elbow_cost(Basis(reach, angle) * now, neutral, up)
			if cost < best_cost:
				best_cost = cost
				found = angle
		best = found
		center = best
		step /= 5.0
	if best != 0.0:
		ik.root_joint.global_basis = (Basis(reach, best) * ik.root_joint.global_basis).orthonormalized()


## How far an upper arm direction is from neutral: elbow height off the flat block's, and block turn.
func _elbow_cost(dir: Vector3, neutral: Vector3, up: Vector3) -> float:
	var height := absf(dir.angle_to(-up) - neutral.angle_to(-up))
	# Near straight down the turn about up means little (_flat_yaw is 0 there): it fades in smoothly
	# with the lean, so the cost has no step (the shoulder block flickered between a hanging and a
	# turned arm from one frame to the next, user report 2026-10-13).
	var flat := (dir - up * dir.dot(up)).length()
	var yaw := absf(_flat_yaw(dir, neutral, up)) * smoothstep(0.05, 0.2, flat)
	var over := maxf(yaw - _block_limit(), 0.0)
	return height * height + 0.1 * yaw * yaw + block_yaw_weight * over * over


## Signed turn about up from the neutral elbow direction to dir (0 when dir is near straight up or down).
static func _flat_yaw(dir: Vector3, neutral: Vector3, up: Vector3) -> float:
	var flat := dir - up * dir.dot(up)
	var flat_neutral := neutral - up * neutral.dot(up)
	if flat.length_squared() < 0.0025 or flat_neutral.length_squared() < 0.0025:
		return 0.0
	return flat_neutral.signed_angle_to(flat, up)


## The block turn about up for an upper arm direction: the flat yaw (clamped), fading out as the elbow
## height moves away from the neutral one.
func _block_yaw(dir: Vector3, neutral: Vector3, up: Vector3) -> float:
	var height := absf(dir.angle_to(-up) - neutral.angle_to(-up))
	var weight := clampf(1.0 - height / deg_to_rad(block_yaw_fade_deg), 0.0, 1.0)
	var limit := _block_limit()
	return clampf(_flat_yaw(dir, neutral, up), -limit, limit) * weight


## The block turn limit (radians): max_block_yaw_deg at rest, fading to 0 while aiming (the aim holds
## were tuned with flat, forward blocks).
func _block_limit() -> float:
	var amount := weapon_pose.aim_amount if weapon_pose != null else 0.0
	if weapons != null and weapons.left_pose != null:
		amount = maxf(amount, weapons.left_pose.aim_amount)
	return deg_to_rad(max_block_yaw_deg) * (1.0 - smoothstep(0.0, 1.0, amount))


## Where an arm's hand (palm socket) is now.
static func _hand(ik: TwoBoneIK) -> Vector3:
	return ik.mid_joint.global_position + ik.mid_joint.global_basis.y * -ik.lower_length


## Upper arm swing limit (radians) for the weapon an arm holds: the right weapon (right arm, and the
## left arm of a two-hand weapon) or the shield (left arm).
func swing_limit(right: bool) -> float:
	var weight := 0.0
	if weapons != null:
		var data: WeaponData = weapons.right_data if right or weapons.two_handed_left_grip() else weapons.left_data
		weight = data.weight_t if data != null else 0.0
	var limit := max_swing_deg - maxf(weight - light_weapon_t, 0.0) * limit_per_ton
	return deg_to_rad(maxf(limit, min_swing_deg))


## Holds the upper arm within limit forward and back: its lean toward the torso's front or back
## (sideways is free). The elbow turns first; if that is not enough, the upper arm stops at the limit
## and the forearm points at the IK target from the elbow.
func _limit_swing(ik: TwoBoneIK, limit: float) -> void:
	var shoulder := ik.root_joint
	var torso_basis := torso.global_basis.orthonormalized()
	var arm := torso_basis.inverse() * (ik.mid_joint.global_position - shoulder.global_position).normalized()
	var lean := asin(clampf(-arm.z, -1.0, 1.0))
	if absf(lean) <= limit:
		return
	# First the elbow turns around the shoulder-to-hand line (the hand stays on its target): the
	# smallest turn that brings the upper arm inside the limit.
	var reach := (ik.target.global_position - shoulder.global_position).normalized()
	var elbow_out := ik.mid_joint.global_position - shoulder.global_position
	for step in range(1, 37):
		for sign in [1.0, -1.0]:
			var swivel := Basis(reach, deg_to_rad(5.0 * step) * sign)
			var turned := torso_basis.inverse() * (swivel * elbow_out).normalized()
			if absf(asin(clampf(-turned.z, -1.0, 1.0))) <= limit and -turned.y >= cos(deg_to_rad(max_lift_deg)):
				shoulder.global_basis = (swivel * shoulder.global_basis).orthonormalized()
				return
	# No elbow turn helps: the upper arm stops at the limit and the hand falls short.
	var flat := Vector2(arm.x, arm.y)
	flat = flat.normalized() if flat.length_squared() > 0.000001 else Vector2(0.0, -1.0)
	var held := Vector3(flat.x * cos(limit), flat.y * cos(limit), -signf(lean) * sin(limit))
	var turn := torso_basis * Basis(Quaternion(arm, held)) * torso_basis.inverse()
	shoulder.global_basis = (turn * shoulder.global_basis).orthonormalized()
	var side := ik.mid_joint.global_basis.x
	ik.mid_joint.global_basis = _joint_basis(ik.mid_joint.global_position, ik.target.global_position, side)


## The left hand's gun or pile bunker (not a fist: it follows the animation), or null.
func _left_gun() -> Node3D:
	var weapon := weapons.left_weapon if weapons != null else null
	if weapon == null or not is_instance_valid(weapon) or weapon is MeleeWeapon:
		return null
	return weapon


## side: 0 = left, 1 = right.
func _restore_weapon(weapon: Node3D, side: int) -> void:
	if weapon == null:
		return
	if not weapon.transform.is_equal_approx(_weapon_moved[side]):
		_weapon_base[side] = weapon.transform
	weapon.transform = _weapon_base[side]


## A limited hand does not reach the grip: the weapon moves so its grip is in the hand.
func _move_weapon_to_hand(weapon: Node3D, ik: TwoBoneIK, side: int) -> void:
	if weapon == null or ik.target == null or not weapon.is_ancestor_of(ik.target):
		return
	var gap := _hand(ik) - ik.target.global_position
	if gap.length_squared() > 0.000001:
		weapon.global_position += gap
	_weapon_moved[side] = weapon.transform


## The way through a closed fist (index to pinky), in the elbow joint node's space (Vector3.ZERO
## before the first frame).
func hand_across(right: bool) -> Vector3:
	return _sides[1 if right else 0].hand_across if _sides.size() == 2 else Vector3.ZERO


## The torso frame (weapons, shield, hand places) and the shoulder mounts again from the bones now.
## A modifier after this one that turns the body (SkeletalDodgeAnimation) calls it, so the weapon stays
## in the hands.
func refresh_torso() -> void:
	if _skeleton == null:
		return
	torso.global_transform = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(torso_bone)).orthonormalized() \
			* _torso_offset).orthonormalized()
	_jump_lift()
	_follow_shoulders()


## Shoulder mounts follow their upper arm bones (after the arm bones got their final turn).
func _follow_shoulders() -> void:
	var skin := _skeleton.global_transform
	for entry: Array in _mount_offsets:
		var bone: int = entry[1]
		(entry[0] as Node3D).global_transform = (skin * _skeleton.get_bone_global_pose(bone).orthonormalized() \
				* (entry[2] as Transform3D)).orthonormalized()


## Jump crouch lift (SkeletalJumpPose.weapon_offset, torso space) and jump guard rise (straight up).
func _jump_lift() -> void:
	if jump_pose == null:
		return
	torso.global_transform = torso.global_transform.translated_local(jump_pose.weapon_offset())
	if jump_pose.mech == null or jump_pose.guard <= 0.001:
		return
	# The guard: the frame turns level (the torso lean taken out, the turn about the up axis kept), moves
	# forward and rises, so the held weapons keep off the leaning body and the knees (user report
	# 2026-10-19: the rifle went into the body in the landing).
	var amount := smoothstep(0.0, 1.0, jump_pose.guard)
	var up := jump_pose.mech.global_basis.y.normalized()
	var forward := -torso.global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	if forward.length_squared() > 0.5:
		var level := Basis.looking_at(forward, up)
		var turned := Quaternion(torso.global_basis.orthonormalized()).slerp(Quaternion(level), amount)
		torso.global_basis = Basis(turned)
		torso.global_position += forward * guard_forward * amount
	var height := (torso.global_position - jump_pose.mech.global_position).dot(up)
	torso.global_position += up * jump_pose.guard_rise(height)


## Jump guard: a relaxed arm (free or fist hand) aims at a place between its hang marker and the guard
## place, by SkeletalJumpPose.guard. Returns {ik: its own target} to put back after the solve.
func _guard_hands(active: Array[Dictionary]) -> Dictionary:
	var swapped := {}
	if jump_pose == null or jump_pose.guard <= 0.001:
		return swapped
	for side in active:
		var ik := side.ik as TwoBoneIK
		if not _is_relaxed(ik):
			continue
		var right := ik == ik_right
		var marker := _guard_marker(right)
		var place := torso.global_transform * (guard_right if right else guard_left)
		marker.global_transform = Transform3D(ik.target.global_basis,
				ik.target.global_position.lerp(place, smoothstep(0.0, 1.0, jump_pose.guard)))
		swapped[ik] = ik.target
		ik.target = marker
	return swapped


func _guard_marker(right: bool) -> Marker3D:
	var key := 1 if right else 0
	if _guard_markers[key] == null:
		var marker := Marker3D.new()
		marker.name = "HandGuardR" if right else "HandGuardL"
		torso.add_child(marker)
		_guard_markers[key] = marker
	return _guard_markers[key]


## True when the arm's IK goes to a relaxed hang marker (a free or fist hand).
func _is_relaxed(ik: TwoBoneIK) -> bool:
	return weapons != null and ik.target != null and (ik.target == weapons.free_left_hand or ik.target == weapons.free_right_hand)


## The mech's FreeArmSwing (found on first use; Mech adds it at runtime), or null.
func _arm_swing() -> FreeArmSwing:
	if _free_swing == null or not is_instance_valid(_free_swing):
		_free_swing = weapons.mech.get_node_or_null(^"FreeArmSwing") as FreeArmSwing \
				if weapons != null and weapons.mech != null else null
	return _free_swing


## A relaxed arm (IK to a hang marker) turns whole about the shoulder by FreeArmSwing's idle sway while
## standing (it fades out as the clip swing fades in).
func _swing_relaxed(side: Dictionary) -> void:
	var ik := side.ik as TwoBoneIK
	if not _is_relaxed(ik) or _arm_swing() == null:
		return
	var angle := _free_swing.right_angle if ik == ik_right else _free_swing.left_angle
	if absf(angle) < 0.00001:
		return
	var axis := torso.global_basis.x.normalized()
	ik.root_joint.global_basis = (Basis(axis, angle) * ik.root_joint.global_basis).orthonormalized()


## Clip arm swing (user request 2026-10-18): a relaxed arm, posed at its hang, takes the clip's upper arm,
## forearm and wrist turns, blended by FreeArmSwing.amount, with the clip's twist and turn out. Then it
## keeps off the legs and the body (_keep_off) and the joint nodes follow the bones.
func _clip_swing(side: Dictionary, right: bool) -> void:
	var ik := side.ik as TwoBoneIK
	if not _is_relaxed(ik) or _arm_swing() == null or _free_swing.amount <= 0.0 or _free_swing.clip == null:
		side.swing_out = 0.0
		return
	var amount := _free_swing.amount
	var legs := _leg_segments()
	# The clip may come no nearer the legs and the body than the hang pose already is.
	var hang := _arm_distances(side, legs)
	var leg_limit := minf(swing_leg_clearance, hang.x)
	var body_limit := minf(swing_body_clearance, hang.y)
	for bone: int in [side.upper, side.fore, side.hand]:
		if bone < 0:
			continue
		var now := _skeleton.get_bone_pose_rotation(bone)
		var clip := _free_swing.arm_rotation(StringName(_skeleton.get_bone_name(bone)), now, right)
		_skeleton.set_bone_pose_rotation(bone, now.slerp(clip, amount))
	_turn_upper(side, right, deg_to_rad(clip_out_deg) * amount)
	_turn_forearm(side, right, deg_to_rad(clip_forearm_out_deg) * amount)
	_keep_off(side, right, legs, leg_limit, body_limit)
	_joints_from_bones(side)


## Turns the upper arm out to the side (the forearm and the hand go with it) about the torso's forward
## axis at the shoulder.
func _turn_upper(side: Dictionary, right: bool, out: float) -> void:
	if absf(out) < 0.00001:
		return
	var upper: int = side.upper
	var upper_pose := _skeleton.get_bone_global_pose(upper).orthonormalized()
	var turn := Basis(_torso_back_axis(), out * (1.0 if right else -1.0))
	var parent_pose := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(upper))
	_skeleton.set_bone_pose_rotation(upper, (parent_pose.basis.orthonormalized().inverse() * (turn * upper_pose.basis)).get_rotation_quaternion())


## Turns the forearm (the hand goes with it) about the torso's up axis at the elbow: + = a forward forearm
## points more to the outside.
func _turn_forearm(side: Dictionary, right: bool, out: float) -> void:
	if absf(out) < 0.00001:
		return
	var fore: int = side.fore
	var fore_pose := _skeleton.get_bone_global_pose(fore).orthonormalized()
	var torso_basis := _skeleton.global_transform.basis.orthonormalized().inverse() * torso.global_basis.orthonormalized()
	# About +Y a forward (-Z) direction turns to -X: the right arm (out = +X) turns by the minus angle.
	var turn := Basis((torso_basis * Vector3.UP).normalized(), -out * (1.0 if right else -1.0))
	var upper_pose := _skeleton.get_bone_global_pose(side.upper as int).orthonormalized()
	_skeleton.set_bone_pose_rotation(fore, (upper_pose.basis.inverse() * (turn * fore_pose.basis)).get_rotation_quaternion())


## The torso's back axis in skeleton space (a turn about it moves a hanging right arm to +X, out).
func _torso_back_axis() -> Vector3:
	var torso_basis := _skeleton.global_transform.basis.orthonormalized().inverse() * torso.global_basis.orthonormalized()
	return (torso_basis * Vector3.BACK).normalized()


## Nearest distances (m) of the palm (grip bone) and the wrist (hand bone): x to the leg bone lines, y to
## the torso and pelvis armor boxes (below 0 inside one).
func _arm_distances(side: Dictionary, legs: Array) -> Vector2:
	var skin := _skeleton.global_transform
	var nearest := Vector2(INF, INF)
	for bone: int in [side.grip, side.hand]:
		if bone >= 0:
			var point := _skeleton.get_bone_global_pose(bone).origin
			nearest.x = minf(nearest.x, _leg_distance(skin * point, legs))
			nearest.y = minf(nearest.y, _body_distance(point))
	return nearest


## Distance (m) of a point (skeleton space) to the nearest armor box (below 0: that deep inside).
func _body_distance(point: Vector3) -> float:
	var nearest := INF
	for entry: Array in _body_boxes:
		var local := _skeleton.get_bone_global_pose(entry[0] as int).orthonormalized().affine_inverse() * point
		var box := entry[1] as AABB
		var half := box.size * 0.5
		var away := (local - box.get_center()).abs() - half
		var outside := Vector3(maxf(away.x, 0.0), maxf(away.y, 0.0), maxf(away.z, 0.0)).length()
		nearest = minf(nearest, outside if outside > 0.0 else maxf(away.x, maxf(away.y, away.z)))
	return nearest


## Where the palm or the wrist is nearer the legs than leg_limit or the body than body_limit, the upper arm
## turns further out to the side (about the torso's forward axis at the shoulder) by the smallest angle
## that clears, up to swing_max_out_deg, changing at most swing_out_speed_deg per second.
func _keep_off(side: Dictionary, right: bool, legs: Array, leg_limit: float, body_limit: float) -> void:
	var skin := _skeleton.global_transform
	var upper_pose := _skeleton.get_bone_global_pose(side.upper as int)
	var shoulder := upper_pose.origin
	var points: Array[Vector3] = []
	for bone: int in [side.grip, side.hand]:
		if bone >= 0:
			points.append(_skeleton.get_bone_global_pose(bone).origin)
	var axis := _torso_back_axis()
	var out_sign := 1.0 if right else -1.0
	var clear := func(angle: float) -> bool:
		var turn := Basis(axis, angle * out_sign)
		for point in points:
			var moved := shoulder + turn * (point - shoulder)
			if _leg_distance(skin * moved, legs) < leg_limit - 0.001 or _body_distance(moved) < body_limit - 0.001:
				return false
		return true
	var wanted := 0.0
	if not clear.call(0.0):
		var low := 0.0
		var high := deg_to_rad(swing_max_out_deg)
		if clear.call(high):
			for i in 10:
				var middle := (low + high) * 0.5
				if clear.call(middle):
					high = middle
				else:
					low = middle
		wanted = high
	var step := deg_to_rad(swing_out_speed_deg) * _delta
	var last := float(side.get("swing_out", 0.0))
	var angle := clampf(wanted, last - step, last + step)
	side.swing_out = angle
	if angle > 0.0:
		_turn_upper(side, right, angle)


## The lower raise fades in with the ground speed (on the ground, not fallen).
func _update_raise_amount(delta: float) -> void:
	var mech := weapons.mech if weapons != null else null
	var target := 0.0
	if mech != null and mech.is_on_floor() and not mech.is_fallen and not mech.is_wrecked:
		target = smoothstep(0.0, 1.0, clampf(mech.get_horizontal_speed() / maxf(moving_raise_speed, 0.01), 0.0, 1.0))
	_raise_amount = move_toward(_raise_amount, target, moving_raise_blend * delta)


## An arm that follows the animation: its upper arm turns toward the body (about the torso's forward
## axis, its forward swing stays) so it keeps moving_raise_scale of the clip's raise to the side. The
## forearm and the hand go with it. Where the palm or the held weapon would come within the clearance of
## a leg, it lowers only as far as it may.
func _lower_raise(side: Dictionary, right: bool) -> void:
	var wanted := (1.0 - moving_raise_scale) * _raise_amount
	if wanted <= 0.0:
		side.raise_part = 0.0
		return
	var upper: int = side.upper
	var upper_pose := _skeleton.get_bone_global_pose(upper)
	var shoulder := upper_pose.origin
	var arm := _skeleton.get_bone_global_pose(side.fore as int).origin - shoulder
	if arm.length_squared() < 0.000001:
		return
	arm = arm.normalized()
	var skin := _skeleton.global_transform
	var torso_basis := skin.basis.orthonormalized().inverse() * torso.global_basis.orthonormalized()
	var local := torso_basis.inverse() * arm
	var out_sign := 1.0 if right else -1.0
	var raise := asin(clampf(local.x * out_sign, -1.0, 1.0))
	var sagittal := Vector3(0.0, local.y, local.z)
	if raise <= 0.0 or sagittal.length_squared() < 0.000001:
		side.raise_part = 0.0
		return
	sagittal = sagittal.normalized()
	# Points that must keep off the legs (skeleton space): the palm, and along a held melee weapon's
	# handle (from its butt behind the hand) to its head.
	var palm := _skeleton.get_bone_global_pose(side.grip as int).origin
	var points: Array = [[palm, leg_clearance]]
	var head := _weapon_head(right)
	if head != Vector3.INF:
		for t: float in [-weapon_butt_share, 0.35, 0.7]:
			points.append([palm.lerp(head, t), leg_clearance])
		points.append([head, weapon_head_clearance])
	var legs := _leg_segments()
	var turn_for := func(part: float) -> Basis:
		var lowered := raise * (1.0 - wanted * part)
		var direction := torso_basis * (sagittal * cos(lowered) + Vector3(out_sign * sin(lowered), 0.0, 0.0))
		return Basis(Quaternion(arm, direction.normalized()))
	# Each point keeps its clearance, or its distance in the clip pose where the clip is nearer already.
	var limits: Array[float] = []
	for entry: Array in points:
		limits.append(minf(float(entry[1]), _leg_distance(skin * (entry[0] as Vector3), legs)))
	var clear := func(part: float) -> bool:
		var turn: Basis = turn_for.call(part)
		for i in points.size():
			var point: Vector3 = skin * (shoulder + turn * ((points[i][0] as Vector3) - shoulder))
			if _leg_distance(point, legs) < limits[i] - 0.001:
				return false
		return true
	# The largest part of the wanted lowering that keeps the clearance.
	var allowed := 1.0
	if not clear.call(1.0):
		var low := 0.0
		var high := 1.0
		for i in 8:
			var middle := (low + high) * 0.5
			if clear.call(middle):
				low = middle
			else:
				high = middle
		allowed = low
	# Both ways at a limited speed (no pop): less quickly, more back slowly.
	var last := float(side.get("raise_part", 0.0))
	var part := clampf(allowed, last - raise_drop_speed * _delta, last + raise_recover_speed * _delta)
	side.raise_part = part
	if part <= 0.0:
		return
	var turned: Basis = turn_for.call(part) * upper_pose.basis
	var parent_pose := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(upper))
	_skeleton.set_bone_pose_rotation(upper, (parent_pose.basis.orthonormalized().inverse() * turned.orthonormalized()).get_rotation_quaternion())


## Shortest distance from a point (world space) to the leg bone lines.
static func _leg_distance(point: Vector3, legs: Array) -> float:
	var nearest := INF
	for segment: Array in legs:
		nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, segment[0], segment[1])))
	return nearest


## The leg bone lines (world space): thigh to shin and shin to foot of each leg.
func _leg_segments() -> Array:
	var skin := _skeleton.global_transform
	var segments: Array = []
	for i in range(0, leg_bones.size() - 2, 3):
		var joints: Array[Vector3] = []
		for j in 3:
			var bone := _skeleton.find_bone(leg_bones[i + j])
			if bone >= 0:
				joints.append(skin * _skeleton.get_bone_global_pose(bone).origin)
		for j in joints.size() - 1:
			segments.append([joints[j], joints[j + 1]])
	return segments


## The head (StrikePoint) of the melee weapon in this hand, in skeleton space at the hand's pose now, or
## Vector3.INF (no melee weapon).
func _weapon_head(right: bool) -> Vector3:
	if weapons == null:
		return Vector3.INF
	var weapon := weapons.right_weapon if right else weapons.left_weapon
	if weapon == null or not is_instance_valid(weapon) or not weapon is MeleeWeapon:
		return Vector3.INF
	var model := (weapon as MeleeWeapon).get_model()
	var point := model.get_node_or_null(^"StrikePoint") as Node3D if is_instance_valid(model) else null
	var holder := model.get_parent() as Node3D if point != null else null
	if holder == null:
		return Vector3.INF
	# The model sits on the hand bone (BoneAttachment3D): its place in the hand bone's space is fixed.
	var in_hand := holder.global_transform.affine_inverse() * point.global_position
	var hand := _skeleton.find_bone((weapon as MeleeWeapon).get_hand_bone())
	return _skeleton.get_bone_global_pose(hand) * in_hand if hand >= 0 else Vector3.INF


static func _joint_basis(start: Vector3, end: Vector3, across: Vector3) -> Basis:
	var y := (start - end).normalized()
	var x := (across - y * across.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


func _process_modification_with_delta(delta: float) -> void:
	_delta = delta
	if _skeleton == null:
		_setup()
	var skin := _skeleton.global_transform
	_aim_twist()
	_head_to_aim(delta)
	torso.global_transform = (skin * _skeleton.get_bone_global_pose(_skeleton.find_bone(torso_bone)).orthonormalized() \
			* _torso_offset).orthonormalized()
	# Jump and landing crouch: the weapon frame (weapons, shield, free hand places) lifts, so the thighs
	# coming up keep off the arms.
	_jump_lift()
	var active: Array[Dictionary] = []
	# A fist arm that the punch clip drives (no IK target) gets the hang pose under the clip: its target
	# is the hang marker only inside this solve, so SkeletalMeleeAnimation (after this node) still sees no
	# target and plays the clip on the arm (user report 2026-10-18: the hand snapped to the hang).
	var borrowed: Array[TwoBoneIK] = []
	for i in _sides.size():
		var side := _sides[i]
		var shoulder := side.shoulder as Node3D
		shoulder.global_position = skin * _skeleton.get_bone_global_pose(side.upper).origin
		var ik := side.ik as TwoBoneIK
		if ik.target == null and weapons != null:
			ik.target = weapons.fist_hang_target(i == 1)
			if ik.target != null:
				borrowed.append(ik)
		if ik.target != null and ik.can_process():
			active.append(side)
	var guarded := _guard_hands(active)
	_solve_arms(active)
	for side in active:
		_swing_relaxed(side)
		_pose_arm(side)
		_clip_swing(side, side.ik == ik_right)
	for ik: TwoBoneIK in guarded:
		ik.target = guarded[ik]
	for ik in borrowed:
		ik.target = null
	_update_raise_amount(delta)
	for i in _sides.size():
		if not active.has(_sides[i]):
			_lower_raise(_sides[i], i == 1)
	_follow_shoulders()
