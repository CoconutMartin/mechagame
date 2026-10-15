class_name WeaponPickup
extends SkeletonModifier3D
## The mech takes its dropped weapons back after the get-up (user request 2026-10-15). A knock-down face
## down made the hands let go of their guns (WeaponController.drop_hand_weapons); when the get-up ends,
## SkeletalStaggerAnimation calls begin(). Keyframed by code, no clip:
##   REACH: the body crouches (knees bend, the hips go back, the body leans forward: CrouchPose) and each
##          hand goes to the grip of its weapon on the ground. The mech stays "fallen" (no control, no fire).
##   GRAB:  the weapon snaps into the hand (the grip goes to the palm) and the hand closes.
##   LIFT:  the body stands up and the weapon goes from the ground to its hold place.
## Then the weapon works again (WeaponController.equip_dropped) and the mech is free.
## A new knock-down or stun calls interrupt(): a weapon in the hand is put in its place, one still on the
## ground stays there, and the pick-up starts again after the next get-up. Death stops it.
## A skeleton modifier must be a child of the Skeleton3D. This node must come before SkeletalArmRig (the arms
## follow the crouch); SkeletalStaggerAnimation puts it there.

signal finished

enum Phase { IDLE, REACH, GRAB, LIFT, FADE }

@export var mech: Mech
@export var weapons: WeaponController

@export_group("Timing")
## Seconds to crouch and reach, to hold the grip, to stand up with the weapon, and to let go of the crouch
## when the pick-up is interrupted.
@export var reach_time: float = 1.0
@export var grab_time: float = 0.3
@export var lift_time: float = 1.0
@export var fade_time: float = 0.2
## The hands start to move this part of the reach time after the crouch starts.
@export_range(0.0, 0.9) var hand_delay: float = 0.15
@export_group("Crouch")
## Hip bend forward and extra bend at the waist (degrees), hips moved back (m), inner knee angle at
## the full crouch (degrees), and how far the knees point to the side.
@export var lean_deg: float = 40.0
@export var torso_lean_deg: float = 30.0
@export var hips_back: float = 0.6
@export var knee_deg: float = 70.0
@export var knee_out: float = 0.3
## The hips move toward a weapon that lies to the side: this part of its side distance (m), at most max_hip_shift.
@export var hip_shift_part: float = 0.3
@export var max_hip_shift: float = 1.0
@export_group("Reach")
## A weapon with its grip farther than this from the mech (m, flat) slides toward it before the mech bends
## (a second knock-down, or a fall that a wall blocked, left the weapon out of reach).
@export var max_reach_distance: float = 3.8

var phase: Phase = Phase.IDLE

var _time: float = 0.0
var _fade_from: float = 0.0
## Per weapon: {drop, weapon, right (the hand slot), grabbed, grab_local}.
var _drops: Array[Dictionary] = []
## Per hand: {ik, right, marker, grip (marker name), drop, start (mech space)}.
var _hands: Array[Dictionary] = []
var _shift_x: float = 0.0


## True from begin() until the weapons are back (the crouch letting go after an interrupt does not count).
func is_picking() -> bool:
	return phase != Phase.IDLE and phase != Phase.FADE


## Starts the pick-up of the weapons on the ground. The mech stays fallen until the end.
func begin() -> void:
	if phase != Phase.IDLE or mech.is_wrecked:
		return
	_drops.clear()
	_hands.clear()
	for is_right: bool in [true, false]:
		var drop := weapons.dropped_right if is_right else weapons.dropped_left
		if is_instance_valid(drop) and is_instance_valid(drop.weapon):
			_drops.append({"drop": drop, "weapon": drop.weapon, "right": is_right, "grabbed": false, "grab_local": Transform3D.IDENTITY})
	if _drops.is_empty():
		mech.end_fall()
		finished.emit()
		return
	weapons.reset_grips()
	var side := 0.0
	for entry in _drops:
		var drop: WeaponDrop = entry.drop
		_bring_in_reach(drop)
		_add_hand(entry.right, &"GripRight" if entry.right else &"GripLeft", drop)
		if entry.right and weapons.weapon_pose.left_grip_target != null:
			_add_hand(false, &"GripLeft", drop)
	for hand in _hands:
		side += (mech.global_transform.affine_inverse() * (hand.drop as WeaponDrop).get_grip_position(hand.grip)).x
	# Skeleton space +X is the mech's left; the weapon side is mech space +X (right).
	_shift_x = clampf(-side / _hands.size() * hip_shift_part, -max_hip_shift, max_hip_shift)
	phase = Phase.REACH
	_time = 0.0


## A new knock-down or stun: a weapon in the hand goes to its place, one on the ground stays, the crouch lets go.
func interrupt() -> void:
	if not is_picking():
		return
	if phase == Phase.REACH:
		for hand in _hands:
			weapons.relax_arm(hand.right)
	else:
		_equip_all()
	_free_markers()
	_fade_from = get_crouch()
	phase = Phase.FADE
	_time = 0.0


