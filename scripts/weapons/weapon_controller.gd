class_name WeaponController
extends Node
## Mounts the loadout weapons on the mech and sends the buttons to them.
## Right arm weapon: a model under the torso, posed by WeaponPose, held by the right hand.
##   One-hand gun: RMB raises and fires (hip fire). Blade: RMB lunge slash.
##   Two-hand weapon: RMB aims down sight (zoom), LMB fires. The left hand holds the weapon.
## Left arm: a shield (LMB lifts it), a fist, or (user rule 2026-10-15) a one-hand gun or the pile
## bunker: LMB uses it like RMB uses the right arm weapon. The left weapon has its own WeaponPose and
## WeaponRecoil (made here) and a left view of this controller (left_view) that its scripts use.
## Back units: missile pods, Q = left, E = right.
## Left arm lost with a two-hand weapon: the right hand holds it alone, low at the hip like the
## one-hand rifle, and the aim ring is unsteady (FreeAim.unsteady). The keys stay the same.
## Only one weapon works at a time: the first one whose button is pressed stays active until it is
## done (trigger released, missiles launched). The blade is the exception: it works any time.
## A knock-down face down (SkeletalStaggerAnimation) makes the hands let go of their guns and rifles
## (user request 2026-10-15): drop_hand_weapons() sends each one to a rest place on the ground (WeaponDrop)
## and WeaponPickup takes them back after the get-up (grab_dropped, equip_dropped). While a weapon lies on
## the ground its slot (right_weapon or left_weapon) is null, so nothing fires and the hands see no weapon.
## MechAssembler (or SkeletalWeaponMount on a rigged mech) calls mount() before the other nodes start.

@export var mech: Mech
@export var input: MechInput
@export var mech_aim: MechAim
@export var weapon_pose: WeaponPose
@export var weapon_recoil: WeaponRecoil
@export var arm_ik_left: TwoBoneIK
@export var arm_ik_right: TwoBoneIK
@export var camera_ads: CameraAds
@export var torso_pose: TorsoPose
@export var camera_shake: CameraShake
@export var mech_shield: MechShield
@export var shield_pose: ShieldPose
@export var shield_mount: ShieldMount
## Frame node that holds the weapons (the torso).
@export var torso: Node3D
## Left hand target when the left hand holds no weapon (moved by ShieldPose).
@export var left_hand: Node3D
## Optional. Made unsteady when a two-hand weapon is held in one hand.
@export var free_aim: FreeAim
## True: with no shield and no two-hand weapon the left arm keeps its animation (rigged mechs).
@export var animate_free_left_arm: bool = false
## Optional. With animate_free_left_arm: the free left hand goes to this marker (a relaxed hang)
## in place of the animation.
@export var free_left_hand: Node3D
## Optional. The free right hand (the right weapon broke) goes to this marker (a relaxed hang). Empty:
## a marker is made at the mirror place of free_left_hand.
@export var free_right_hand: Node3D

@export_group("One-hand hold")
## Right hand (GripRight) place in the aim pose, torso space. The one-hand rifle hip hold.
@export var one_hand_grip_aim: Vector3 = Vector3(2.38, 0.6, -1.84)
## Right hand place in the rest pose, torso space.
@export var one_hand_grip_rest: Vector3 = Vector3(2.38, 0.65, -1.69)
## Weapon turn in the rest pose (muzzle a little down), in degrees.
@export var one_hand_rest_pitch_deg: float = -4.6
## Elbow direction of the right arm (out and down).
@export var one_hand_pole: Vector3 = Vector3(0.4, -1.0, 0.5)
@export_group("Drop")
## False: the Auto Cannon (a gun held under the forearm) stays on the arm when the mech is knocked face down.
@export var drop_forearm_guns: bool = true
## Rest place of a dropped weapon (grip), from the place where the mech stands after the get-up: meters
## ahead of it, to the side of a one-hand gun (right gun right, left gun left), and to the right of the
## right grip of a two-hand rifle (the rifle lies across in front of the mech).
@export var drop_ahead: float = 1.8
@export var drop_side: float = 2.4
@export var drop_rifle_side: float = 1.0
## A one-hand gun lies with its muzzle turned this much away from the front (degrees, outward).
@export var drop_gun_yaw_deg: float = 20.0
@export_group("")

## True when a two-hand weapon is held in the right hand alone.
var one_hand_hold: bool = false

