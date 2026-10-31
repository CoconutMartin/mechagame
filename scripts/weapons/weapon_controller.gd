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
## and WeaponPickup takes them back after the get-up (take_from_ground, equip_dropped). While a weapon lies
## on the ground its slot (right_weapon or left_weapon) is null, so nothing fires and the hands see no weapon.
## Empty hands are fists (user rule 2026-10-17): every hand with a live arm and nothing in it holds a Fist
## from a pool of two (right_fist, left_fist; the loadout has no fist weapon any more). Empty left punches on
## LMB, empty right on RMB. A fist hand that does not punch hangs relaxed (the arm IK goes to the relaxed
## hang marker); during a punch the arm IK lets go so the punch clip drives the arm. The arm rig still
## poses the hang under the clip (fist_hang_target), so the clip fades into the hang (user report 2026-10-18).
## Hand weapons can be dropped with Tab (drop_hand) and taken from the ground (WeaponPickup.begin_manual,
## take_from_ground): WeaponHandControl reads the keys. A weapon in a hand is a node under the torso; a
## weapon on the ground is a node under a WeaponDrop and is disabled.
## MechAssembler (or SkeletalWeaponMount on a rigged mech) calls mount() before the other nodes start.

## Stop to fire and the brace of the shoulder weapons (user request 2026-10-22). A preload and no class_name.
const ShoulderBraceScript := preload("res://scripts/weapons/shoulder_brace.gd")
## The brace stance of a rigged mech (a skeleton modifier made in _ready).
const BracePoseScript := preload("res://scripts/animation/brace_pose.gd")

## A hand let go of a weapon (Tab drop, knock-down, death). is_right: the right hand slot (a two-hand weapon
## is the right slot). WeaponPartSync takes the HP part of the weapon off the mech.
signal hand_weapon_released(is_right: bool, weapon: MechWeapon)
## A weapon is in the hand and works (picked up). WeaponPartSync gives it an HP part again.
signal hand_weapon_equipped(is_right: bool, weapon: MechWeapon)

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
@export_group("Fists")
## The weapon in an empty hand (user rule 2026-10-17). Empty: data/weapons/fist.tres.
@export var fist_data: WeaponData
## A fist arm stays free for the punch clip this many seconds after a melee attack ends (the clip fades
## out meanwhile), then it goes back to the relaxed hang.
@export var fist_hang_delay: float = 0.35
@export_group("Drop")
## False: the Auto Cannon (a gun held under the forearm) stays on the arm when the mech is knocked face down.
## (A Tab drop ignores this: user rule 2026-10-17.)
@export var drop_forearm_guns: bool = true
## A Tab drop lands this part of the knock-down rest distances (drop_ahead, drop_side, drop_rifle_side), so
## the weapon lies inside the 3 m pick-up radius and the mech can take it back at once.
@export_range(0.2, 1.0) var tab_drop_scale: float = 0.75
## The most weapons on the ground on the map (user rule 2026-10-17). The oldest free one goes first.
@export var max_ground_weapons: int = 8
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
## Stop to fire for the back weapons and the brace amount of the shoulder cannons (made in _ready).
var shoulder_brace: ShoulderBraceScript
## The two fists of the empty hands (made once, on first use; null = never made or the arm is gone).
var right_fist: MeleeWeapon
var left_fist: MeleeWeapon
## The weapon pick-up of this mech (it registers itself). Null on a mech without one.
var pickup: WeaponPickup
## True while the left arm is destroyed.
var left_arm_lost: bool = false

var right_weapon: MechWeapon
var back_left: MechWeapon
## The loadout's back weapon data [left, right] (set in mount; for the shoulder guns hold).
var _back_data: Array = []
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

## A hand is reaching for a weapon on the ground (WeaponPickup): its fist is off and the pick-up runs it.
var _picking_right: bool = false
var _picking_left: bool = false
## Seconds left that a fist arm stays free for the punch clip.
var _swing_hold: float = 0.0
var _melee: SkeletalMeleeAnimation


func _ready() -> void:
	# After MechInput (-10), before WeaponPose (5) and the weapons.
	process_physics_priority = 1
	shoulder_brace = ShoulderBraceScript.new()
	shoulder_brace.name = "ShoulderBrace"
	shoulder_brace.mech = mech
	add_child(shoulder_brace)
	_make_brace_pose.call_deferred()


