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
@export var head_bone: StringName = &"head"
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

var _skeleton: Skeleton3D
var _torso_offset: Transform3D
var _sides: Array[Dictionary] = []
## Seconds since the last modification (the elbow speed limit).
var _delta: float = 1.0 / 60.0
## Shoulder mount place in its upper arm bone's space: [mount, bone, offset].
var _mount_offsets: Array = []
## The right weapon's transform from WeaponPose, and the moved one this rig set (the weapon moves to
## a limited hand; WeaponPose sets it again on its next physics frame).
var _weapon_base: Transform3D
var _weapon_moved: Transform3D


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
	var grip_track := _grip_rotations()
	for i in 2:
		var side := {}
		side.ik = ik_left if i == 0 else ik_right
		side.shoulder = shoulder_left if i == 0 else shoulder_right
		side.upper = _skeleton.find_bone(upper_arm_bones[i])
		side.fore = _skeleton.find_bone(forearm_bones[i])
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


## In the sniping stance the head turns back by the hip turn and the torso twist, so it looks along the
## aim (the user's reference: the head over the rifle).
func _head_to_aim() -> void:
	if stance == null or stance.amount <= 0.0:
		return
	var total := stance.applied_turn
	if weapon_pose != null and torso_pose != null and weapon_pose.weapon != null:
		total -= deg_to_rad(torso_pose.aim_twist_deg) * smoothstep(0.0, 1.0, weapon_pose.aim_amount)
	var head := _skeleton.find_bone(head_bone)
	if head < 0:
		return
	var up := (_skeleton.global_basis.inverse() * Vector3.UP).normalized()
	var pose := _skeleton.get_bone_global_pose(head).orthonormalized()
	var parent := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(head)).orthonormalized()
	var turned := Basis(up, -total) * pose.basis
	_skeleton.set_bone_pose_rotation(head, (parent.basis.inverse() * turned).get_rotation_quaternion())


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
	if weapons == null or ik.target != weapons.free_left_hand:
		for bone: int in side.fingers:
			_skeleton.set_bone_pose_rotation(bone, side.fingers[bone])
	shoulder.global_basis = (skin.basis.orthonormalized() * upper_basis * (side.upper_offset as Basis).inverse()).orthonormalized()
	ik.mid_joint.global_basis = (skin.basis.orthonormalized() * fore_basis * (side.fore_offset as Basis).inverse()).orthonormalized()


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
		_restore_weapon()
		right_ik.solve()
		_tuck_elbow(right_ik)
		_limit_swing(right_ik, swing_limit(true))
		_move_weapon_to_hand(right_ik)
	if left_ik == null:
		return
	left_ik.solve()
	_tuck_elbow(left_ik)
	_limit_swing(left_ik, swing_limit(false))
	var weapon := weapons.right_weapon if weapons != null else null
	if right_ik == null or weapon == null or not weapon.is_ancestor_of(left_ik.target):
		return
	var gap := _hand(left_ik) - left_ik.target.global_position
	if gap.length_squared() < 0.0001:
		return
	weapon.global_position += gap
	_weapon_moved = weapon.transform
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
	var aim := smoothstep(0.0, 1.0, weapon_pose.aim_amount) if weapon_pose != null else 0.0
	return deg_to_rad(max_block_yaw_deg) * (1.0 - aim)


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


func _restore_weapon() -> void:
	var weapon := weapons.right_weapon if weapons != null else null
	if weapon == null:
		return
	if not weapon.transform.is_equal_approx(_weapon_moved):
		_weapon_base = weapon.transform
	weapon.transform = _weapon_base


## A limited right hand does not reach the grip: the weapon moves so its grip is in the hand.
func _move_weapon_to_hand(ik: TwoBoneIK) -> void:
	var weapon := weapons.right_weapon if weapons != null else null
	if weapon == null or not weapon.is_ancestor_of(ik.target):
		return
	var gap := _hand(ik) - ik.target.global_position
	if gap.length_squared() > 0.000001:
		weapon.global_position += gap
	_weapon_moved = weapon.transform


## The way through a closed fist (index to pinky), in the elbow joint node's space (Vector3.ZERO
## before the first frame).
func hand_across(right: bool) -> Vector3:
	return _sides[1 if right else 0].hand_across if _sides.size() == 2 else Vector3.ZERO


## Shoulder mounts follow their upper arm bones (after the arm bones got their final turn).
func _follow_shoulders() -> void:
	var skin := _skeleton.global_transform
	for entry: Array in _mount_offsets:
		var bone: int = entry[1]
		(entry[0] as Node3D).global_transform = (skin * _skeleton.get_bone_global_pose(bone).orthonormalized() \
				* (entry[2] as Transform3D)).orthonormalized()


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
	_head_to_aim()
	torso.global_transform = (skin * _skeleton.get_bone_global_pose(_skeleton.find_bone(torso_bone)).orthonormalized() \
			* _torso_offset).orthonormalized()
	var active: Array[Dictionary] = []
	for side: Dictionary in _sides:
		var shoulder := side.shoulder as Node3D
		shoulder.global_position = skin * _skeleton.get_bone_global_pose(side.upper).origin
		var ik := side.ik as TwoBoneIK
		if ik.target != null and ik.can_process():
			active.append(side)
	_solve_arms(active)
	for side in active:
		_pose_arm(side)
	_follow_shoulders()