var right_weapon: MechWeapon
var back_left: MechWeapon
## What the left hand holds when it is not a shield: a fist, a one-hand gun or the pile bunker.
var left_weapon: MechWeapon
## The left weapon's own pose and recoil (a gun or the pile bunker; made on first use).
var left_pose: WeaponPose
var left_recoil: WeaponRecoil
## True on the view node (left_view): a stand-in controller for the left weapon. Weapon scripts read
## weapon_pose, weapon_recoil and holding_arm_ik() from their controller, so a left weapon gets
## the left ones. It shares everything else with the real controller and does no work of its own.
var left_arm_view: bool = false
var left_view: WeaponController
## Left arm hold offset (ArmPart.hold_offset of the left arm), torso space.
var left_hold_offset: Vector3 = Vector3.ZERO
var back_right: MechWeapon
var right_data: WeaponData
var left_data: WeaponData
## A hand weapon on the ground (a knock-down face down made the hand let go): right_weapon or left_weapon
## is null meanwhile, right_data and left_data stay.
var dropped_right: WeaponDrop
var dropped_left: WeaponDrop
## The weapon in use now (null = none).
var active: MechWeapon = null
## Shield model nodes on the frame (PartBreaker drops them when the shield breaks).
var shield_nodes: Array[Node3D] = []
## Right arm hold offset (ArmPart.hold_offset), torso space: added to every right weapon hold place.
var hold_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	# After MechInput (-10), before WeaponPose (5) and the weapons.
	process_physics_priority = 1


## attach: adds a socket-group scene to the frame and returns the added nodes (MechAssembler.attach).
func mount(loadout: Loadout, attach: Callable) -> void:
	right_data = loadout.weapon_right
	left_data = loadout.weapon_left
	hold_offset = loadout.arm_right.hold_offset if loadout.arm_right is ArmPart else Vector3.ZERO
	left_hold_offset = loadout.arm_left.hold_offset if loadout.arm_left is ArmPart else Vector3.ZERO
	if right_data != null and right_data.scene != null:
		right_weapon = _add_weapon(right_data, "RightWeapon")
		if is_melee_kind(right_data):
			_wire_melee(right_weapon as MeleeWeapon, false)
		else:
			_wire_right(right_data)
	var has_shield := left_data != null and left_data.kind == WeaponData.Kind.SHIELD
	if has_shield:
		shield_nodes.assign(attach.call(left_data.scene))
		_wire_shield(left_data)
	_set_shield_enabled(has_shield)
	if not has_shield and not _two_handed():
		arm_ik_left.target = _free_left_target()
	if left_data != null and left_data.kind == WeaponData.Kind.FIST and left_data.scene != null and not _two_handed():
		left_weapon = _add_weapon(left_data, "LeftWeapon")
		_wire_melee(left_weapon as MeleeWeapon, true)
	elif can_hold_left(left_data, right_data):
		_make_left_view()
		left_weapon = _add_weapon(left_data, "LeftWeapon", left_view)
		_wire_left_weapon(left_data)
	if loadout.back_left != null and loadout.back_left.scene != null:
		back_left = _add_weapon(loadout.back_left, "BackLeft")
	if loadout.back_right != null and loadout.back_right.scene != null:
		back_right = _add_weapon(loadout.back_right, "BackRight")


## owner_controller: the controller the weapon talks to (the left view for a left weapon).
func _add_weapon(data: WeaponData, node_name: String, owner_controller: WeaponController = null) -> MechWeapon:
	var weapon := data.scene.instantiate() as MechWeapon
	weapon.name = node_name
	torso.add_child(weapon)
	weapon.setup(data, owner_controller if owner_controller != null else self)
	return weapon


func _wire_right(data: WeaponData) -> void:
	weapon_pose.weapon = right_weapon
	weapon_pose.use_weapon_data = true
	weapon_pose.rest_transform = data.rest_transform.translated(hold_offset)
	weapon_pose.aim_origin = data.aim_anchor + hold_offset
	weapon_pose.right_pole_rest = data.right_pole_rest
	weapon_pose.right_pole_aim = data.right_pole_aim
	right_weapon.transform = data.rest_transform.translated(hold_offset)
	arm_ik_right.target = right_weapon.get_node("GripRight")
	weapon_pose.right_grip_target = right_weapon.get_node_or_null("GripRight") as Node3D
	weapon_pose.right_grip_rest = right_weapon.get_node_or_null("GripRightRest") as Node3D
	weapon_pose.right_grip_aim = right_weapon.get_node_or_null("GripRightAim") as Node3D
	weapon_recoil.bind(right_weapon)
	weapon_recoil.kick_back = data.model_kick_back
	weapon_recoil.kick_up_deg = data.model_kick_up_deg
	torso_pose.aim_twist_deg = data.aim_twist_deg
	torso_pose.aim_tilt_deg = data.aim_tilt_deg
	camera_ads.enabled = data.two_handed and data.zoom_fov > 0.0
	if camera_ads.enabled:
		camera_ads.aim_fov = data.zoom_fov
	if data.two_handed:
		weapon_pose.left_grip_target = right_weapon.get_node("GripLeft")
		weapon_pose.left_grip_rest = right_weapon.get_node("GripLeftRest")
		weapon_pose.left_grip_aim = right_weapon.get_node("GripLeftAim")
		weapon_pose.left_pole_rest = data.left_pole_rest
		weapon_pose.left_pole_aim = data.left_pole_aim
		arm_ik_left.target = weapon_pose.left_grip_target


