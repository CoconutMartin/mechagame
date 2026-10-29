class_name MechHandControl
extends Node
## Drives the two jointed hands (MechHand, user request 2026-10-13) of a rigged mech from what each hand
## does: a gun's grip (the fingers fit around it), the left hand on a two-hand weapon (around the
## forestock), the shield or the pile bunker (a fist), or nothing (a fist while the mech moves, a relaxed
## open hand while it stands). It hides the old hand meshes, and a hand whose arm is destroyed.
## Grip sockets (user request 2026-10-13): a weapon's GripSocketRight / GripSocketLeft marker (grip
## center; +Y up the grip, +Z toward the butt, +X to the gun's right; metadata grip_radius) turns that
## hand so its fist lines up with the grip: a roll about the forearm line (at most max_wrist_twist_deg),
## then a bend (at most max_wrist_bend_deg). With hand_reach the fist hollow goes onto the socket and the
## arm reaches the rest of the way (a HandTarget node). The two-hand rifles' hand markers sit where the
## fist lands on the sockets, so their reach stays near 0; GripSocketLeftAim (optional) is the left
## socket of the aim hold (the hand slides between the two with the left hand marker), and
## GripSocketLeftAimLow (optional, with GripLeftAimLow) the socket of the low aim hold (WeaponPose
## low_aim_amount). Without sockets: the old grips (the right fist hollow PALM_HOLLOW from grip_R,
## tools/mech_gen/arm_poses.py; the left grip at grip_L).
## Wrist (user report 2026-10-24: "hand and arms are still disjointed at the wrist"): the hand model's own
## wrist joint (the roller on the back of the hand block, MechHand.wrist_local) stays on the forearm's wrist
## pin (the dark joint at the end of the forearm armor; its center is wrist_pin_right / wrist_pin_left in the
## forearm bone frame, written by build_sanggigilid.gd) in every pose, and a turning hand turns about it.
## The arm, not the hand, makes up the rest of the way to a grip (the HandTarget).

const PALM_HOLLOW := Vector3(0.2, 0.0, 0.18)
## The fist hollows in the hand frames (wrist origin, +Y to the fingers, +Z to the back of the hand),
## measured from the old hands.
const RIGHT_HOLLOW := Vector3(0.01, 0.70, -0.04)
const LEFT_HOLLOW := Vector3(-0.01, 0.58, -0.04)
## The palm face (hand frame Z): a grip of radius r sits with its center r in front of it, so thick
## grips do not fill the knuckles (the hollows above fit a 0.11 m grip).
const PALM_FACE_Z := 0.07

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
## Handle radius (meters) of a forearm gun (Auto Cannon): its model's Grip marker is the grip socket.
@export var handle_radius: float = 0.11
## Moving faster than this (m/s), a free hand makes a fist.
@export var fist_speed: float = 1.0
@export var grip_bones: PackedStringArray = ["grip_L", "grip_R"]
## How fast a hand turns to a socket and back (1 / seconds).
@export var socket_blend_speed: float = 5.0
## Largest hand roll about the forearm line (degrees; the roller wrist) and largest bend off that line
## (degrees) to line the fist up with a socket's grip.
@export var max_wrist_twist_deg: float = 150.0
@export var max_wrist_bend_deg: float = 60.0
## Wrist pin center (meters) in the forearm bone frame at rest: the dark joint at the end of the forearm
## armor. build_sanggigilid.gd writes both (the forearm mesh's end, measured from the model).
@export var wrist_pin_right: Vector3 = Vector3.ZERO
@export var wrist_pin_left: Vector3 = Vector3.ZERO
## How far build_sanggigilid.gd moved each hand model on its hand bone to put the wrist joint on the pin (meters,
## in the hand bone frame). A melee weapon sits on the hand bone, so its model moves by the same amount.
@export var hand_shift_right: Vector3 = Vector3.ZERO
@export var hand_shift_left: Vector3 = Vector3.ZERO
## Part of the miss between the fist hollow and the grip that the arm target closes each frame (once per frame,
## also when the skeleton updates more than once), and the largest target move (meters). 0.3 since the hinge
## arms (user report 2026-10-24: the rifle and the left fingers twitched in ADS): at 0.7 and 0.4 the reach
## overshot and swung back every frame (the hinge forearm turns a lot for a small target move).
@export var reach_gain: float = 0.3
@export var max_reach_offset: float = 1.0
## reach_gain is the part closed per frame at this frame rate; at other rates the part per frame is scaled so the
## reach takes the same time (user report 2026-10-24, round 2: the right forearm twitched fast in ADS and charged
## firing; at 144 fps the plain 0.3 per frame overshot and the elbow turn swung 0.5 deg every frame).
@export var reach_gain_fps: float = 60.0
## Soft dead band (meters): a fist miss shorter than this closes slower (smoothstep), so the reach comes to rest
## instead of swinging about the grip by tiny steps. 0 = off.
@export var reach_dead_band: float = 0.01
## A gun held without arm reach: the wrist turns for the other direction of the grip axis when that puts the
## fist hollow nearer the grip by more than this (meters).
@export var flip_margin: float = 0.05
## Old hand meshes: meshes skinned to bones with these name starts are hidden.
@export var old_hand_bones: PackedStringArray = ["hand_", "index_", "middle_", "ring_", "pinky_", "thumb_", "grip_"]