## 0 = standing, 1 = full crouch.
func get_crouch() -> float:
	match phase:
		Phase.REACH:
			return smoothstep(0.0, 1.0, _time / maxf(reach_time, 0.01))
		Phase.GRAB:
			return 1.0
		Phase.LIFT:
			return 1.0 - smoothstep(0.0, 1.0, _time / maxf(lift_time, 0.01))
		Phase.FADE:
			return _fade_from * (1.0 - clampf(_time / maxf(fade_time, 0.01), 0.0, 1.0))
	return 0.0


func _physics_process(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	if mech.is_wrecked:
		# The mech died: a weapon in the hand stays there, one on the ground stays there.
		if phase != Phase.REACH and phase != Phase.FADE:
			_equip_all()
		_free_markers()
		phase = Phase.IDLE
		return
	_time += delta
	match phase:
		Phase.REACH:
			_move_markers()
			if _time >= reach_time:
				_grab()
		Phase.GRAB:
			if _time >= grab_time:
				phase = Phase.LIFT
				_time = 0.0
		Phase.LIFT:
			_move_weapons()
			if _time >= lift_time:
				_finish()
		Phase.FADE:
			if _time >= fade_time:
				phase = Phase.IDLE


func _process_modification_with_delta(_delta: float) -> void:
	var amount := get_crouch()
	if amount <= 0.0 or phase == Phase.IDLE:
		return
	CrouchPose.apply(get_skeleton(), amount, lean_deg, torso_lean_deg, hips_back, knee_deg, knee_out, _shift_x)


## A hand that reaches for a grip: its IK target is a marker that moves from the hand to the grip.
func _add_hand(right: bool, grip: StringName, drop: WeaponDrop) -> void:
	var ik := weapons.arm_ik_right if right else weapons.arm_ik_left
	var marker := Marker3D.new()
	marker.name = "PickupHandR" if right else "PickupHandL"
	mech.add_child(marker)
	var start := _hand_position(ik)
	marker.global_position = start
	ik.target = marker
	ik.process_mode = Node.PROCESS_MODE_INHERIT
	var out := 1.0 if right else -1.0
	ik.pole_direction = Vector3(0.4 * out, -1.0, 0.5)
	_hands.append({"ik": ik, "right": right, "marker": marker, "grip": grip, "drop": drop,
			"start": mech.global_transform.affine_inverse() * start})


## Where a hand (the palm socket) is now.
static func _hand_position(ik: TwoBoneIK) -> Vector3:
	return ik.mid_joint.global_position + ik.mid_joint.global_basis.y * -ik.lower_length


## A weapon out of reach slides toward the mech first.
func _bring_in_reach(drop: WeaponDrop) -> void:
	var flat := drop.get_grip_position(&"GripRight") - mech.global_position
	flat.y = 0.0
	if flat.length() <= max_reach_distance:
		return
	drop.slide_by(-flat.normalized() * (flat.length() - max_reach_distance * 0.85), reach_time * 0.6)


## REACH: the hands go from where they hang to the grips.
func _move_markers() -> void:
	var k := smoothstep(0.0, 1.0, clampf((_time / maxf(reach_time, 0.01) - hand_delay) / (1.0 - hand_delay), 0.0, 1.0))
	for hand in _hands:
		var start := mech.global_transform * (hand.start as Vector3)
		var grip := (hand.drop as WeaponDrop).get_grip_position(hand.grip)
		(hand.marker as Marker3D).global_position = start.lerp(grip, k)


## The weapons go into the hands: each grip moves to the palm, the weapon goes back to the mech frame.
func _grab() -> void:
	phase = Phase.GRAB
	_time = 0.0
	for entry in _drops:
		var drop: WeaponDrop = entry.drop
		var weapon: MechWeapon = entry.weapon
		var hand := _hand_of(entry.right)
		var gap := _hand_position(hand.ik) - drop.get_grip_position(hand.grip)
		weapon.global_position += gap
		weapons.grab_dropped(drop)
		entry.grabbed = true
		entry.grab_local = weapon.transform
	_free_markers()


func _hand_of(right: bool) -> Dictionary:
	for hand in _hands:
		if hand.right == right:
			return hand
	return {}


## LIFT: each weapon goes from the ground to its hold place (in the mech frame, so the body standing up
## lifts it too).
func _move_weapons() -> void:
	var t := smoothstep(0.0, 1.0, _time / maxf(lift_time, 0.01))
	for entry in _drops:
		if not entry.grabbed or not is_instance_valid(entry.weapon):
			continue
		(entry.weapon as MechWeapon).transform = (entry.grab_local as Transform3D).interpolate_with(_rest_of(entry.right), t)


func _rest_of(right: bool) -> Transform3D:
	return weapons.weapon_pose.rest_transform if right else weapons.left_pose.rest_transform


## The weapons are in the hands and work again: the mech is free.
func _finish() -> void:
	_equip_all()
	phase = Phase.IDLE
	_time = 0.0
	mech.end_fall()
	finished.emit()


func _equip_all() -> void:
	for entry in _drops:
		if not entry.grabbed or not is_instance_valid(entry.weapon):
			continue
		entry.weapon.transform = _rest_of(entry.right)
		weapons.equip_dropped(entry.weapon, entry.right)
		entry.grabbed = false
	_drops.clear()


func _free_markers() -> void:
	for hand in _hands:
		if is_instance_valid(hand.marker):
			(hand.marker as Marker3D).queue_free()
	_hands.clear()