## True for the melee weapons that play attack clips (fist, hammer; user request 2026-10-15).
static func is_melee_kind(data: WeaponData) -> bool:
	return data != null and (data.kind == WeaponData.Kind.FIST or data.kind == WeaponData.Kind.HAMMER)


## A fist or the hammer: the model goes on the hand and the arm follows the animation (no grip IK,
## no aim pose). The hammer frees both arms.
func _wire_melee(weapon: MeleeWeapon, left: bool) -> void:
	weapon.is_left = left
	weapon.attach_to_hand()
	if left:
		arm_ik_left.target = null
		return
	arm_ik_right.target = null
	for node: Node in [weapon_pose, weapon_recoil, arm_ik_right]:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	camera_ads.enabled = false
	torso_pose.aim_twist_deg = 0.0
	torso_pose.aim_tilt_deg = 0.0
	if weapon.data.two_handed:
		arm_ik_left.target = null


## True when the left hand can hold this weapon besides the shields and the fist (user rule
## 2026-10-15): a one-hand gun, or the pile bunker when the right hand holds no pile bunker (melee
## weapons may not be doubled, except the fist). Never beside a two-hand weapon.
static func can_hold_left(left: WeaponData, right: WeaponData) -> bool:
	if left == null or left.scene == null or left.two_handed:
		return false
	if right != null and right.two_handed:
		return false
	match left.kind:
		WeaponData.Kind.GUN:
			return true
		WeaponData.Kind.PILE_BUNKER:
			return right == null or right.kind != WeaponData.Kind.PILE_BUNKER
	return false


## A place mirrored across the mech's middle plane (torso space: x is right).
static func mirror_point(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y, point.z)


## A transform mirrored across the middle plane, as a pose of the same (unmirrored) model on the
## other side: the places mirror, the turns mirror, and the model keeps its handedness.
static func mirror_pose(pose: Transform3D) -> Transform3D:
	var flip := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	return Transform3D(flip * pose.basis * flip, mirror_point(pose.origin))


## The arm IK of the arm that holds this controller's weapons: the left arm on the left view.
func holding_arm_ik() -> TwoBoneIK:
	return arm_ik_left if left_arm_view else arm_ik_right


## Makes the left weapon's own WeaponPose and WeaponRecoil (next to the right ones) and the left
## view that the left weapon's scripts use as their controller.
func _make_left_view() -> void:
	var parent := weapon_pose.get_parent()
	left_recoil = WeaponRecoil.new()
	left_recoil.name = "LeftWeaponRecoil"
	parent.add_child(left_recoil)
	left_pose = WeaponPose.new()
	left_pose.name = "LeftWeaponPose"
	left_pose.left_arm = true
	left_pose.use_weapon_data = true
	left_pose.mech_aim = mech_aim
	left_pose.input = input
	left_pose.arm_ik_left = arm_ik_left
	left_pose.arm_ik_right = arm_ik_right
	left_pose.recoil = left_recoil
	left_pose.one_hand_elbow_pivot = weapon_pose.one_hand_elbow_pivot
	left_pose.one_hand_pivot = mirror_point(weapon_pose.one_hand_pivot)
	parent.add_child(left_pose)
	left_view = WeaponController.new()
	left_view.name = "LeftView"
	left_view.left_arm_view = true
	for property in ["mech", "input", "mech_aim", "arm_ik_left", "arm_ik_right", "camera_ads", "torso_pose",
			"camera_shake", "mech_shield", "shield_pose", "shield_mount", "torso", "left_hand", "free_aim"]:
		left_view.set(property, get(property))
	left_view.weapon_pose = left_pose
	left_view.weapon_recoil = left_recoil
	left_view.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(left_view)


