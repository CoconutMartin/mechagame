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
## Pick-up by the player (user rules 2026-10-17, begin_manual): Tab plus a mouse button takes a weapon from
## the ground within 3 m, any weapon that is free (a Tab drop, a dead mech's weapon) and the mech's own
## knock-down drops. The same crouch, grab and lift at manual_speed times the speed (about 1.2 s in all). The
## body turns toward the weapon during the reach. The mech cannot move or fire meanwhile (it is "fallen"), the
## camera stays where the player aims (the free look of a mech that is down: MechCameraRig), the hand that
## takes the weapon holds no fist until the weapon is in it.
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
@export_group("Pick-up by the player")
## The phases run this many times faster than after a knock-down (user rule 2026-10-17: about 1.2 s in all).
@export var manual_speed: float = 2.0
## The body turns toward the weapon during this part of the reach.
@export_range(0.1, 1.0) var turn_share: float = 0.4
## A weapon closer than this to the mech (m, flat) slides out in front of the feet first, so the hands
## do not reach into the legs.
@export var min_reach_distance: float = 1.8
@export_group("")

var phase: Phase = Phase.IDLE

var _time: float = 0.0
var _fade_from: float = 0.0
## Per weapon: {drop, weapon, right (the hand slot), grabbed, grab_local}.
var _drops: Array[Dictionary] = []
## Per hand: {ik, right, marker, grip (marker name), drop, start (mech space)}.
var _hands: Array[Dictionary] = []
var _shift_x: float = 0.0
## True for a pick-up the player started (Tab); the phase times run at _speed.
var _manual: bool = false
var _speed: float = 1.0
var _heading_from: float = 0.0
var _heading_to: float = 0.0


func _ready() -> void:
	if weapons != null:
		weapons.pickup = self


func _exit_tree() -> void:
	if weapons != null and weapons.pickup == self:
		weapons.pickup = null


## True from begin() until the weapons are back (the crouch letting go after an interrupt does not count).
func is_picking() -> bool:
	return phase != Phase.IDLE and phase != Phase.FADE


## True during a pick-up that the player started with Tab.
func is_manual() -> bool:
	return _manual and is_picking()


## Starts the pick-up of the weapons on the ground. The mech stays fallen until the end.
func begin() -> void:
	if phase != Phase.IDLE or mech.is_wrecked:
		return
	_drops.clear()
	_hands.clear()
	_manual = false
	_speed = 1.0
	for is_right: bool in [true, false]:
		var drop := weapons.dropped_right if is_right else weapons.dropped_left
		if is_instance_valid(drop) and is_instance_valid(drop.weapon):
			var both := is_right and weapons.weapon_pose.left_grip_target != null and weapons.is_arm_alive(false)
			_drops.append({"drop": drop, "weapon": drop.weapon, "right": is_right, "both": both, "grabbed": false,
					"grab_local": Transform3D.IDENTITY})
	if _drops.is_empty():
		mech.end_fall()
		finished.emit()
		return
	weapons.reset_grips()
	var side := 0.0
	for entry in _drops:
		var drop: WeaponDrop = entry.drop
		drop.reserved_by = self
		_bring_in_reach(drop)
		weapons.begin_hand_pickup(entry.right)
		_add_hand(entry.right, &"GripRight" if entry.right else &"GripLeft", drop)
		if entry.both:
			weapons.begin_hand_pickup(false)
			_add_hand(false, &"GripLeft", drop)
	for hand in _hands:
		side += (mech.global_transform.affine_inverse() * (hand.drop as WeaponDrop).get_grip_position(hand.grip)).x
	# Skeleton space +X is the mech's left; the weapon side is mech space +X (right).
	_shift_x = clampf(-side / _hands.size() * hip_shift_part, -max_hip_shift, max_hip_shift)
	phase = Phase.REACH
	_time = 0.0


