class_name WeaponController
extends Node
## Mounts the loadout weapons on the mech and sends the buttons to them.
## Right arm weapon: a model under the torso, posed by WeaponPose, held by the right hand.
##   One-hand gun: RMB raises and fires (hip fire). Blade: RMB lunge slash.
##   Two-hand weapon: RMB aims down sight (zoom), LMB fires. The left hand holds the weapon.
## Left arm: a shield (LMB lifts it). Back units: missile pods, Q = left, E = right.
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

var right_weapon: MechWeapon
var back_left: MechWeapon
var back_right: MechWeapon
var right_data: WeaponData
var left_data: WeaponData
## The weapon in use now (null = none).
var active: MechWeapon = null


func _ready() -> void:
	# After MechInput (-10), before WeaponPose (5) and the weapons.
	process_physics_priority = 1


func mount(loadout: Loadout, assembler: MechAssembler) -> void:
	right_data = loadout.weapon_right
	left_data = loadout.weapon_left
	if right_data != null and right_data.scene != null:
		right_weapon = _add_weapon(right_data, "RightWeapon")
		_wire_right(right_data)
	var has_shield := left_data != null and left_data.kind == WeaponData.Kind.SHIELD
	if has_shield:
		assembler.attach(left_data.scene)
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
	weapon_pose.rest_transform = data.rest_transform
	weapon_pose.aim_origin = data.aim_anchor
	weapon_pose.right_pole_rest = data.right_pole_rest
	weapon_pose.right_pole_aim = data.right_pole_aim
	right_weapon.transform = data.rest_transform
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


func _set_shield_enabled(enabled: bool) -> void:
	mech_shield.enabled = enabled
	var mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	shield_pose.process_mode = mode
	shield_mount.process_mode = mode


func _two_handed() -> bool:
	return right_data != null and right_data.two_handed


func _physics_process(_delta: float) -> void:
	var wants := {}
	if right_weapon != null:
		wants[right_weapon] = input.left_fire_held if _two_handed() else input.fire_held
	if back_left != null:
		wants[back_left] = input.back_left_held
	if back_right != null:
		wants[back_right] = input.back_right_held
	# One weapon at a time (not counting the blade).
	if active != null and not (wants.get(active, false) or _is_busy(active)):
		active = null
	if active == null:
		for weapon in wants:
			if wants[weapon] and not weapon is BladeWeapon:
				active = weapon
				break
	for weapon in wants:
		var allowed: bool = weapon == active or weapon is BladeWeapon
		weapon.set_trigger(wants[weapon] and allowed)
	if right_weapon != null:
		var right_on := right_weapon == active
		if _two_handed():
			weapon_pose.wants_raise = input.aim_held or (input.left_fire_held and right_on)
		else:
			weapon_pose.wants_raise = input.fire_held and right_on and right_data.kind == WeaponData.Kind.GUN
		if input.reload_pressed:
			right_weapon.start_reload()
	if input.reload_pressed:
		for pod in [back_left, back_right]:
			if pod != null:
				pod.start_reload()


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