## Per side: hand, base transform, socket weight, socket.
var _sides := {}
## Process frame of the last reach step per side (the reach closes once per frame).
var _reach_frame := {}
## Per side: the stand-in socket node of an old-style hold (see _stand_in).
var _stand_ins := {}


func _ready() -> void:
	_hide_old_hands.call_deferred()
	if health != null:
		health.part_destroyed.connect(_on_part_destroyed)
	for side in ["R", "L"]:
		var hand := hand_right if side == "R" else hand_left
		_sides[side] = {"hand": hand, "base": hand.transform if hand != null else Transform3D.IDENTITY,
				"wrist": hand.wrist_local() if hand != null else Vector3.ZERO, "weight": 0.0, "socket": null, "weapon": null, "target": null, "offset": Vector3.ZERO}
	if skeleton != null:
		skeleton.skeleton_updated.connect(_after_skeleton)


func _process(delta: float) -> void:
	if skeleton == null or weapons == null:
		return
	var moving := mech != null and Vector3(mech.velocity.x, 0.0, mech.velocity.z).length() > fist_speed
	# A fist in the right hand is no gun: the hand makes a fist (user rule 2026-10-17: empty hands hold fists).
	var fist_right := weapons.right_weapon is MeleeWeapon and weapons.right_data != null \
			and weapons.right_data.kind == WeaponData.Kind.FIST
	var punching := weapons.is_punching()
	# A Pile Bunker on either arm: both hands stay closed (user request 2026-10-29).
	var bunker := weapons.right_weapon is PileBunkerWeapon or weapons.left_weapon is PileBunkerWeapon
	var gun := weapons.right_weapon if weapons.right_weapon != null and is_instance_valid(weapons.right_weapon) \
			and not fist_right else null
	var two_hand := gun != null and weapons.two_handed_left_grip()
	var socket_r := _socket(gun, ^"GripSocketRight")
	if socket_r == null and gun != null and not gun is PileBunkerWeapon:
		socket_r = _handle_socket(gun)
	# A melee weapon or the pile bunker has no socket marker: a stand-in at its grip marker gives the hand the same
	# reach (the wrist stays on the pin, the arm brings the fist to the weapon's grip).
	if socket_r == null and gun != null:
		socket_r = _stand_in("R", gun, ^"GripRight")
	_move_melee_model(gun, hand_shift_right)
	var melee_left := weapons.left_weapon if weapons.left_weapon is MeleeWeapon and is_instance_valid(weapons.left_weapon) \
			and weapons.left_data != null and weapons.left_data.kind != WeaponData.Kind.FIST else null
	# A one-hand gun in the left hand (user rule 2026-10-15): its GripSocketRight fits the left fist too.
	var left_gun := weapons.left_weapon if weapons.left_weapon != null and is_instance_valid(weapons.left_weapon) \
			and not weapons.left_weapon is MeleeWeapon else null
	var socket_l := _socket(gun, ^"GripSocketLeft") if two_hand else _socket(left_gun, ^"GripSocketRight")
	_update_side("R", socket_r, weapons.arm_ik_right, ^"GripRight", gun, delta)
	_move_melee_model(melee_left, hand_shift_left)
	if socket_l == null and melee_left != null:
		socket_l = _stand_in("L", melee_left, ^"GripLeft")
	_update_side("L", socket_l, weapons.arm_ik_left, ^"GripLeft", gun if two_hand else (left_gun if left_gun != null else melee_left), delta)
	if is_instance_valid(hand_right) and hand_right.visible:
		if socket_r != null and not gun is PileBunkerWeapon:
			hand_right.set_grip(socket_r.global_position, socket_r.global_basis.y, _radius(socket_r, grip_radius))
		elif gun != null and not gun is PileBunkerWeapon:
			var grip := _grip_pose(grip_bones[1])
			hand_right.set_grip(grip * PALM_HOLLOW, grip.basis.y, grip_radius)
		elif gun != null:
			hand_right.mode = MechHand.Mode.FIST
		else:
			# An empty hand (it holds a Fist weapon without a model): the jointed hand makes the fist for a
			# punch and while the mech moves; at rest it stays relaxed (user report 2026-10-22).
			hand_right.mode = MechHand.Mode.FIST if moving or punching or bunker else MechHand.Mode.RELAXED
	if is_instance_valid(hand_left) and hand_left.visible:
		if socket_l != null and melee_left == null:
			var place := _left_socket_place(socket_l, gun) if two_hand else socket_l.global_transform.orthonormalized()
			hand_left.set_grip(place.origin, place.basis.y, _radius(socket_l, forestock_radius))
		elif two_hand:
			var grip := _grip_pose(grip_bones[0])
			hand_left.set_grip(grip.origin, grip.basis.y, forestock_radius)
		elif weapons.left_data != null and weapons.left_data.kind != WeaponData.Kind.FIST:
			hand_left.mode = MechHand.Mode.FIST
		else:
			hand_left.mode = MechHand.Mode.FIST if moving or punching or bunker else MechHand.Mode.RELAXED


