class_name WeaponController
extends Node
## Mounts the loadout weapons on the mech and sends the buttons to them.
## Right arm weapon: a model under the torso, posed by WeaponPose, held by the right hand.
##   One-hand gun: RMB raises and fires (hip fire). Blade: RMB lunge slash.
##   Two-hand weapon: RMB aims down sight (zoom), LMB fires. The left hand holds the weapon.
## Left arm: a shield (LMB lifts it). Back units: missile pods, Q = left, E = right.
## Left arm lost with a two-hand weapon: the right hand holds it alone, low at the hip like the
## one-hand rifle, and the aim ring is unsteady (FreeAim.unsteady). The keys stay the same.
## Only one weapon works at a time: the first one whose button is pressed stays active until it is
## done (trigger released, missiles launched). The blade is the exception: it works any time.
## MechAssembler calls mount() before the other nodes start.

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

@export_group("One-hand hold")
## Right hand (GripRight) place in the aim pose, torso space. The one-hand rifle hip hold.
@export var one_hand_grip_aim: Vector3 = Vector3(2.38, 0.6, -1.84)
## Right hand place in the rest pose, torso space.
@export var one_hand_grip_rest: Vector3 = Vector3(2.38, 0.65, -1.69)
## Weapon turn in the rest pose (muzzle a little down), in degrees.
@export var one_hand_rest_pitch_deg: float = -4.6
## Elbow direction of the right arm (out and down).
@export var one_hand_pole: Vector3 = Vector3(0.4, -1.0, 0.5)
@export_group("")

## True when a two-hand weapon is held in the right hand alone.
var one_hand_hold: bool = false

var right_weapon: MechWeapon
var back_left: MechWeapon
var back_right: MechWeapon
var right_data: WeaponData
var left_data: WeaponData
## The weapon in use now (null = none).
var active: MechWeapon = null
## Shield model nodes on the frame (PartBreaker drops them when the shield breaks).
var shield_nodes: Array[Node3D] = []
## Right arm hold offset (ArmPart.hold_offset), torso space: added to every right weapon hold place.
var hold_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	# After MechInput (-10), before WeaponPose (5) and the weapons.
	process_physics_priority = 1


func mount(loadout: Loadout, assembler: MechAssembler) -> void:
	right_data = loadout.weapon_right
	left_data = loadout.weapon_left
	hold_offset = loadout.arm_right.hold_offset if loadout.arm_right is ArmPart else Vector3.ZERO
	if right_data != null and right_data.scene != null:
		right_weapon = _add_weapon(right_data, "RightWeapon")
		_wire_right(right_data)
	var has_shield := left_data != null and left_data.kind == WeaponData.Kind.SHIELD
	if has_shield:
		shield_nodes = assembler.attach(left_data.scene)
		_wire_shield(left_data)
	_set_shield_enabled(has_shield)
	if not has_shield and not _two_handed():
		arm_ik_left.target = left_hand
	if loadout.back_left != null and loadout.back_left.scene != null:
		back_left = _add_weapon(loadout.back_left, "BackLeft")
	if loadout.back_right != null and loadout.back_right.scene != null:
		back_right = _add_weapon(loadout.back_right, "BackRight")


func _add_weapon(data: WeaponData, node_name: String) -> MechWeapon:
	var weapon := data.scene.instantiate() as MechWeapon
	weapon.name = node_name
	torso.add_child(weapon)
	weapon.setup(data, self)
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


func _wire_shield(data: WeaponData) -> void:
	shield_mount.shield_node = torso.find_child("Shield", true, false)
	shield_mount.rest_mount = torso.find_child("ShieldMountRest", true, false)
	shield_mount.cover = torso.find_child("ShieldCover", true, false)
	shield_mount.shield_scale = data.shield_scale
	mech_shield.area_m2 = data.shield_area_m2
	arm_ik_left.target = left_hand


## The right arm is gone: its weapon stops and the right arm pose and IK stop.
func lose_right_weapon() -> void:
	if right_weapon == null:
		return
	if active == right_weapon:
		active = null
	right_weapon.set_trigger(false)
	right_weapon.process_mode = Node.PROCESS_MODE_DISABLED
	if two_handed_left_grip():
		arm_ik_left.target = left_hand
	right_weapon = null
	right_data = null
	weapon_pose.aim_amount = 0.0
	weapon_pose.wants_raise = false
	one_hand_hold = false
	if free_aim != null:
		free_aim.unsteady = 0.0
	for node: Node in [weapon_pose, weapon_recoil, arm_ik_right]:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	torso_pose.aim_twist_deg = 0.0
	torso_pose.aim_tilt_deg = 0.0
	torso_pose.action_twist_deg = 0.0
	camera_ads.enabled = false


## True when the left hand holds the right weapon (two-hand weapon).
func two_handed_left_grip() -> bool:
	return right_data != null and right_data.two_handed


## The shield is gone (broken, or the left arm is gone).
func lose_shield() -> void:
	if left_data == null:
		return
	left_data = null
	shield_nodes = []
	_set_shield_enabled(false)
	mech_shield.force_up = false


## The left arm is gone: no shield, and the left arm IK stops.
func lose_left_arm() -> void:
	lose_shield()
	arm_ik_left.process_mode = Node.PROCESS_MODE_DISABLED
	if _two_handed() and right_weapon != null:
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
		return
	var wants := {}
	if right_weapon != null:
		wants[right_weapon] = input.left_fire_held if _two_handed() else input.fire_held
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
		var allowed: bool = weapon == active or weapon.is_melee() \
				or (weapon is MissilePodWeapon and active is MissilePodWeapon)
		weapon.set_trigger(wants[weapon] and allowed)
	if right_weapon != null:
		var right_on := right_weapon == active
		if _two_handed():
			weapon_pose.wants_raise = input.aim_held or (right_on and (input.left_fire_held or right_weapon.is_busy()))
		else:
			weapon_pose.wants_raise = input.fire_held and right_on and right_data.kind == WeaponData.Kind.GUN
		if input.reload_pressed:
			right_weapon.start_reload()
	if input.reload_pressed:
		for pod in [back_left, back_right]:
			if pod != null:
				pod.start_reload()


func _still_in_use(weapon: MechWeapon, wants: Dictionary) -> bool:
	if wants.get(weapon, false) or _is_busy(weapon):
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
	if right_weapon != null:
		slots.append(["R", right_weapon])
	if left_data != null:
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
