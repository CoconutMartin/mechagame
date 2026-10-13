class_name MechHandControl
extends Node
## Drives the two jointed hands (MechHand, user request 2026-10-13) of a rigged mech from what each hand
## does: a gun's grip (the fingers fit around it), the left hand on a two-hand weapon (around the
## forestock), the shield or the pile bunker (a fist), or nothing (a fist while the mech moves, a relaxed
## open hand while it stands). It hides the old hand meshes, and a hand whose arm is destroyed.
## Grip sockets (user request 2026-10-13): a weapon's GripSocketRight / GripSocketLeft marker (grip
## center; +Y up the grip, +Z toward the butt, +X to the gun's right; metadata grip_radius) turns that
## hand by the smallest turn that lines its fist up with the grip (the grip's rake; at most
## max_wrist_bend_deg), about a point between the wrist and the fist hollow (pivot_on_fist), and the
## fingers fit the socket's grip. The arms keep their poses (the clean weapon holds): moving the arm to
## a fully turned hand put the stocks back into the forearm (up to 0.45 m). The left socket moves with
## the left hand marker (WeaponPose slides it between rest and aim). Without sockets: the old grips (the
## right fist hollow PALM_HOLLOW from grip_R, tools/mech_gen/arm_poses.py; the left grip at grip_L).

const PALM_HOLLOW := Vector3(0.2, 0.0, 0.18)
## The fist hollows in the hand frames (wrist origin, +Y to the fingers, +Z to the back of the hand),
## measured from the old hands.
const RIGHT_HOLLOW := Vector3(0.01, 0.70, -0.04)
const LEFT_HOLLOW := Vector3(-0.01, 0.58, -0.04)

@export var mech: Mech
@export var skeleton: Skeleton3D
@export var weapons: WeaponController
@export var health: MechHealth
@export var hitboxes: SkeletalHitboxes
@export var hand_right: MechHand
@export var hand_left: MechHand
## Grip cylinder radius (meters) without a socket: gun pistol grips, and the forestock.
@export var grip_radius: float = 0.12
@export var forestock_radius: float = 0.15
## Moving faster than this (m/s), a free hand makes a fist.
@export var fist_speed: float = 1.0
@export var grip_bones: PackedStringArray = ["grip_L", "grip_R"]
## How fast a hand turns to a socket and back (1 / seconds).
@export var socket_blend_speed: float = 5.0
## Largest hand turn to a socket (degrees).
@export var max_wrist_bend_deg: float = 30.0
## Turn pivot from the wrist (0) to the fist hollow (1): the wrist and the fist each move part of the way.
@export_range(0.0, 1.0) var pivot_on_fist: float = 1.0
## Part of the wrist gap the arm target closes each frame, and the largest target move (meters).
@export var reach_gain: float = 0.5
@export var max_reach_offset: float = 0.5
## Old hand meshes: meshes skinned to bones with these name starts are hidden.
@export var old_hand_bones: PackedStringArray = ["hand_", "index_", "middle_", "ring_", "pinky_", "thumb_", "grip_"]

## Per side: hand, base transform, socket weight, socket.
var _sides := {}


func _ready() -> void:
	_hide_old_hands.call_deferred()
	if health != null:
		health.part_destroyed.connect(_on_part_destroyed)
	for side in ["R", "L"]:
		var hand := hand_right if side == "R" else hand_left
		_sides[side] = {"hand": hand, "base": hand.transform if hand != null else Transform3D.IDENTITY,
				"weight": 0.0, "socket": null, "weapon": null, "target": null, "offset": Vector3.ZERO}
	if skeleton != null:
		skeleton.skeleton_updated.connect(_after_skeleton)


func _process(delta: float) -> void:
	if skeleton == null or weapons == null:
		return
	var moving := mech != null and Vector3(mech.velocity.x, 0.0, mech.velocity.z).length() > fist_speed
	var gun := weapons.right_weapon if weapons.right_weapon != null and is_instance_valid(weapons.right_weapon) else null
	var two_hand := gun != null and weapons.two_handed_left_grip()
	var socket_r := _socket(gun, ^"GripSocketRight")
	var socket_l := _socket(gun, ^"GripSocketLeft") if two_hand else null
	_update_side("R", socket_r, weapons.arm_ik_right, ^"GripRight", delta)
	_update_side("L", socket_l, weapons.arm_ik_left, ^"GripLeft", delta)
	if is_instance_valid(hand_right) and hand_right.visible:
		if socket_r != null:
			hand_right.set_grip(socket_r.global_position, socket_r.global_basis.y, _radius(socket_r, grip_radius))
		elif gun != null and not gun is PileBunkerWeapon:
			var grip := _grip_pose(grip_bones[1])
			hand_right.set_grip(grip * PALM_HOLLOW, grip.basis.y, grip_radius)
		elif gun != null:
			hand_right.mode = MechHand.Mode.FIST
		else:
			hand_right.mode = MechHand.Mode.FIST if moving else MechHand.Mode.RELAXED
	if is_instance_valid(hand_left) and hand_left.visible:
		if socket_l != null:
			var place := _left_socket_place(socket_l, gun)
			hand_left.set_grip(place.origin, place.basis.y, _radius(socket_l, forestock_radius))
		elif two_hand:
			var grip := _grip_pose(grip_bones[0])
			hand_left.set_grip(grip.origin, grip.basis.y, forestock_radius)
		elif weapons.left_data != null:
			hand_left.mode = MechHand.Mode.FIST
		else:
			hand_left.mode = MechHand.Mode.FIST if moving else MechHand.Mode.RELAXED