## A one-hand gun or the pile bunker in the left hand: its pose, recoil and hand target are the
## mirror of the right ones, and the left arm reaches for its grip.
func _wire_left_weapon(data: WeaponData) -> void:
	var rest := mirror_pose(data.rest_transform).translated(left_hold_offset)
	left_pose.weapon = left_weapon
	left_pose.rest_transform = rest
	left_pose.aim_origin = mirror_point(data.aim_anchor) + left_hold_offset
	left_pose.right_pole_rest = mirror_point(data.right_pole_rest)
	left_pose.right_pole_aim = mirror_point(data.right_pole_aim)
	left_weapon.transform = rest
	var grip := left_weapon.get_node("GripRight") as Node3D
	var hand := Marker3D.new()
	hand.name = "GripLeft"
	hand.position = mirror_point(grip.position)
	left_weapon.add_child(hand)
	arm_ik_left.target = hand
	left_recoil.bind(left_weapon)
	left_recoil.kick_back = data.model_kick_back
	left_recoil.kick_up_deg = data.model_kick_up_deg


func _wire_shield(data: WeaponData) -> void:
	shield_mount.shield_node = torso.find_child("Shield", true, false)
	shield_mount.rest_mount = torso.find_child("ShieldMountRest", true, false)
	shield_mount.cover = torso.find_child("ShieldCover", true, false)
	shield_mount.shield_scale = data.shield_scale
	mech_shield.area_m2 = data.shield_area_m2
	# The arm holds the shield in one place (rest = raised).
	if shield_pose != null and shield_pose.rest != null and shield_pose.raised != null:
		shield_pose.rest.position = data.shield_hand
		shield_pose.raised.position = data.shield_hand
	arm_ik_left.target = left_hand


## The right arm is gone: its weapon stops and the right arm pose and IK stop.
func lose_right_weapon() -> void:
	if right_weapon == null and dropped_right == null:
		return
	# A weapon that lies on the ground stays there for good (the caller may break it with right_weapon_nodes()).
	_leave_dropped(true)
	if right_weapon != null:
		if active == right_weapon:
			active = null
		right_weapon.set_trigger(false)
		right_weapon.process_mode = Node.PROCESS_MODE_DISABLED
	if two_handed_left_grip():
		arm_ik_left.target = _lost_left_target()
	var relaxed_right := _free_right_target()
	right_weapon = null
	right_data = null
	weapon_pose.aim_amount = 0.0
	weapon_pose.wants_raise = false
	one_hand_hold = false
	if free_aim != null:
		free_aim.unsteady = 0.0
	for node: Node in [weapon_pose, weapon_recoil]:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	# Rigged mech: the right arm hangs relaxed like the free left arm (user report 2026-10-15: no wide V).
	if relaxed_right != null:
		arm_ik_right.target = relaxed_right
		arm_ik_right.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		arm_ik_right.process_mode = Node.PROCESS_MODE_DISABLED
	torso_pose.aim_twist_deg = 0.0
	torso_pose.aim_tilt_deg = 0.0
	torso_pose.action_twist_deg = 0.0
	camera_ads.enabled = false


## Left hand target when the left hand holds nothing.
func _free_left_target() -> Node3D:
	return free_left_hand if animate_free_left_arm else left_hand


## Right hand target when the right weapon broke. Rigged mechs: the relaxed hang, the mirror of the
## free left hand (a marker made on first use). Part-built mechs: none (the arm IK stops).
func _free_right_target() -> Node3D:
	if not animate_free_left_arm:
		return null
	if free_right_hand == null and free_left_hand != null:
		free_right_hand = Marker3D.new()
		free_right_hand.name = "RightHandRelaxed"
		free_left_hand.get_parent().add_child(free_right_hand)
		free_right_hand.position = Vector3(-free_left_hand.position.x, free_left_hand.position.y, free_left_hand.position.z)
	return free_right_hand


## Left hand target when what it held broke (a two-hand weapon or the shield): the relaxed hang
## on a rigged mech (user report 2026-10-15: the animation arm stood out in a wide V).
func _lost_left_target() -> Node3D:
	return _free_left_target()


## The mech is wrecked (MechDeath froze the animation): a left arm that follows the animation goes
## to the relaxed hang, so it takes no stiff frozen pose (user request 2026-10-15).
func relax_free_left_arm() -> void:
	if arm_ik_left != null and arm_ik_left.target == null:
		arm_ik_left.target = _free_left_target()