## A melee weapon's model sits on the hand bone, placed for the old hand (on the bone). The jointed hand sits
## `shift` away from there (its wrist joint is on the pin), so the model moves by the same amount, once.
func _move_melee_model(weapon: Node3D, shift: Vector3) -> void:
	if not weapon is MeleeWeapon:
		return
	var model := (weapon as MeleeWeapon).get_model()
	if not is_instance_valid(model) or model.has_meta(&"wrist_shifted") or not model.get_parent() is BoneAttachment3D:
		return
	model.position += shift
	model.set_meta(&"wrist_shifted", true)


## Stand-in socket of an old-style hold (a melee weapon, the pile bunker; no socket marker): at the weapon's grip
## marker plus the fist offset the old grip code used (PALM_HOLLOW in the grip bone's frame, mirrored for the left
## hand). Null when the weapon has no such marker.
func _stand_in(side: String, weapon: Node3D, marker_path: NodePath) -> Node3D:
	var marker := weapon.get_node_or_null(marker_path) as Node3D
	if marker == null:
		return null
	var node := _stand_ins.get(side) as Node3D if is_instance_valid(_stand_ins.get(side)) else null
	if node == null:
		node = Node3D.new()
		node.name = "StandIn" + side
		# The old hold never turned the hand: it keeps the arm rig's pose, and only the reach moves.
		node.set_meta(&"keep_turn", true)
		add_child(node)
		_stand_ins[side] = node
	var bone := _grip_pose(grip_bones[1 if side == "R" else 0])
	var offset := PALM_HOLLOW if side == "R" else Vector3(-PALM_HOLLOW.x, PALM_HOLLOW.y, PALM_HOLLOW.z)
	node.global_transform = Transform3D(bone.basis.orthonormalized(), marker.global_position + bone.basis * offset)
	return node