## The weapon's socket marker, or null (no weapon, or a weapon without sockets).
func _socket(weapon: Node3D, path: NodePath) -> Node3D:
	if weapon == null or not is_instance_valid(weapon):
		return null
	return weapon.get_node_or_null(path) as Node3D


func _radius(socket: Node3D, fallback: float) -> float:
	return float(socket.get_meta(&"grip_radius", fallback))


## The socket frame where the hand is now: the left socket moves with the left hand marker.
func _socket_place(side: String, socket: Node3D) -> Transform3D:
	if side == "L":
		return _left_socket_place(socket, weapons.right_weapon)
	return socket.global_transform.orthonormalized()


func _left_socket_place(socket: Node3D, weapon: Node3D) -> Transform3D:
	var place := socket.global_transform.orthonormalized()
	var marker := weapon.get_node_or_null(^"GripLeft") as Node3D if weapon != null else null
	var rest := weapon.get_node_or_null(^"GripLeftRest") as Node3D if weapon != null else null
	if marker != null and rest != null:
		place.origin += marker.global_position - rest.global_position
	return place


## A weapon with this side's socket: the arm reaches for a HandTarget node (a child of the weapon, so
## the arm rig still moves the weapon with a limited hand); the old marker comes back without one.
func _update_side(side: String, socket: Node3D, ik: TwoBoneIK, marker_path: NodePath, delta: float) -> void:
	var state: Dictionary = _sides[side]
	state.socket = socket
	state.weight = move_toward(state.weight, 1.0 if socket != null else 0.0, socket_blend_speed * delta)
	if ik == null:
		return
	var weapon := weapons.right_weapon
	var target := state.target as Node3D if is_instance_valid(state.target) else null
	var old_weapon := state.weapon as Node3D if is_instance_valid(state.weapon) else null
	if socket == null or not bool(socket.get_meta(&"hand_reach", true)):
		if target != null and ik.target == target and old_weapon != null:
			ik.target = old_weapon.get_node_or_null(marker_path) as Node3D
		state.weapon = null
		return
	if weapon != old_weapon:
		state.weapon = weapon
		state.offset = Vector3.ZERO
		target = weapon.get_node_or_null("HandTarget" + side) as Node3D
		if target == null:
			target = Node3D.new()
			target.name = "HandTarget" + side
			weapon.add_child(target)
		state.target = target
	var marker := weapon.get_node_or_null(marker_path) as Node3D
	if marker == null:
		return
	if ik.target == marker:
		ik.target = target
	if ik.target == target:
		target.position = marker.position + (state.offset as Vector3)


## After the arm rig: each hand turns to its socket's grip axis (blended, limited), about a point
## between its wrist and its fist hollow.
func _after_skeleton() -> void:
	for side: String in _sides:
		var state: Dictionary = _sides[side]
		var hand := state.hand as MechHand
		if not is_instance_valid(hand):
			continue
		var bone_pose := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side))
		var base: Transform3D = state.base
		var socket := state.socket as Node3D
		var weight: float = state.weight
		if socket == null or not is_instance_valid(socket) or weight <= 0.0:
			hand.transform = base
			continue
		var attached := (bone_pose * base).orthonormalized()
		var place := _socket_place(side, socket)
		# The fist runs along the hand's -X (right; index side) or +X (left).
		var fist := (attached.basis.x * (-1.0 if side == "R" else 1.0)).normalized()
		var axis := place.basis.y.normalized()
		var turn := Quaternion(fist, axis)
		var angle := turn.get_angle()
		var part := minf(1.0, deg_to_rad(max_wrist_bend_deg) / maxf(angle, 0.0001)) * smoothstep(0.0, 1.0, weight)
		var limited := Quaternion.IDENTITY.slerp(turn, part)
		var hollow := RIGHT_HOLLOW if side == "R" else LEFT_HOLLOW
		# hand_reach false (two-hand rifles): the arm keeps its pose; the hand only turns at the wrist.
		var reach := bool(socket.get_meta(&"hand_reach", true))
		var pivot := attached * (hollow * (pivot_on_fist if reach else 0.0))
		var rotation := Basis(limited)
		var now := Transform3D(rotation * attached.basis, pivot + rotation * (attached.origin - pivot))
		# Then the fist hollow onto the socket (blended in), so the fingers close on the real grip.
		if reach:
			now.origin += (place.origin - now * hollow) * smoothstep(0.0, 1.0, weight)
		hand.transform = bone_pose.affine_inverse() * now
		# The arm reaches by part of the gap between its wrist and the placed hand's wrist.
		var weapon := state.weapon as Node3D
		if reach and weapon != null and is_instance_valid(weapon):
			var local := weapon.global_basis.orthonormalized().inverse() * (now.origin - attached.origin)
			state.offset = ((state.offset as Vector3) + local * reach_gain).limit_length(max_reach_offset)


func _grip_pose(bone_name: StringName) -> Transform3D:
	var bone := skeleton.find_bone(bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone)


func _hide_old_hands() -> void:
	if hitboxes == null:
		return
	for mesh: MeshInstance3D in hitboxes.mesh_bones:
		var bone_name := String(skeleton.get_bone_name(hitboxes.mesh_bones[mesh]))
		for start in old_hand_bones:
			if bone_name.begins_with(start):
				mesh.visible = false
				break


func _on_part_destroyed(key: String) -> void:
	if key == "Arm R" and is_instance_valid(hand_right):
		hand_right.visible = false
	elif key == "Arm L" and is_instance_valid(hand_left):
		hand_left.visible = false