## Model nodes of the right weapon (a forearm weapon's model sits on the forearm: get_model()).
func right_weapon_nodes() -> Array[Node3D]:
	return _weapon_nodes(right_weapon if right_weapon != null else _dropped_weapon(dropped_right))


## Model nodes of a weapon (a forearm weapon's model sits on the forearm: get_model()).
func _weapon_nodes(weapon: MechWeapon) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	if weapon != null and weapon.has_method(&"get_model"):
		nodes.append(weapon.call(&"get_model") as Node3D)
	elif weapon != null:
		nodes.append(weapon)
	return nodes


func _dropped_weapon(drop: WeaponDrop) -> MechWeapon:
	return drop.weapon if is_instance_valid(drop) and is_instance_valid(drop.weapon) else null


## True when the left hand holds the right weapon (two-hand weapon).
func two_handed_left_grip() -> bool:
	return right_data != null and right_data.two_handed and not is_melee_kind(right_data)


## The shield is gone (broken, or the left arm is gone).
func lose_shield() -> void:
	if left_data == null:
		return
	left_data = null
	shield_nodes = []
	_set_shield_enabled(false)
	mech_shield.force_up = false
	if animate_free_left_arm and not _two_handed():
		arm_ik_left.target = _lost_left_target()


## The left arm is gone: no shield, and the left arm IK stops.
func lose_left_arm() -> void:
	lose_shield()
	_leave_dropped(false)
	if left_weapon != null:
		left_weapon.set_trigger(false)
		left_weapon.process_mode = Node.PROCESS_MODE_DISABLED
		if left_weapon is PileBunkerWeapon:
			(left_weapon as PileBunkerWeapon).cancel()
			# The bunker no longer runs, so its torso twist would stay (review 2026-10-15).
			torso_pose.action_twist_deg = 0.0
		if active == left_weapon:
			active = null
		var model: Node3D = left_weapon.call(&"get_model") if left_weapon.has_method(&"get_model") else null
		if is_instance_valid(model):
			model.queue_free()
		# A gun or the pile bunker is its own node on the frame; a fist is only a model on the hand.
		if not left_weapon is MeleeWeapon:
			left_weapon.queue_free()
		left_weapon = null
	if left_pose != null:
		left_pose.weapon = null
		left_pose.wants_raise = false
		left_pose.aim_amount = 0.0
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	arm_ik_left.process_mode = Node.PROCESS_MODE_DISABLED
	if _two_handed() and right_weapon != null and not right_weapon is MeleeWeapon:
		_hold_one_hand()


## The right hand holds the two-hand weapon alone: the weapon moves so its right grip sits where
## the one-hand rifle grip sits (the stock slides back under the arm), and the aim swings.
func _hold_one_hand() -> void:
	one_hand_hold = true
	var grip := (right_weapon.get_node("GripRight") as Node3D).position
	var rest_basis := Basis(Vector3.RIGHT, deg_to_rad(one_hand_rest_pitch_deg))
	weapon_pose.left_grip_target = null
	weapon_pose.aim_origin = one_hand_grip_aim + hold_offset - grip
	weapon_pose.rest_transform = Transform3D(rest_basis, one_hand_grip_rest + hold_offset - rest_basis * grip)
	weapon_pose.right_pole_rest = one_hand_pole
	weapon_pose.right_pole_aim = one_hand_pole
	torso_pose.aim_twist_deg = 0.0
	torso_pose.aim_tilt_deg = 0.0
	if free_aim != null:
		free_aim.unsteady = 1.0


## The left hand lets go of its gun (the mech died): the gun stops working. Returns the nodes to drop
## (empty when the left hand holds no gun). The pile bunker and the fist stay.
func lose_left_gun() -> Array[Node3D]:
	var weapon := left_weapon
	if not can_drop(weapon):
		return []
	if active == weapon:
		active = null
	weapon.set_trigger(false)
	weapon.process_mode = Node.PROCESS_MODE_DISABLED
	left_weapon = null
	if left_pose != null:
		left_pose.weapon = null
		left_pose.wants_raise = false
		left_pose.aim_amount = 0.0
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	arm_ik_left.target = _lost_left_target()
	return _weapon_nodes(weapon)


## True when the hand can let go of this weapon: a hand gun or a rifle (the pile bunker and the fist stay,
## the shields stay).
func can_drop(weapon: MechWeapon) -> bool:
	if weapon == null or not is_instance_valid(weapon) or weapon is MeleeWeapon or weapon is PileBunkerWeapon:
		return false
	if weapon is ForearmGunWeapon and not drop_forearm_guns:
		return false
	return (weapon is GunWeapon or weapon is BeamRifleWeapon) and torso.is_ancestor_of(weapon)