## The weapon's socket marker, or null (no weapon, or a weapon without sockets).
func _socket(weapon: Node3D, path: NodePath) -> Node3D:
	if weapon == null or not is_instance_valid(weapon):
		return null
	return weapon.get_node_or_null(path) as Node3D


## A forearm gun (Auto Cannon) has no socket marker on its root (its model moves to the forearm): the
## Grip marker of its model is the right socket (+Y along the handle). The arm keeps its pose and the
## hand turns at the wrist, so the fist lines up with the handle and the thumb can wrap it (user
## request 2026-10-22).
func _handle_socket(weapon: Node3D) -> Node3D:
	if not weapon.has_method(&"get_model"):
		return null
	var model: Node3D = weapon.call(&"get_model")
	var grip := model.get_node_or_null(^"Model/Grip") as Node3D if model != null else null
	if grip != null and not grip.has_meta(&"grip_radius"):
		grip.set_meta(&"grip_radius", handle_radius)
		grip.set_meta(&"hand_reach", false)
	return grip


func _radius(socket: Node3D, fallback: float) -> float:
	return float(socket.get_meta(&"grip_radius", fallback))


## The socket frame where the hand is now: the left socket moves with the left hand marker.
func _socket_place(side: String, socket: Node3D) -> Transform3D:
	if side == "L" and weapons.two_handed_left_grip():
		return _left_socket_place(socket, weapons.right_weapon)
	return socket.global_transform.orthonormalized()


func _left_socket_place(socket: Node3D, weapon: Node3D) -> Transform3D:
	var place := socket.global_transform.orthonormalized()
	var marker := weapon.get_node_or_null(^"GripLeft") as Node3D if weapon != null else null
	var rest := weapon.get_node_or_null(^"GripLeftRest") as Node3D if weapon != null else null
	var aim := weapon.get_node_or_null(^"GripLeftAim") as Node3D if weapon != null else null
	if marker == null or rest == null:
		return place
	# GripSocketLeftAim (optional): the socket of the aim hold; the hand slides between the two.
	var socket_aim := weapon.get_node_or_null(^"GripSocketLeftAim") as Node3D
	if socket_aim != null and aim != null:
		var aim_place := socket_aim.global_transform.orthonormalized()
		var aim_position := aim.position
		# Low aim (WeaponPose.low_aim_amount): the aim hold slides back to GripLeftAimLow and
		# GripSocketLeftAimLow, so the socket follows the marker.
		var aim_low := weapon.get_node_or_null(^"GripLeftAimLow") as Node3D
		var socket_low := weapon.get_node_or_null(^"GripSocketLeftAimLow") as Node3D
		var low := weapons.weapon_pose.low_aim_amount if weapons.weapon_pose != null else 0.0
		if aim_low != null and socket_low != null and low > 0.0:
			aim_place = aim_place.interpolate_with(socket_low.global_transform.orthonormalized(), low)
			aim_position = aim_position.lerp(aim_low.position, low)
		var way := aim_position - rest.position
		var t := clampf((marker.position - rest.position).dot(way) / maxf(way.length_squared(), 0.000001), 0.0, 1.0)
		return place.interpolate_with(aim_place, t)
	place.origin += marker.global_position - rest.global_position
	return place


## A weapon with this side's socket: the arm reaches for a HandTarget node (a child of the weapon, so
## the arm rig still moves the weapon with a limited hand); the old marker comes back without one.
func _update_side(side: String, socket: Node3D, ik: TwoBoneIK, marker_path: NodePath, weapon: Node3D, delta: float) -> void:
	var state: Dictionary = _sides[side]
	state.socket = socket
	state.weight = move_toward(state.weight, 1.0 if socket != null else 0.0, socket_blend_speed * delta)
	if ik == null:
		return
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