## attach: adds a socket-group scene to the frame and returns the added nodes (MechAssembler.attach).
func mount(loadout: Loadout, attach: Callable) -> void:
	if fist_data == null:
		# Loaded here and not preloaded: the fist scene's script reads this class (a preload would be a cycle).
		fist_data = load("res://data/weapons/fist.tres") as WeaponData
	right_data = loadout.weapon_right
	left_data = loadout.weapon_left
	_back_data = [loadout.back_left, loadout.back_right]
	# A fist is no loadout weapon (user rule 2026-10-17): every empty hand gets one (_refresh_fists).
	if right_data != null and right_data.kind == WeaponData.Kind.FIST:
		right_data = null
	if left_data != null and left_data.kind == WeaponData.Kind.FIST:
		left_data = null
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
	if can_hold_left(left_data, right_data):
		_make_left_view()
		left_weapon = _add_weapon(left_data, "LeftWeapon", left_view)
		_wire_left_weapon(left_data)
	if loadout.back_left != null and loadout.back_left.scene != null:
		back_left = _add_weapon(loadout.back_left, "BackLeft")
	if loadout.back_right != null and loadout.back_right.scene != null:
		back_right = _add_weapon(loadout.back_right, "BackRight")
	if animate_free_left_arm:
		# Both fists exist from the start (they get the mech skin with the rest of the mech); an empty hand shows its one.
		_fist(true)
		_fist(false)
	_refresh_fists()
	_make_hand_control()


## True when both back slots of the loadout carry a shoulder gun (a GUN on a back slot: the shoulder Auto Cannon).
func _has_shoulder_guns() -> bool:
	for data: WeaponData in _back_data:
		if data == null or data.slot != WeaponData.Slot.BACK or data.kind != WeaponData.Kind.GUN:
			return false
	return _back_data.size() == 2


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
	var rest := data.rest_transform
	var anchor := data.aim_anchor
	weapon_pose.aim_shift = Vector3.ZERO
	# A weapon held like another one when both back slots carry shoulder guns (WeaponData.shoulder_guns_hold).
	var hold := BorrowedHold.apply(right_weapon, data.shoulder_guns_hold) if data.two_handed and _has_shoulder_guns() else null
	if hold != null:
		rest = hold.rest_transform
		anchor = hold.aim_anchor
		weapon_pose.aim_shift = hold.shift
	weapon_pose.rest_transform = rest.translated(hold_offset)
	weapon_pose.aim_origin = anchor + hold_offset
	weapon_pose.right_pole_rest = data.right_pole_rest
	weapon_pose.right_pole_aim = data.right_pole_aim
	right_weapon.transform = rest.translated(hold_offset)
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
	else:
		# A one-hand gun (maybe after a rifle): no left grip on the pose.
		weapon_pose.left_grip_target = null
		weapon_pose.left_grip_rest = null
		weapon_pose.left_grip_aim = null


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


## The fist of a hand, made on first use (a MeleeWeapon under the torso, its model on the hand bone). It
## stays off (disabled, model hidden) until _fist_on.
func _fist(is_right: bool) -> MeleeWeapon:
	var fist := right_fist if is_right else left_fist
	if fist != null and is_instance_valid(fist):
		return fist
	fist = _add_weapon(fist_data, "RightFist" if is_right else "LeftFist") as MeleeWeapon
	fist.is_left = not is_right
	fist.attach_to_hand()
	fist.process_mode = Node.PROCESS_MODE_DISABLED
	_show_fist(fist, false)
	if is_right:
		right_fist = fist
	else:
		left_fist = fist
	return fist


func _show_fist(fist: MeleeWeapon, shown: bool) -> void:
	var model := fist.get_model()
	if is_instance_valid(model):
		model.visible = shown


func _is_fist(weapon: MechWeapon) -> bool:
	return weapon != null and weapon is MeleeWeapon and weapon.data != null and weapon.data.kind == WeaponData.Kind.FIST