## True when a hand holds a weapon that a knock-down face down drops.
func has_droppable_weapon() -> bool:
	return can_drop(right_weapon) or can_drop(left_weapon)


## True while a hand weapon lies on the ground.
func is_hand_weapon_dropped() -> bool:
	return is_instance_valid(dropped_right) or is_instance_valid(dropped_left)


## True when the right (left) arm has no weapon in the hand because the weapon lies on the ground. The
## left hand of a two-hand rifle counts: it let go of the forestock.
func is_arm_free(right: bool) -> bool:
	if right:
		return is_instance_valid(dropped_right)
	return is_instance_valid(dropped_left) or (is_instance_valid(dropped_right) and weapon_pose.left_grip_target != null)


## The hands let go of their guns and rifles: each flies from the hand to a rest place on the ground
## near stand_point (the place where the mech will stand after the get-up; forward is its facing, flat).
## The fall moves the mech; the rest places are ahead of the stand place, to the sides.
func drop_hand_weapons(stand_point: Vector3, forward: Vector3) -> void:
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var side := forward.cross(Vector3.UP)
	var level := get_world()
	for is_right: bool in [true, false]:
		var weapon := right_weapon if is_right else left_weapon
		if not can_drop(weapon):
			continue
		var two_hand := is_right and two_handed_left_grip() and weapon_pose.left_grip_target != null
		_let_go(weapon, is_right, two_hand)
		var spot := stand_point + forward * drop_ahead
		var face := forward
		if two_hand:
			spot += side * drop_rifle_side
			face = -side
		else:
			var out := 1.0 if is_right else -1.0
			spot += side * drop_side * out
			face = forward.rotated(Vector3.UP, -deg_to_rad(drop_gun_yaw_deg) * out)
		var drop := WeaponDrop.create(weapon, level, spot, face, two_hand)
		if is_right:
			dropped_right = drop
		else:
			dropped_left = drop