## After the arm rig: the hand's wrist joint goes on the wrist pin; a hand on a socket turns (blended,
## limited) about that joint so its fist lines up with the grip axis, and the arm target moves by part of
## the fist's miss, so the fist comes onto the grip without the wrist leaving the pin.
func _after_skeleton() -> void:
	for side: String in _sides:
		var state: Dictionary = _sides[side]
		# Check before each cast: casting a freed node (a broken arm or weapon) is an error.
		if not is_instance_valid(state.hand):
			continue
		var hand := state.hand as MechHand
		var bone_pose := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side))
		var pin := wrist_pin(side)
		var wrist: Vector3 = state.wrist
		var base: Transform3D = state.base
		var socket: Node3D = state.socket as Node3D if is_instance_valid(state.socket) else null
		var weight: float = state.weight
		var attached := (bone_pose * base).orthonormalized()
		# The hand model rides on the hand bone; the wrist joint goes onto the pin (the forearm's end).
		attached.origin += pin - attached * wrist
		if socket == null or weight <= 0.0:
			hand.transform = bone_pose.affine_inverse() * attached
			continue
		var place := _socket_place(side, socket)
		var hollow := RIGHT_HOLLOW if side == "R" else LEFT_HOLLOW
		hollow.z = PALM_FACE_Z - _radius(socket, grip_radius)
		# Socket metadata hold_drop (meters): the hand sits this much lower on the grip, so the thumb mount and
		# the thumb clear the gun body (the hollow point is higher on the hand: index side for the right hand).
		hollow.x += float(socket.get_meta(&"hold_drop", 0.0)) * (-1.0 if side == "R" else 1.0)
		var reach := bool(socket.get_meta(&"hand_reach", true))
		var axis := place.basis.y.normalized()
		var turn := _wrist_turn(attached, side, axis) if not bool(socket.get_meta(&"keep_turn", false)) else Quaternion.IDENTITY
		if not reach:
			# The arm keeps its pose, so the turn decides where the grip lies in the hand: a grip axis has two
			# directions, and the turn for the one that brings the fist hollow nearer the grip wins.
			turn = _spin_to_grip(attached, wrist, turn, hollow, place.origin, axis)
			var other := _spin_to_grip(attached, wrist, _wrist_turn(attached, side, -axis), hollow, place.origin, axis)
			var gap := _hollow_gap(attached, wrist, turn, hollow, place.origin)
			var gap_other := _hollow_gap(attached, wrist, other, hollow, place.origin)
			var flipped := bool(state.get("flip", false))
			if gap_other + (0.0 if flipped else flip_margin) < gap or (flipped and gap_other < gap + flip_margin):
				turn = other
				flipped = true
			else:
				flipped = false
			state["flip"] = flipped
		var rotation := Basis(turn.slerp(Quaternion.IDENTITY, 1.0 - smoothstep(0.0, 1.0, weight)))
		# The hand turns about its wrist joint, which stays on the pin.
		var now := Transform3D(rotation * attached.basis, pin + rotation * (attached.origin - pin))
		hand.transform = bone_pose.affine_inverse() * now
		# The arm reaches by part of the fist's miss (the hollow to the grip center).
		var weapon: Node3D = state.weapon as Node3D if is_instance_valid(state.weapon) else null
		if reach and weapon != null and _reach_frame.get(side, -1) != Engine.get_process_frames():
			_reach_frame[side] = Engine.get_process_frames()
			var miss := (place.origin - now * hollow) * smoothstep(0.0, 1.0, weight)
			var local := weapon.global_basis.orthonormalized().inverse() * miss
			var gain := 1.0 - pow(1.0 - clampf(reach_gain, 0.0, 1.0), get_process_delta_time() * reach_gain_fps)
			# Soft dead band: a small miss closes slower, so the reach settles without steps.
			gain *= smoothstep(0.0, reach_dead_band, miss.length()) if reach_dead_band > 0.0 else 1.0
			state.offset = ((state.offset as Vector3) + local * gain).limit_length(max_reach_offset)