## The hand holds its fist now.
func _fist_on(is_right: bool) -> void:
	var fist := _fist(is_right)
	if (right_weapon if is_right else left_weapon) == fist:
		return
	fist.process_mode = Node.PROCESS_MODE_INHERIT
	_show_fist(fist, true)
	if is_right:
		right_weapon = fist
		right_data = fist_data
		weapon_pose.aim_amount = 0.0
		weapon_pose.wants_raise = false
		for node: Node in [weapon_pose, weapon_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		torso_pose.aim_twist_deg = 0.0
		torso_pose.aim_tilt_deg = 0.0
		camera_ads.enabled = false
		_relax_arm(arm_ik_right, _free_right_target())
	else:
		left_weapon = fist
		left_data = fist_data
		_relax_arm(arm_ik_left, _free_left_target())


## The hand does not hold its fist any more (a weapon comes into the hand, or the arm is gone).
func _fist_off(is_right: bool) -> void:
	var fist := right_fist if is_right else left_fist
	if fist == null or not is_instance_valid(fist):
		return
	# Twice: the second call clears the "trigger was released" flag.
	fist.set_trigger(false)
	fist.set_trigger(false)
	fist.process_mode = Node.PROCESS_MODE_DISABLED
	_show_fist(fist, false)
	if active == fist:
		active = null
	if is_right:
		if right_weapon == fist:
			right_weapon = null
			right_data = null
	elif left_weapon == fist:
		left_weapon = null
		left_data = null


## The arm is destroyed: its fist goes with it (the model sits on the hand bone).
func _retire_fist(is_right: bool) -> void:
	_fist_off(is_right)
	var fist := right_fist if is_right else left_fist
	if is_right:
		right_fist = null
	else:
		left_fist = null
	if fist != null and is_instance_valid(fist):
		var model := fist.get_model()
		if is_instance_valid(model):
			model.queue_free()
		fist.queue_free()


## Puts a fist in every empty hand and takes it out of every other hand (user rule 2026-10-17). Safe to call
## at any time. A hand has no fist when: its arm is destroyed, a weapon lies on the ground that the hand
## dropped face down, the hand is reaching for a weapon, the hand holds something, or
## (left) the right hand holds a two-hand weapon or the War Hammer. Only rigged mechs have fists.
func _refresh_fists() -> void:
	# A wreck keeps the fists it has and gets no new ones.
	if not animate_free_left_arm or fist_data == null or mech == null or left_arm_view or mech.is_wrecked:
		return
	var right_empty := (right_weapon == null or right_weapon == right_fist) \
			and (right_data == null or right_data == fist_data) and not is_instance_valid(dropped_right)
	var left_empty := (left_weapon == null or left_weapon == left_fist) \
			and (left_data == null or left_data == fist_data) and not is_instance_valid(dropped_left) \
			and not _two_handed()
	var want_right := right_empty and not _picking_right and is_arm_alive(true)
	var want_left := left_empty and not _picking_left and is_arm_alive(false)
	if want_right:
		_fist_on(true)
	elif right_weapon == right_fist and right_fist != null:
		_fist_off(true)
	if want_left:
		_fist_on(false)
	elif left_weapon == left_fist and left_fist != null:
		_fist_off(false)


## True when the arm of a hand is not destroyed.
func is_arm_alive(is_right: bool) -> bool:
	if not is_right and left_arm_lost:
		return false
	var health := mech.health if mech != null else null
	var key := "Arm R" if is_right else "Arm L"
	return health == null or not health.hp.has(key) or health.is_part_alive(key)


## True when the hand holds only its fist (a weapon can go in it) and its arm is alive.
func is_hand_free(is_right: bool) -> bool:
	if (_picking_right if is_right else _picking_left):
		return false
	var fist := right_fist if is_right else left_fist
	return fist != null and is_instance_valid(fist) and (right_weapon if is_right else left_weapon) == fist \
			and is_arm_alive(is_right)


## True when this weapon is in a hand (not on the ground, not on the way).
func holds(weapon: MechWeapon) -> bool:
	return weapon != null and (weapon == right_weapon or weapon == left_weapon)


## Keeps a fist arm free for the punch clip while a melee attack plays, and at the relaxed hang
## otherwise (the melee animation keeps an arm that has an IK target: SkeletalMeleeAnimation).
func _update_fist_arms(delta: float) -> void:
	if right_fist == null and left_fist == null and not _swings_like_fist(right_weapon):
		return
	if _melee == null or not is_instance_valid(_melee):
		_melee = mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	# Also while the punch pose fades out: an arm with an IK target leaves the clip at once, so the hang target
	# before the fade ends snapped the fist to the hang (user report 2026-10-24 after the slower lowering).
	if _melee != null and (_melee.is_playing or _melee.is_fading()):
		_swing_hold = fist_hang_delay
	else:
		_swing_hold = maxf(_swing_hold - delta, 0.0)
	var hanging := _swing_hold <= 0.0
	for is_right: bool in [true, false]:
		var fist := right_fist if is_right else left_fist
		var held := right_weapon if is_right else left_weapon
		if (fist == null or held != fist) and not (is_right and _swings_like_fist(held)):
			continue
		var ik := arm_ik_right if is_right else arm_ik_left
		if is_right and _swings_like_fist(held) and ik.process_mode == Node.PROCESS_MODE_DISABLED:
			# The hammer arm's IK is off for the clip; the hang needs it (a null target leaves the arm to the clip).
			ik.process_mode = Node.PROCESS_MODE_INHERIT
		var hang := _free_right_target() if is_right else _free_left_target()
		var wanted: Node3D = hang if hanging else null
		if hang != null and ik.target != wanted:
			ik.target = wanted


## True while a fist arm punches and for fist_hang_delay seconds after (MechHandControl closes the hand
## then; at rest an empty hand is open and relaxed, user report 2026-10-22).
func is_punching() -> bool:
	return _swing_hold > 0.0


## The relaxed hang marker of a hand that holds its fist, also while the punch clip has the arm (its IK
## target is null then), or null. SkeletalArmRig poses a released fist arm at this hang under the punch
## clip, so the clip fades into the hang and the hand does not snap to it later (user report 2026-10-18).
func fist_hang_target(is_right: bool) -> Node3D:
	# The Pile Bunker punch clip has the arm: posed at the weapon's grip under the clip, so it fades back into it.
	var held := right_weapon if is_right else left_weapon
	if held is PileBunkerWeapon and is_instance_valid(held):
		return (held as PileBunkerWeapon).clip_hold_target()
	if is_right and _swings_like_fist(held):
		return _free_right_target()
	var fist := right_fist if is_right else left_fist
	if fist == null or not is_instance_valid(fist) or (right_weapon if is_right else left_weapon) != fist:
		return null
	return _free_right_target() if is_right else _free_left_target()


## A War Hammer or Baton in the right hand (user request 2026-10-30): when it does not swing, its arm hangs and swings
## with the stride like a fist arm (level shoulder block); the weapon rides the hand.
func _swings_like_fist(weapon: MechWeapon) -> bool:
	return weapon is MeleeWeapon and is_instance_valid(weapon) and (weapon as MeleeWeapon).data != null \
			and (weapon as MeleeWeapon).data.kind == WeaponData.Kind.HAMMER


func _make_hand_control() -> void:
	if mech == null or input == null or left_arm_view:
		return
	var control := WeaponHandControl.new()
	control.name = "WeaponHandControl"
	control.mech = mech
	control.weapons = self
	control.input = input
	mech.add_child.call_deferred(control)


## True when the left hand can hold this weapon besides the shields and the fist (user rule
## 2026-10-15): a one-hand gun, or the pile bunker (two Pile Bunkers allowed since 2026-10-30, user request;
## one attacks at a time). Never beside a two-hand weapon.
static func can_hold_left(left: WeaponData, right: WeaponData) -> bool:
	if left == null or left.scene == null or left.two_handed:
		return false
	if right != null and right.two_handed:
		return false
	match left.kind:
		WeaponData.Kind.GUN:
			return true
		WeaponData.Kind.PILE_BUNKER:
			return true
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
	ensure_left_grip(left_weapon)
	arm_ik_left.target = left_weapon.get_node("GripLeft")
	left_recoil.bind(left_weapon)
	left_recoil.kick_back = data.model_kick_back
	left_recoil.kick_up_deg = data.model_kick_up_deg


## A one-hand gun gets a GripLeft marker (the mirror of its GripRight) when it has none: the left arm
## reaches for it. WeaponPickup needs it before the weapon is in the left hand.
func ensure_left_grip(weapon: MechWeapon) -> void:
	if weapon.get_node_or_null("GripLeft") != null:
		return
	var grip := weapon.get_node("GripRight") as Node3D
	var hand := Marker3D.new()
	hand.name = "GripLeft"
	hand.position = mirror_point(grip.position)
	weapon.add_child(hand)


func _wire_shield(data: WeaponData) -> void:
	shield_mount.shield_node = torso.find_child("Shield", true, false)
	shield_mount.rest_mount = torso.find_child("ShieldMountRest", true, false)
	shield_mount.cover = torso.find_child("ShieldCover", true, false)
	shield_mount.shield_scale = data.shield_scale
	mech_shield.area_m2 = data.shield_area_m2
	# The hand holds the shield at its rest place; LMB raises it to the guard place (ShieldPose, user request
	# 2026-10-22): ShieldPose puts the hand behind the guard and ShieldMount moves the shield there.
	if shield_pose != null and shield_pose.rest != null and shield_pose.raised != null:
		shield_pose.rest.position = data.shield_hand
		shield_pose.raised.position = data.shield_hand
		shield_pose.shield_rest = shield_mount.rest_mount
		shield_pose.set_guard(data.shield_area_m2)
		shield_mount.pose = shield_pose
		shield_mount.move_to_cover = true
	arm_ik_left.target = left_hand


## The right arm is gone: its weapon stops and the right arm pose and IK stop.
func lose_right_weapon() -> void:
	if right_weapon == null and dropped_right == null:
		return
	var fist_in_hand := right_weapon != null and right_weapon == right_fist
	if fist_in_hand and is_arm_alive(true):
		return  # A fist is no part: nothing is lost while the arm is there.
	# A weapon that lies on the ground stays there for good (nobody owns it any more).
	_leave_dropped(true)
	if fist_in_hand:
		_retire_fist(true)
	elif right_weapon != null:
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
	if not is_arm_alive(true):
		_retire_fist(true)
	_refresh_fists()


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


## Model nodes of the right weapon in the hand (a forearm weapon's model sits on the forearm: get_model()).
## A fist and a weapon on the ground have none (they are no HP part).
func right_weapon_nodes() -> Array[Node3D]:
	if right_weapon == null or _is_fist(right_weapon):
		return []
	return _weapon_nodes(right_weapon)


## Model nodes of the left hand gun or Pile Bunker ("Weapon L", user request 2026-10-15); empty for a
## fist, a shield or an empty hand.
func left_weapon_nodes() -> Array[Node3D]:
	if left_weapon == null or left_weapon is MeleeWeapon:
		return []
	return _weapon_nodes(left_weapon)


## True when the left hand holds a weapon with its own HP part ("Weapon L"): a gun or the Pile Bunker.
func has_left_weapon_part() -> bool:
	return left_weapon != null and not left_weapon is MeleeWeapon


## The left hand weapon broke ("Weapon L"): it stops, the arm stays and hangs relaxed. Returns the nodes
## to drop as debris.
func lose_left_weapon() -> Array[Node3D]:
	var weapon := left_weapon
	if weapon == null or weapon is MeleeWeapon:
		return []
	var nodes := left_weapon_nodes()
	if active == weapon:
		active = null
	weapon.set_trigger(false)
	if weapon is PileBunkerWeapon:
		(weapon as PileBunkerWeapon).cancel()
		torso_pose.action_twist_deg = 0.0
	weapon.process_mode = Node.PROCESS_MODE_DISABLED
	left_weapon = null
	left_data = null
	if left_pose != null:
		left_pose.weapon = null
		left_pose.wants_raise = false
		left_pose.aim_amount = 0.0
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	if not _two_handed():
		arm_ik_left.target = _lost_left_target()
	_refresh_fists()
	return nodes


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
	# The empty hand is a fist now (user rule 2026-10-17).
	_refresh_fists()


## The left arm is gone: no shield, and the left arm IK stops.
func lose_left_arm() -> void:
	left_arm_lost = true
	lose_shield()
	_leave_dropped(false)
	_retire_fist(false)
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
	weapon_pose.aim_shift = Vector3.ZERO
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


## True when the hand can let go of this weapon on a knock-down: a hand gun or a rifle (the pile bunker and
## the fist stay, the shields stay), and the Auto Cannon only with drop_forearm_guns.
func can_drop(weapon: MechWeapon) -> bool:
	if weapon is ForearmGunWeapon and not drop_forearm_guns:
		return false
	return is_droppable(weapon)


## True for the weapons that leave the hand: guns (also the Auto Cannon) and beam rifles. Not the pile
## bunker, the hammer, the fists and the shields (user rule 2026-10-17).
func is_droppable(weapon: MechWeapon) -> bool:
	if weapon == null or not is_instance_valid(weapon) or weapon is MeleeWeapon or weapon is PileBunkerWeapon:
		return false
	return (weapon is GunWeapon or weapon is BeamRifleWeapon) and torso.is_ancestor_of(weapon)


## True when a hand holds a weapon that a knock-down face down drops.
func has_droppable_weapon() -> bool:
	return can_drop(right_weapon) or can_drop(left_weapon)


## True while a hand weapon lies on the ground.
func is_hand_weapon_dropped() -> bool:
	return is_instance_valid(dropped_right) or is_instance_valid(dropped_left)


## True when the right (left) arm has no weapon in the hand: the weapon lies on the ground, or the hand
## holds only its fist (the knock-down clip moves the arm then). The left hand of a two-hand rifle counts: it
## let go of the forestock.
func is_arm_free(right: bool) -> bool:
	if right:
		return is_instance_valid(dropped_right) or (right_weapon != null and right_weapon == right_fist)
	return is_instance_valid(dropped_left) or (left_weapon != null and left_weapon == left_fist) \
			or (is_instance_valid(dropped_right) and weapon_pose.left_grip_target != null)


## The hands let go of their guns and rifles: each flies from the hand to a rest place on the ground
## near stand_point (the place where the mech will stand after the get-up; forward is its facing, flat).
## The fall moves the mech; the rest places are ahead of the stand place, to the sides. Only this mech
## takes them back (user rule 2026-10-17).
func drop_hand_weapons(stand_point: Vector3, forward: Vector3) -> void:
	var level := get_world()
	for is_right: bool in [true, false]:
		var weapon := right_weapon if is_right else left_weapon
		if not can_drop(weapon):
			continue
		var two_hand := is_right and two_handed_left_grip() and weapon_pose.left_grip_target != null
		_let_go(weapon, is_right, two_hand, false)
		var place := _drop_spot(stand_point, forward, is_right, two_hand, 1.0)
		var drop := WeaponDrop.create(weapon, level, place[0], place[1], two_hand, max_ground_weapons)
		drop.owner_weapons = self
		if is_right:
			dropped_right = drop
		else:
			dropped_left = drop


## Rest place of a dropped weapon: [grip spot, facing]. Ahead of stand_point by drop_ahead, to the side of a
## one-hand gun, across in front of the mech for a two-hand rifle. scale shortens all the distances.
func _drop_spot(stand_point: Vector3, forward: Vector3, is_right: bool, two_hand: bool, scale: float) -> Array:
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var side := forward.cross(Vector3.UP)
	var spot := stand_point + forward * drop_ahead * scale
	var face := forward
	if two_hand:
		spot += side * drop_rifle_side * scale
		face = -side
	else:
		var out := 1.0 if is_right else -1.0
		spot += side * drop_side * scale * out
		face = forward.rotated(Vector3.UP, -deg_to_rad(drop_gun_yaw_deg) * out)
	return [spot, face]


## True when a Tab drop can let go of the weapon of this hand now (user rule 2026-10-17): a gun or a
## rifle in the hand, and the mech is free (on its feet, not reaching for a weapon).
func can_tab_drop(is_right: bool) -> bool:
	if mech.is_wrecked or mech.is_fallen or _picking_right or _picking_left:
		return false
	return is_droppable(right_weapon if is_right else left_weapon)


## Tab drop (user rule 2026-10-17): the hand lets go of its weapon. It lands in front of the mech, free for
## any mech to take, and the empty hand becomes a fist. is_right: the hand slot (a two-hand rifle is the
## right one). Returns the drop, or null when nothing can be dropped.
func drop_hand(is_right: bool) -> WeaponDrop:
	if not can_tab_drop(is_right):
		return null
	var weapon := right_weapon if is_right else left_weapon
	var rifle := is_right and right_data != null and right_data.two_handed
	var forward := Basis(Vector3.UP, mech.get_aim_yaw()) * Vector3.FORWARD
	var place := _drop_spot(mech.global_position, forward, is_right, rifle, tab_drop_scale)
	_let_go(weapon, is_right, rifle and weapon_pose.left_grip_target != null, true)
	var drop := WeaponDrop.create(weapon, get_world(), place[0], place[1], rifle, max_ground_weapons)
	_refresh_fists()
	return drop


## The hand lets go of its weapon at a given place (the mech died): a free drop, no fist after.
func drop_hand_at(is_right: bool, spot: Vector3, face: Vector3) -> WeaponDrop:
	var weapon := right_weapon if is_right else left_weapon
	if not can_drop(weapon):
		return null
	var rifle := is_right and right_data != null and right_data.two_handed
	_let_go(weapon, is_right, rifle and weapon_pose.left_grip_target != null, true)
	return WeaponDrop.create(weapon, get_world(), spot, face, rifle, max_ground_weapons)


## The hand lets go of the weapon: it stops, the pose and the arm IK of that hand stop, and the arm
## goes to its relaxed hang (the knock-down clip moves it). The weapon is disabled for good (it lies on the
## ground; WeaponDrop does that too). ownerless: the weapon will not come back to this hand by itself (Tab
## drop, death), so the pose forgets it and the slot data goes.
func _let_go(weapon: MechWeapon, is_right: bool, two_hand: bool, ownerless: bool) -> void:
	# First: WeaponPartSync takes the HP part off the mech while the weapon is still known as the hand's.
	hand_weapon_released.emit(is_right, weapon)
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
		weapon_recoil.unbind(weapon)
		reset_grips()
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
		one_hand_hold = false
		if free_aim != null:
			free_aim.unsteady = 0.0
		_relax_arm(arm_ik_right, _free_right_target())
		if two_hand:
			_relax_arm(arm_ik_left, _lost_left_target())
		if ownerless:
			right_data = null
			weapon_pose.weapon = null
			weapon_pose.right_grip_target = null
			weapon_pose.right_grip_rest = null
			weapon_pose.right_grip_aim = null
			weapon_pose.left_grip_target = null
			weapon_pose.left_grip_rest = null
			weapon_pose.left_grip_aim = null
	else:
		if left_recoil != null:
			left_recoil.unbind(weapon)
		left_weapon = null
		left_pose.aim_amount = 0.0
		left_pose.wants_raise = false
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		_relax_arm(arm_ik_left, _free_left_target())
		if ownerless:
			left_data = null
			left_pose.weapon = null


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


## WeaponPickup: the hand starts to reach for a weapon on the ground. Its fist goes off (the pick-up runs the
## arm) and stays off until equip_dropped or cancel_hand_pickup.
func begin_hand_pickup(is_right: bool) -> void:
	if is_right:
		_picking_right = true
	else:
		_picking_left = true
	_fist_off(is_right)


## WeaponPickup: the reach ended before the weapon was in the hand (a knock-down, a broken arm): the arm goes
## back to the relaxed hang and the hand gets its fist back.
func cancel_hand_pickup(is_right: bool) -> void:
	relax_arm(is_right)
	clear_hand_pickup(is_right)


## WeaponPickup: the hand is not reaching any more (the weapon is gone from the hand, or the reach ended).
func clear_hand_pickup(is_right: bool) -> void:
	if is_right:
		_picking_right = false
	else:
		_picking_left = false
	_refresh_fists()


## True while a hand reaches for a weapon (the pick-up of this mech runs).
func is_picking() -> bool:
	return _picking_right or _picking_left


## WeaponPickup: the hands hold the weapon of a drop. It goes under the frame and into the slot of the hand,
## the pose and the arm IK are wired for it, and the arms reach for its grips. The weapon keeps its place in
## the world and does not work yet (equip_dropped). Its recoil, controller and HP part follow.
func take_from_ground(drop: WeaponDrop, is_right: bool) -> void:
	var weapon := drop.weapon
	if not is_instance_valid(weapon):
		return
	var data := weapon.data
	var place := weapon.global_transform
	weapon.reparent(torso, true)
	if is_right:
		if dropped_right == drop:
			dropped_right = null
		weapon.rebind(self)
		right_weapon = weapon
		right_data = data
		_wire_right(data)
		arm_ik_right.process_mode = Node.PROCESS_MODE_INHERIT
		if data.two_handed and is_arm_alive(false):
			arm_ik_left.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		if dropped_left == drop:
			dropped_left = null
		if left_view == null:
			_make_left_view()
		weapon.rebind(left_view)
		left_weapon = weapon
		left_data = data
		_wire_left_weapon(data)
		arm_ik_left.process_mode = Node.PROCESS_MODE_INHERIT
	weapon.global_transform = place
	# Still disabled, with its pose and recoil: they work again at equip_dropped.
	weapon.process_mode = Node.PROCESS_MODE_DISABLED
	if is_right:
		for node: Node in [weapon_pose, weapon_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	drop.queue_free()


## WeaponPickup: the weapon is in the hand again: it works, its pose and recoil run, the torso and the
## aim camera take their values for it. The pose puts the weapon in its rest place.
func equip_dropped(weapon: MechWeapon, is_right: bool) -> void:
	weapon.process_mode = Node.PROCESS_MODE_INHERIT
	if is_right:
		torso_pose.aim_twist_deg = right_data.aim_twist_deg
		torso_pose.aim_tilt_deg = right_data.aim_tilt_deg
		camera_ads.enabled = right_data.two_handed and right_data.zoom_fov > 0.0
		if camera_ads.enabled:
			camera_ads.aim_fov = right_data.zoom_fov
		weapon_pose.aim_amount = 0.0
		weapon_pose.wants_raise = false
		arm_ik_right.pole_direction = weapon_pose.right_pole_rest
		if weapon_pose.left_grip_target != null:
			arm_ik_left.pole_direction = weapon_pose.left_pole_rest
		for node: Node in [weapon_pose, weapon_recoil]:
			node.process_mode = Node.PROCESS_MODE_INHERIT
		# The left arm is gone: the rifle is held in one hand, low at the hip.
		if right_data.two_handed and not is_arm_alive(false):
			_hold_one_hand()
		_picking_right = false
		if right_data.two_handed:
			_picking_left = false
	else:
		left_pose.aim_amount = 0.0
		left_pose.wants_raise = false
		arm_ik_left.pole_direction = left_pose.right_pole_rest
		for node: Node in [left_pose, left_recoil]:
			node.process_mode = Node.PROCESS_MODE_INHERIT
		_picking_left = false
	_refresh_fists()
	hand_weapon_equipped.emit(is_right, weapon)


## Where a hand holds the weapon at rest: the grip markers of a two-hand rifle go to their rest places
## (the pose moves them while aiming).
func reset_grips() -> void:
	if weapon_pose.right_grip_target != null and weapon_pose.right_grip_rest != null:
		weapon_pose.right_grip_target.position = weapon_pose.right_grip_rest.position
	if weapon_pose.left_grip_target != null and weapon_pose.left_grip_rest != null:
		weapon_pose.left_grip_target.position = weapon_pose.left_grip_rest.position


## The weapon on the ground has no owner any more (its arm is gone, or the mech is): it stays where it is and
## any mech may take it.
func _leave_dropped(is_right: bool) -> void:
	var drop := dropped_right if is_right else dropped_left
	if is_right:
		dropped_right = null
	else:
		dropped_left = null
	if is_instance_valid(drop):
		drop.owner_weapons = null


## The weapons on the ground that belonged to this mech (knock-down drops) have no owner now: the mech died
## or is gone (user rule 2026-10-17).
func release_ground_weapons() -> void:
	_leave_dropped(true)
	_leave_dropped(false)


## The mech is gone: its weapons on the ground stay for any mech.
func _exit_tree() -> void:
	release_ground_weapons()


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


func _physics_process(delta: float) -> void:
	_update_fist_arms(delta)
	if mech.is_wrecked or mech.is_fallen:
		# Down, stunned or dead: no weapon fires (a trigger held before stays released).
		for weapon: MechWeapon in [right_weapon, left_weapon, back_left, back_right]:
			if weapon != null:
				weapon.set_trigger(false)
		weapon_pose.wants_raise = false
		if left_pose != null:
			left_pose.wants_raise = false
		shoulder_brace.step(delta, false)
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
	# A shoulder cannon that waits for its shot: the mech stops and braces (ShoulderBrace).
	shoulder_brace.armed_cannons = _shoulder_armed_count()
	shoulder_brace.step(delta, _shoulder_wants_brace())
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


## A rigged mech takes the brace stance while a shoulder cannon waits and fires: a skeleton modifier before
## the arm rig (BracePose).
func _make_brace_pose() -> void:
	if not animate_free_left_arm or left_arm_view or mech == null:
		return
	var skeleton := mech.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var pose := BracePoseScript.new()
	pose.name = "BracePose"
	pose.brace = shoulder_brace
	pose.mech = mech
	skeleton.add_child(pose)


## How many shoulder cannons wait for the brace now.
func _shoulder_armed_count() -> int:
	var count := 0
	for weapon: MechWeapon in [back_left, back_right]:
		if weapon is ShoulderGunWeapon and (weapon as ShoulderGunWeapon).wants_brace():
			count += 1
	return count


## True when a shoulder cannon waits for the brace.
func _shoulder_wants_brace() -> bool:
	for weapon: MechWeapon in [back_left, back_right]:
		if weapon is ShoulderGunWeapon and (weapon as ShoulderGunWeapon).wants_brace():
			return true
	return false


## The two arm guns (right and left hand) work together (dual guns, user rule 2026-10-15), like the
## two missile pods. Every other weapon works alone.
func _is_arm_gun(weapon: MechWeapon) -> bool:
	return weapon is GunWeapon and (weapon == right_weapon or weapon == left_weapon)


## True when the weapon may fire now: it is the active one, a melee weapon, or it works together with
## the active one (the missile pods, the two arm guns, the two shoulder cannons: user rule 2026-10-16).
func _may_fire(weapon: MechWeapon) -> bool:
	return weapon == active or weapon.is_melee() \
			or (weapon is MissilePodWeapon and active is MissilePodWeapon) \
			or (weapon is ShoulderGunWeapon and active is ShoulderGunWeapon) \
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
	if weapon is ShoulderGunWeapon:
		for other in wants:
			if other != weapon and other is ShoulderGunWeapon and (wants[other] or _is_busy(other)):
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


func get_lock_speed() -> float:
	return mech.stats.lock_on_speed if mech.stats != null else 1.0