## The hand lets go of the weapon: it stops, the pose and the arm IK of that hand stop, and the arm
## goes to its relaxed hang (the knock-down clip moves it).
func _let_go(weapon: MechWeapon, is_right: bool, two_hand: bool) -> void:
	# Twice: the second call clears the "trigger was released" flag, or a charged beam rifle would fire
	# from the ground when it works again.
	weapon.set_trigger(false)
	weapon.set_trigger(false)
	_end_discharge(weapon)
	for flash: Node3D in weapon.find_children("*", "MuzzleFlash", true, false):
		flash.visible = false
	if active == weapon:
		active = null
	# A forearm gun has its model under the forearm: it goes back to the weapon to fall with it.
	if weapon is ForearmGunWeapon:
		var model := (weapon as ForearmGunWeapon).get_model()
		if model.get_parent() != weapon:
			model.reparent(weapon, true)
		weapon.process_mode = Node.PROCESS_MODE_DISABLED
	if is_right:
		right_weapon = null
		weapon_pose.aim_amount = 0.0
		weapon_pose.wants_raise = false
		for node: Node in [weapon_pose, weapon_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		torso_pose.aim_twist_deg = 0.0
		torso_pose.aim_tilt_deg = 0.0
		torso_pose.action_twist_deg = 0.0
		camera_ads.enabled = false
		input.stance_lock = false
		_relax_arm(arm_ik_right, _free_right_target())
		if two_hand:
			_relax_arm(arm_ik_left, _lost_left_target())
	else:
		left_weapon = null
		left_pose.aim_amount = 0.0
		left_pose.wants_raise = false
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		_relax_arm(arm_ik_left, _free_left_target())


## WeaponPickup: an arm that reached for its weapon goes back to the relaxed hang.
func relax_arm(right: bool) -> void:
	if right:
		_relax_arm(arm_ik_right, _free_right_target())
	else:
		_relax_arm(arm_ik_left, _free_left_target())


func _relax_arm(ik: TwoBoneIK, target: Node3D) -> void:
	ik.target = target
	ik.process_mode = Node.PROCESS_MODE_INHERIT if target != null else Node.PROCESS_MODE_DISABLED


## A beam rifle that fires or charges stops (nothing fires from the ground).
func _end_discharge(weapon: MechWeapon) -> void:
	var rifle := weapon as BeamRifleWeapon
	if rifle == null:
		return
	rifle.discharge_left = 0.0
	rifle.charge = 0.0
	if is_instance_valid(rifle._beam):
		rifle._beam.release()
	rifle._beam = null
	torso_pose.action_shake = 0.0


## WeaponPickup: the hands hold the dropped weapon again. It goes back to the frame and the slot, and the
## arms reach for its grips. The weapon does not work yet (equip_dropped).
func grab_dropped(drop: WeaponDrop) -> void:
	var weapon := drop.weapon
	if not is_instance_valid(weapon):
		return
	var is_right := drop == dropped_right
	weapon.reparent(torso, true)
	if is_right:
		dropped_right = null
		right_weapon = weapon
		arm_ik_right.target = weapon.get_node("GripRight")
		arm_ik_right.process_mode = Node.PROCESS_MODE_INHERIT
		if weapon_pose.left_grip_target != null:
			arm_ik_left.target = weapon_pose.left_grip_target
	else:
		dropped_left = null
		left_weapon = weapon
		arm_ik_left.target = weapon.get_node("GripLeft")
	drop.queue_free()


## WeaponPickup: the weapon is in the hand again: it works, its pose and recoil run, the torso and the
## aim camera take their values for it. The pose puts the weapon in its rest place.
func equip_dropped(weapon: MechWeapon, is_right: bool) -> void:
	weapon.process_mode = Node.PROCESS_MODE_INHERIT
	if is_right:
		torso_pose.aim_twist_deg = right_data.aim_twist_deg
		torso_pose.aim_tilt_deg = right_data.aim_tilt_deg
		camera_ads.enabled = right_data.two_handed and right_data.zoom_fov > 0.0
		weapon_pose.aim_amount = 0.0
		weapon_pose.wants_raise = false
		arm_ik_right.pole_direction = weapon_pose.right_pole_rest
		if weapon_pose.left_grip_target != null:
			arm_ik_left.pole_direction = weapon_pose.left_pole_rest
		for node: Node in [weapon_pose, weapon_recoil]:
			node.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		left_pose.aim_amount = 0.0
		left_pose.wants_raise = false
		arm_ik_left.pole_direction = left_pose.right_pole_rest
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_INHERIT


## Where a hand holds the weapon at rest: the grip markers of a two-hand rifle go to their rest places
## (the pose moves them while aiming).
func reset_grips() -> void:
	if weapon_pose.right_grip_target != null and weapon_pose.right_grip_rest != null:
		weapon_pose.right_grip_target.position = weapon_pose.right_grip_rest.position
	if weapon_pose.left_grip_target != null and weapon_pose.left_grip_rest != null:
		weapon_pose.left_grip_target.position = weapon_pose.left_grip_rest.position


## The weapon lies on the ground for good (its arm is gone): nobody picks it up.
func _leave_dropped(is_right: bool) -> void:
	var drop := dropped_right if is_right else dropped_left
	if is_right:
		dropped_right = null
	else:
		dropped_left = null
	if is_instance_valid(drop) and is_instance_valid(drop.weapon):
		drop.weapon.process_mode = Node.PROCESS_MODE_DISABLED


## The mech is gone: its weapons on the ground go with it.
func _exit_tree() -> void:
	for drop in [dropped_right, dropped_left]:
		if is_instance_valid(drop):
			drop.queue_free()


## A back unit is gone.
func lose_back_weapon(weapon: MechWeapon) -> void:
	if weapon == null:
		return
	if active == weapon:
		active = null
	weapon.set_trigger(false)
	weapon.process_mode = Node.PROCESS_MODE_DISABLED
	if weapon == back_left:
		back_left = null
	if weapon == back_right:
		back_right = null


func _set_shield_enabled(enabled: bool) -> void:
	mech_shield.enabled = enabled
	var mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	shield_pose.process_mode = mode
	shield_mount.process_mode = mode


func _two_handed() -> bool:
	return right_data != null and right_data.two_handed


func _physics_process(_delta: float) -> void:
	if mech.is_wrecked or mech.is_fallen:
		# Down, stunned or dead: no weapon fires (a trigger held before stays released).
		for weapon: MechWeapon in [right_weapon, left_weapon, back_left, back_right]:
			if weapon != null:
				weapon.set_trigger(false)
		weapon_pose.wants_raise = false
		if left_pose != null:
			left_pose.wants_raise = false
		return
	var wants := {}
	if right_weapon != null:
		if right_data.kind == WeaponData.Kind.HAMMER:
			# The hammer: either mouse button (user request 2026-10-15).
			wants[right_weapon] = input.fire_held or input.left_fire_held
		else:
			wants[right_weapon] = input.left_fire_held if _two_handed() else input.fire_held
	if left_weapon != null:
		wants[left_weapon] = input.left_fire_held
	if back_left != null:
		wants[back_left] = input.back_left_held
	if back_right != null:
		wants[back_right] = input.back_right_held
	# One weapon at a time (not counting melee weapons). Both missile pods count as one weapon.
	if active != null and not _still_in_use(active, wants):
		active = null
	if active == null:
		for weapon in wants:
			if wants[weapon] and not weapon.is_melee():
				active = weapon
				break
	for weapon in wants:
		weapon.set_trigger(wants[weapon] and _may_fire(weapon))
	input.stance_lock = false
	if right_weapon != null and not right_weapon is MeleeWeapon:
		var right_on := _may_fire(right_weapon)
		if _two_handed():
			weapon_pose.wants_raise = input.aim_held or (right_on and (input.left_fire_held or right_weapon.is_busy()))
			# Sniping stance: no walking while the rifle is raised (user, 2026-10-12). The rifle lowers
			# slowly (WeaponPose.lower_speed), so walking comes back early in the lowering.
			input.stance_lock = weapon_pose.wants_raise or weapon_pose.aim_amount > 0.85
		else:
			weapon_pose.wants_raise = input.fire_held and right_on and right_data.kind == WeaponData.Kind.GUN
		if input.reload_pressed:
			right_weapon.start_reload()
	# A one-hand gun in the left hand: raised while LMB is held, like the right one on RMB.
	if left_weapon != null and left_pose != null and not left_weapon is MeleeWeapon:
		left_pose.wants_raise = input.left_fire_held and _may_fire(left_weapon) and left_data.kind == WeaponData.Kind.GUN
		if input.reload_pressed:
			left_weapon.start_reload()
	if input.reload_pressed:
		for pod in [back_left, back_right]:
			if pod != null:
				pod.start_reload()


## The two arm guns (right and left hand) work together (dual guns, user rule 2026-10-15), like the
## two missile pods. Every other weapon works alone.
func _is_arm_gun(weapon: MechWeapon) -> bool:
	return weapon is GunWeapon and (weapon == right_weapon or weapon == left_weapon)


## True when the weapon may fire now: it is the active one, a melee weapon, or it works together with
## the active one (the missile pods, the two arm guns).
func _may_fire(weapon: MechWeapon) -> bool:
	return weapon == active or weapon.is_melee() \
			or (weapon is MissilePodWeapon and active is MissilePodWeapon) \
			or (_is_arm_gun(weapon) and _is_arm_gun(active))


func _still_in_use(weapon: MechWeapon, wants: Dictionary) -> bool:
	if wants.get(weapon, false) or _is_busy(weapon):
		return true
	if _is_arm_gun(weapon):
		for other in wants:
			if other != weapon and _is_arm_gun(other) and (wants[other] or _is_busy(other)):
				return true
	if weapon is MissilePodWeapon:
		for other in wants:
			if other is MissilePodWeapon and (wants[other] or _is_busy(other)):
				return true
	return false


func _is_busy(weapon: MechWeapon) -> bool:
	return weapon.has_method(&"is_busy") and weapon.is_busy()


## Weapons for the HUD: [label, weapon or data] pairs.
func get_hud_slots() -> Array:
	var slots := []
	# A weapon on the ground still shows in its slot.
	var right_shown := right_weapon if right_weapon != null else _dropped_weapon(dropped_right)
	var left_shown := left_weapon if left_weapon != null else _dropped_weapon(dropped_left)
	if right_shown != null:
		slots.append(["R", right_shown])
	if left_shown != null and not left_shown is MeleeWeapon:
		slots.append(["L", left_shown])
	elif left_data != null:
		slots.append(["L", left_data])
	if back_left != null:
		slots.append(["Q", back_left])
	if back_right != null:
		slots.append(["E", back_right])
	return slots


## Missile pods in lock mode, for the lock HUD.
func get_lock_pods() -> Array[MissilePodWeapon]:
	var pods: Array[MissilePodWeapon] = []
	for pod in [back_left, back_right]:
		if pod is MissilePodWeapon:
			pods.append(pod)
	return pods


## Node that holds bullets, missiles and effects.
func get_world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else get_tree().root


func get_max_locks() -> int:
	return mech.stats.max_locks if mech.stats != null else 4


func get_lock_range() -> float:
	return mech.stats.lock_range if mech.stats != null else 500.0


func get_lock_speed() -> float:
	return mech.stats.lock_on_speed if mech.stats != null else 1.0