## World center of the forearm's wrist pin this frame (call it when the skeleton has its final pose).
func wrist_pin(side: String) -> Vector3:
	var forearm := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("forearm_" + side))
	return forearm * (wrist_pin_right if side == "R" else wrist_pin_left)


## A hand whose arm cannot reach (the arm keeps its pose) also turns about the grip axis through its wrist, so
## the fist hollow points at the grip: the fist stays lined up and the miss gets smaller. Limited by the wrist
## bend (the spin shrinks until the bend fits).
func _spin_to_grip(attached: Transform3D, wrist: Vector3, turn: Quaternion, hollow: Vector3, center: Vector3,
		axis: Vector3) -> Quaternion:
	var line := axis.normalized()
	var to_fist := Basis(turn) * (attached.basis * (hollow - wrist))
	var to_grip := center - attached * wrist
	var fist_flat := to_fist - line * to_fist.dot(line)
	var grip_flat := to_grip - line * to_grip.dot(line)
	if fist_flat.length_squared() < 0.0001 or grip_flat.length_squared() < 0.0001:
		return turn
	var angle := fist_flat.signed_angle_to(grip_flat, line)
	var forearm_line := attached.basis.y.normalized()
	for i in 5:
		var spun := Quaternion(line, angle) * turn
		if (Basis(spun) * forearm_line).angle_to(forearm_line) <= deg_to_rad(max_wrist_bend_deg):
			return spun
		angle *= 0.5
	return turn


## Distance from the fist hollow to a grip center when the hand turns by this wrist turn about its wrist joint
## (which sits on the pin).
func _hollow_gap(attached: Transform3D, wrist: Vector3, turn: Quaternion, hollow: Vector3, center: Vector3) -> float:
	var pivot := attached * wrist
	return (pivot + Basis(turn) * (attached.basis * (hollow - wrist))).distance_to(center)


## The wrist turn (world) that lines the fist up with a grip axis: first a roll about the forearm line
## (the hand's +Y), then a bend off it, each limited.
func _wrist_turn(attached: Transform3D, side: String, axis: Vector3) -> Quaternion:
	# The fist runs along the hand's -X (right; index side) or +X (left).
	var fist := (attached.basis.x * (-1.0 if side == "R" else 1.0)).normalized()
	var line := attached.basis.y.normalized()
	var flat_fist := fist - line * fist.dot(line)
	var flat_axis := axis - line * axis.dot(line)
	var roll := Quaternion.IDENTITY
	if flat_axis.length_squared() > 0.0001:
		var angle := flat_fist.signed_angle_to(flat_axis, line)
		var limit := deg_to_rad(max_wrist_twist_deg)
		roll = Quaternion(line, clampf(angle, -limit, limit))
	var rolled := roll * fist
	var bend := Quaternion(rolled, axis)
	var part := minf(1.0, deg_to_rad(max_wrist_bend_deg) / maxf(bend.get_angle(), 0.0001))
	return Quaternion.IDENTITY.slerp(bend, part) * roll


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
	# The part breaker takes the hand off first (it falls with the arm); this hides a hand it left.
	if key == "Arm R" and is_instance_valid(hand_right):
		hand_right.visible = false
	elif key == "Arm L" and is_instance_valid(hand_left):
		hand_left.visible = false


## Lets go of a hand (its arm broke): this node stops driving it and returns it at its pose now, so
## it can fall with the arm. Null if the hand is gone.
func take_hand(side: String) -> MechHand:
	var hand := hand_right if side == "R" else hand_left
	if not is_instance_valid(hand):
		return null
	if side == "R":
		hand_right = null
	else:
		hand_left = null
	if _sides.has(side):
		_sides[side].hand = null
	hand.visible = true
	return hand