## The player takes a weapon from the ground (Tab plus a mouse button; WeaponHandControl checks the range and
## the rules). is_right: the hand slot that gets the weapon; two_hand: a two-hand weapon (both hands). The
## mech turns toward the weapon, crouches, grabs and lifts it, and cannot move or fire meanwhile. Returns
## false when it cannot start (a pick-up runs, the hands are not free, the weapon is gone or taken).
func begin_manual(drop: WeaponDrop, is_right: bool, two_hand: bool) -> bool:
	if phase != Phase.IDLE or mech.is_wrecked or drop == null or not drop.is_pickable_by(weapons):
		return false
	var weapon := drop.weapon
	if two_hand:
		if not (weapons.is_hand_free(true) and weapons.is_hand_free(false)):
			return false
	elif not weapons.is_hand_free(is_right):
		return false
	if not is_right and not WeaponController.can_hold_left(weapon.data, weapons.right_data):
		return false
	_drops.clear()
	_hands.clear()
	drop.reserved_by = self
	_manual = true
	_speed = manual_speed
	weapons.begin_hand_pickup(is_right)
	if two_hand:
		weapons.begin_hand_pickup(false)
	if not is_right:
		weapons.ensure_left_grip(weapon)
	_drops.append({"drop": drop, "weapon": weapon, "right": is_right, "both": two_hand, "grabbed": false,
			"grab_local": Transform3D.IDENTITY})
	# The mech stands still and cannot act (the same lock as a knock-down).
	mech.start_fall()
	mech.velocity.x = 0.0
	mech.velocity.z = 0.0
	var plan := _plan_manual(drop, two_hand)
	_add_hand(is_right, &"GripRight" if is_right else &"GripLeft", drop)
	if two_hand:
		_add_hand(false, &"GripLeft", drop)
	var final := Transform3D(Basis(Vector3.UP, _heading_to), mech.global_position).affine_inverse()
	var side := 0.0
	for hand in _hands:
		var grip := drop.get_grip_position(hand.grip)
		var after: Vector3 = plan.pivot + Basis(Vector3.UP, plan.turn) * (grip - plan.pivot) + plan.offset
		side += (final * after).x
	_shift_x = clampf(-side / _hands.size() * hip_shift_part, -max_hip_shift, max_hip_shift)
	phase = Phase.REACH
	_time = 0.0
	return true


## Works out where the mech faces and how the weapon has to move for the pick-up, and starts the weapon's
## move. Faces the weapon (the middle between the grips of a two-hand weapon). A weapon under the feet slides
## out in front; a two-hand weapon turns so that its right grip is on the right of the mech and its left
## grip on the left (across in front). Returns {pivot, turn, offset}.
func _plan_manual(drop: WeaponDrop, two_hand: bool) -> Dictionary:
	var grip_right := drop.get_grip_position(&"GripRight")
	var center := grip_right
	var line := Vector3.ZERO
	if two_hand:
		var grip_left := drop.get_grip_position(&"GripLeft")
		center = (grip_right + grip_left) * 0.5
		line = grip_left - grip_right
		line.y = 0.0
	var to := center - mech.global_position
	to.y = 0.0
	var distance := to.length()
	if distance < 0.05:
		to = -mech.global_basis.z
		distance = 0.0
	_heading_from = mech.rotation.y
	_heading_to = _heading_from + wrapf(atan2(-to.x, -to.z) - _heading_from, -PI, PI)
	var forward := Vector3(-sin(_heading_to), 0.0, -cos(_heading_to))
	var wanted := clampf(distance, min_reach_distance, max_reach_distance * 0.8)
	var offset := mech.global_position + forward * wanted - center
	offset.y = 0.0
	var turn := 0.0
	if two_hand and line.length_squared() > 0.0001:
		# Across in front: the line from the right grip to the left grip points to the mech's left.
		var left := Vector3.UP.cross(forward)
		turn = line.signed_angle_to(left, Vector3.UP)
	if offset.length() > 0.05 or absf(turn) > 0.02:
		drop.move_by(offset, turn, reach_time * 0.6 / _speed, center)
	else:
		offset = Vector3.ZERO
		turn = 0.0
	return {"pivot": center, "turn": turn, "offset": offset}


## The reach ended before the weapon was in the hand (a broken arm, the weapon gone): the hands get their
## fists back (a hand with a broken arm gets none) and the mech is free again. The weapon stays on the ground.
## (A pick-up after a knock-down ends the fall itself, like a finished one.)
func abort() -> void:
	if not is_picking():
		return
	_release_reach()
	_free_markers()
	_drops.clear()
	_fade_from = get_crouch()
	phase = Phase.FADE
	_time = 0.0
	if _manual:
		mech.set_heading(mech.input.aim_yaw)
	mech.end_fall()
	_manual = false


## A reach stops: the hands go back to the relaxed hang and the weapons on the ground can be taken again.
func _release_reach() -> void:
	for entry in _drops:
		if is_instance_valid(entry.drop):
			(entry.drop as WeaponDrop).reserved_by = null
	for hand in _hands:
		weapons.cancel_hand_pickup(hand.right)


## A new knock-down or stun: a weapon in the hand goes to its place, one on the ground stays, the crouch lets go.
func interrupt() -> void:
	if not is_picking():
		return
	if phase == Phase.REACH:
		_release_reach()
		_drops.clear()
	else:
		_equip_all()
	_free_markers()
	_fade_from = get_crouch()
	phase = Phase.FADE
	_time = 0.0
	_manual = false


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
		if phase == Phase.REACH:
			_release_reach()
			_drops.clear()
		elif phase != Phase.FADE:
			_equip_all()
		_free_markers()
		phase = Phase.IDLE
		_manual = false
		return
	if phase == Phase.REACH and _reach_broken():
		abort()
		return
	_time += delta * _speed
	match phase:
		Phase.REACH:
			_move_markers()
			if _manual:
				_turn_body()
			if _time >= reach_time:
				_grab()
		Phase.GRAB:
			if _time >= grab_time:
				phase = Phase.LIFT
				_time = 0.0
		Phase.LIFT:
			_move_weapons()
			if _manual:
				_turn_back()
			if _time >= lift_time:
				_finish()
		Phase.FADE:
			if _time >= fade_time:
				phase = Phase.IDLE


## The weapon is gone or taken, or the arm that is to hold it is destroyed. The left arm that only helps a
## two-hand weapon may die: the right hand then takes the weapon alone (it is held in one hand then).
func _reach_broken() -> bool:
	for entry in _drops:
		var drop := entry.drop as WeaponDrop
		if not is_instance_valid(drop) or not is_instance_valid(entry.weapon) or (entry.weapon as Node).get_parent() != drop:
			return true
		if not weapons.is_arm_alive(entry.right):
			return true
		if entry.both and not weapons.is_arm_alive(false):
			for hand in _hands.duplicate():
				if not hand.right:
					if is_instance_valid(hand.marker):
						(hand.marker as Marker3D).queue_free()
					_hands.erase(hand)
					# The left hand leaves the pick-up for good (review 2026-10-18: its flag stayed set).
					weapons.clear_hand_pickup(false)
	return false


## REACH of a pick-up by the player: the whole mech turns toward the weapon (no turn animation).
func _turn_body() -> void:
	var k := smoothstep(0.0, 1.0, clampf(_time / maxf(reach_time * turn_share, 0.01), 0.0, 1.0))
	mech.set_heading(lerp_angle(_heading_from, _heading_to, k))


## LIFT of a pick-up by the player: the mech turns back to face where the camera aims, so the camera is where
## the player left it when the pick-up ends (the torso would pull the camera to it otherwise:
## MechCameraRig.max_torso_lead_deg).
func _turn_back() -> void:
	var k := smoothstep(0.0, 1.0, clampf(_time / maxf(lift_time, 0.01), 0.0, 1.0))
	mech.set_heading(lerp_angle(_heading_to, mech.input.aim_yaw, k))


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
		weapons.take_from_ground(drop, entry.right)
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
		if not entry.grabbed or not is_instance_valid(entry.weapon) or not weapons.holds(entry.weapon):
			continue
		(entry.weapon as MechWeapon).transform = (entry.grab_local as Transform3D).interpolate_with(_rest_of(entry.right), t)


func _rest_of(right: bool) -> Transform3D:
	return weapons.weapon_pose.rest_transform if right else weapons.left_pose.rest_transform


## The weapons are in the hands and work again: the mech is free.
func _finish() -> void:
	_equip_all()
	phase = Phase.IDLE
	_time = 0.0
	_manual = false
	mech.end_fall()
	finished.emit()


## The weapons that are in the hands start to work. A weapon that is not in a hand any more (the arm broke, the
## mech died) is left alone; its hand only forgets the reach.
func _equip_all() -> void:
	for entry in _drops:
		if not entry.grabbed:
			continue
		if is_instance_valid(entry.weapon) and weapons.holds(entry.weapon):
			entry.weapon.transform = _rest_of(entry.right)
			weapons.equip_dropped(entry.weapon, entry.right)
		else:
			weapons.clear_hand_pickup(entry.right)
			if entry.both:
				weapons.clear_hand_pickup(false)
		entry.grabbed = false
	_drops.clear()


func _free_markers() -> void:
	for hand in _hands:
		if is_instance_valid(hand.marker):
			(hand.marker as Marker3D).queue_free()
	_hands.clear()
