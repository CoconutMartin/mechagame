class_name PileBunkerWeapon
extends MechWeapon
## A pile bunker on the right forearm (like the shield on the left). Hold RMB to power up the stake
## (energy drains into it); release RMB, or run out of energy, to attack: a shield charge, then a
## punch. More power = more damage and force.
## The weapon root is only the fist target for the arm IK; the model ("Mount") moves onto the forearm.
## The mech charges toward the target (or along the aim) with the shield up and the torso turned
## so the left shoulder (shield) leads. At the end of the charge the torso twists back and the right
## arm pulls back, then the arm punches forward. When the front of the pile bunker touches something,
## the stake (the "needle") fires out with a strong force. No contact = no shot (no ammo used).
## Uses ammo (one stake cartridge per shot) and the lunge uses energy.
## Left hand (user rule 2026-10-15): the same weapon mirrored. Its controller is the left view
## (WeaponController.left_arm_view): the model sits on the left forearm, the poses and the torso turns
## mirror (the right shoulder leads the charge), and the punch goes along the left shoulder's line.

const IMPACT := preload("res://scenes/effects/impact_spark.tscn")

## Weapon poses in torso space: position of the grip, then the direction the stake points (Sanggigilid,
## from the user's arm drawing 2026-10-12: the elbow-90 place, the arm straight forward; no part
## enters the body in the whole punch cycle).
## Guard: fist ahead of the elbow, forearm level, during the charge.
@export var guard_position: Vector3 = Vector3(2.18, 1.16, -2.76)
@export var guard_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
## Wind-up: fist pulled back a little, beside the body.
@export var windup_position: Vector3 = Vector3(2.4, 1.0, -1.8)
@export var windup_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
## Punch: arm reaching forward.
@export var punch_position: Vector3 = Vector3(2.1, 1.4, -4.0)
@export var punch_direction: Vector3 = Vector3(-0.05, 0.0, -1.0)
## Charge pose (user request 2026-11-02: "arms and shoulders keep changing positions, keep them stable; forearm flat"):
## the fist pulled back beside the chest, the forearm level and the stake forward. Held still while the stake powers up
## and the mech walks.
@export var charge_position: Vector3 = Vector3(2.4, 1.4, -2.3)
@export var charge_direction: Vector3 = Vector3(0.0, 0.0, -1.0)

## Model place on the right forearm (elbow space: -Y runs down the forearm to the fist, -X is the
## outer side, +Z is the top of the forearm). Far enough down the forearm and out that the clamps
## clear the shoulder armor and the thigh.
@export var mount_position: Vector3 = Vector3(-1.15, -2.4, 0.0)
@export var mount_rotation_deg: Vector3 = Vector3(-90.0, 0.0, 180.0)
## Rigged mech (user report 2026-10-26: the model clipped the forearm armor): the model follows the
## skeleton's forearm bone itself, like its armor (the arm IK elbow node turns differently from the bone).
## Place in that bone's frame for each hand (from tools/godot/compute_pile_bunker_mount.gd). Off: the
## elbow place above.
@export var on_forearm_bone: bool = false
@export var forearm_bone_right: StringName = &"forearm_R"
@export var forearm_bone_left: StringName = &"forearm_L"
@export var bone_mount_right: Transform3D = Transform3D.IDENTITY
@export var bone_mount_left: Transform3D = Transform3D.IDENTITY
## On the forearm bone: mirror the model (X, the mirror_path node) in that hand, so its detailed side
## (drum, plates, lug) faces out. Both places are proper turns, so one hand needs the mirror.
@export var bone_mirror_right: bool = false
@export var bone_mirror_left: bool = true

@export_group("Torso")
## Torso turn during the shield charge, in degrees. Negative = turn right (left shoulder leads).
@export var charge_twist_deg: float = -30.0
## Torso turn at the end of the wind-up (the right shoulder pulls back further).
@export var windup_twist_deg: float = -50.0
## Torso turn at the end of the punch (the right shoulder comes forward).
@export var punch_twist_deg: float = 30.0

@export_group("Timing")
## How fast the guard pose comes in at the start of the charge (1 / seconds).
@export var guard_speed: float = 6.0
@export var windup_time: float = 0.18
@export var punch_time: float = 0.12
## The punch pose stays this long after the punch while the stake is out, in seconds.
@export var hold_time: float = 0.3
## Time the attack stays busy after the hold (the next attack can start after it), in seconds.
@export var recover_time: float = 0.45
## The arm lowers to the rest pose over recover_time x this value (user request 2026-10-24: the bare hand fix,
## "hands lower 50% slower" = half the speed, for the fist weapons too). It goes on lowering after the busy time.
@export var lower_time_scale: float = 2.0

@export_group("Stake")
## How far the stake shoots out, in meters.
@export var stake_travel: float = 3.5
## Time for the stake to shoot out, in seconds.
@export var stake_out_time: float = 0.05
## Time for the stake to slide back in, in seconds.
@export var stake_back_time: float = 0.6
## Contact check length in front of the pile bunker nose, in meters.
@export var contact_reach: float = 1.5
## The contact check starts this far behind the grip, in meters.
@export var contact_back: float = 3.0
## The mech is pushed back this fast when the stake fires (m/s).
@export var push_back_speed: float = 7.0
## Layers the contact check hits: 1 world, 3 props, 4 hitboxes.
@export_flags_3d_physics var collision_mask: int = 29

@export_group("Punch clip")
## Punch clips (user uploads 2026-10-29, "... - for pile bunker"): after the charge the whole body plays the clip of
## clip_number (SkeletalMeleeAnimation.play_external) instead of the coded wind-up and punch. The stakes fire when the
## nose touches something during the clip's strike window. No clip for the number = the coded punch.
@export var clips: PileBunkerClips = null
## Which clip of clips this Pile Bunker plays (1 to 5). The player switches it in play with Shift + 1 to 5 (tests).
## 3 since 2026-11-04 (user: "remove shift+1 animation", the leap punch; slots 1 and 2 are deleted).
@export_range(1, 5) var clip_number: int = 3
## The clip's contact ray starts this far behind the nose, along the stakes (m).
@export var clip_contact_back: float = 2.0
## Aim at the crosshair during the clip (user request 2026-11-04: "animate the mech so that the pilebunker edge moves
## towards the crosshair, all model collision considered"): the arm turns so the nose moves toward the crosshair, by
## clip_aim_strength, at most clip_aim_max_deg; it comes in over clip_aim_lead seconds before the strike window, holds
## through it and goes over clip_aim_release seconds after the window or the hit.
@export var clip_aim_strength: float = 1.0
@export var clip_aim_max_deg: float = 40.0
@export var clip_aim_lead: float = 0.25
@export var clip_aim_release: float = 0.25
## A clip cut with the lowest sole higher than this (m) above the ground ends in the soft landing (MeleeAttack.cut_landing_height).
@export var clip_landing_air_m: float = 0.5
@export_subgroup("Body turn")
## Turn the mech toward the crosshair during the clip (user request 2026-11-04: "turn the mech towards the target"), so
## the stake reaches the target when the clip's travel or the mech's heading at the release carries the nose off the
## line. The punching shoulder turns to face the aim line (SkeletalMeleeAnimation moves the clip's travel along with the
## heading). The body takes the heading error beyond clip_turn_arm_deg, the arm aim above takes the rest. 0 = no body
## turn. Fastest turn (deg/s):
@export var clip_turn_speed_deg: float = 180.0
## How fast the turn speed changes (deg/s per s).
@export var clip_turn_accel_deg: float = 900.0
## Turn speed per degree of error (deg/s per deg), up to clip_turn_speed_deg.
@export var clip_turn_gain: float = 8.0
## The error (deg) left to the arm aim.
@export var clip_turn_arm_deg: float = 5.0
## The body turns at most this far (deg) from its heading at the start of the clip.
@export var clip_turn_max_deg: float = 80.0
## The body turn comes in over this many seconds before the strike window, holds through it and ends at the hit (or
## clip_aim_release seconds after the window).
@export var clip_turn_lead: float = 0.4
## The mech turns toward the aim line (from the mech at the clip start to the crosshair point) at this distance (m)
## from the mech at most, or toward the crosshair point when that is nearer. A crosshair point far away would otherwise
## leave a mech that slid sideways with the clip's travel facing parallel to the line and not onto it.
@export var clip_turn_range: float = 14.0

@export_group("Model")
## The parts in the model (paths from the weapon root): the stake that slides out, the nose (front of
## the pile bunker), the drum meshes and the nose ring that glow with the stored power.
@export var stake_path: NodePath = ^"Mount/Stake"
@export var nose_path: NodePath = ^"Mount/Nose"
@export var drum_paths: Array[NodePath] = [^"Mount/Drum"]
@export var nose_ring_path: NodePath = ^"Mount/NoseRing"
## The model node under Mount that is mirrored (X) in the left hand, so its forearm bracket is on the arm
## side there too. Empty = no mirror (a model that looks the same from both sides).
@export var mirror_path: NodePath = ^""

@export_group("Drill spin")
## Spin of the stake about its own axis (a drill stake, Pile Bunker 2, user request 2026-10-31): it spins from
## the start of the charge until the stake hits or the punch misses. Degrees per second; 0 = no spin.
@export var spin_speed_deg: float = 0.0
## Seconds to reach the full spin.
@export var spin_up_time: float = 0.4
## Seconds to stop after a hit or a miss.
@export var spin_down_time: float = 0.25

@export_group("Claws")
## Claw hinge nodes in the model (Pile Bunker 4, user request 2026-10-31): closed round the stake at rest, they
## open when the stake hits or the punch misses, and close again when the arm is back at rest. Each one turns
## out from the stake axis (the model's -Z) about its own hinge. Empty = no claws.
@export var claw_paths: Array[NodePath] = []
## How far a claw opens (degrees).
@export var claw_open_deg: float = 35.0
## Seconds to open and to close.
@export var claw_open_time: float = 0.12
@export var claw_close_time: float = 0.5

@export_group("Power")
## Hold RMB to power up the stake: seconds to full power, and energy use per second while holding.
## Release RMB (or run out of energy) to attack. More power = more damage, push and shake.
@export var power_time: float = 1.5
@export var power_energy_per_second: float = 30.0
## Damage and force of an attack with no power, as a part of a full one.
@export_range(0.0, 1.0) var min_power: float = 0.5
## The stake pulls back into the housing while powering up (cocking), in meters at full power.
@export var cock_distance: float = 0.8
## Camera shake while powering up: trauma at no power and at full power.
@export var power_shake_min: float = 0.03
@export var power_shake_max: float = 0.12

@export_group("Walk while charging")
## While the stake powers up the mech can walk (user request 2026-11-02), at this part of its walk speed; no run or boost.
@export var charge_walk_speed_scale: float = 0.6
## Old behavior: the "Idle - pilebunker charging" clip loops on the whole body during the power-up (the arms move with
## it, and the mech stands still). Off since 2026-11-02 (the fixed charge pose).
@export var charge_clip_loop: bool = false

@export_group("Leap")
## Release with punch clip 1 (or no clip): the mech leaps at the target while the arm swings, and the stakes hit at the
## end of the leap (user request 2026-11-02: replaces the slide). Peak height of the leap (m).
@export var leap_height: float = 2.2
## Longest leap (m). Below 0: the forward dodge length (Space twice + W, the dodge clip step_forward), as asked.
@export var leap_max_distance: float = -1.0
## Parts of the flight time: the arm holds the wind-up until swing_start, then swings to the punch by swing_end
## (speeding up); the contact check starts at contact_start.
@export_range(0.0, 1.0) var leap_swing_start: float = 0.35
@export_range(0.0, 1.0) var leap_swing_end: float = 0.95
@export_range(0.0, 1.0) var leap_contact_start: float = 0.6
## The clips that leap (PileBunkerClips numbers). Other clips keep the charge glide and their own clip.
## Empty since 2026-11-04 (the leap punch was removed with slot 1); the leap code stays for a later clip.
@export var leap_clip_numbers: PackedInt32Array = PackedInt32Array()

@export_group("Charge")
## The charge goes toward the mech aim point (the blue ring) and stops this far from it (flat
## distance from the mech center), so the punch reaches it. In meters.
@export var stop_distance: float = 7.0
## The punch goes at the aim point: hand distance from the shoulder (the arm is 5.7 m long), and
## the widest angle from straight ahead, in degrees.
@export var punch_reach: float = 4.9
@export var punch_cone_deg: float = 60.0

enum State { IDLE, POWER, CHARGE, WINDUP, PUNCH, HOLD, RECOVER, CLIP, LEAP }

var state: State = State.IDLE
## 0 = stake in, 1 = stake fully out.
var stake_out: float = 0.0
## True from the stake shot until the next charge.
var has_fired: bool = false
## 0 to 1: power stored while RMB is held.
var power: float = 0.0

var _time: float = 0.0
var _guard := Transform3D.IDENTITY
var _windup := Transform3D.IDENTITY
var _punch := Transform3D.IDENTITY
var _charge := Transform3D.IDENTITY
## Flight time of the current leap (s).
var _leap_time: float = 1.0
## 0 = normal pose, 1 = action pose.
var _pose_weight: float = 0.0
## Action pose now (between guard, wind-up and punch).
var _action := Transform3D.IDENTITY
var _twist: float = 0.0
var _stake_rest := Vector3.ZERO
## The point the charge and the punch go for (world): the blue ring when the attack starts.
var _aim_point := Vector3.ZERO
## True for a pile bunker in the left hand (set in setup()).
var is_left: bool = false
## The forearm bone attachment that carries the model (on_forearm_bone).
var _bone_attach: BoneAttachment3D
## The model's box corners in the forearm bone's frame (on_forearm_bone), for the arm rig's keep-off.
var _bone_corners: Array[Vector3] = []
## The melee clip player (found on the first clip) and the arm IK target the clip took away.
var _melee: SkeletalMeleeAnimation
var _saved_target: Node3D
## Seconds since the stakes fired during the clip.
var _since_fire: float = 0.0
## True when the clip's strike window ended with no hit.
var _clip_missed: bool = false
## The body turn of the clip: speed now (rad/s) and the sum so far (rad).
var _turn_velocity: float = 0.0
var _turn_total: float = 0.0
## The punching shoulder's side offset from the mech center at the clip start (m, right positive).
var _shoulder_side: float = 0.0
## The aim line noted at the clip start (flat): origin, unit direction and length to the crosshair point.
var _aim_line_origin := Vector3.ZERO
var _aim_line_dir := Vector3.FORWARD
var _aim_line_length: float = 0.0
## Fall height (m) of the soft landing due when the cut clip has faded (0 = none).
var _landing_due: float = 0.0
## Drill spin now (0 to 1 of spin_speed_deg) and its angle (radians).
var _spin: float = 0.0
var _spin_angle: float = 0.0
var _stake_basis := Basis.IDENTITY
## Claw nodes, their rest turn and their open axis (in the model's space); 0 = closed, 1 = open.
var _claws: Array[Node3D] = []
var _claw_rest: Array[Basis] = []
var _claw_axes: Array[Vector3] = []
var _claw_open: float = 0.0

@onready var _mount: Node3D = $Mount
@onready var _stake: Node3D = get_node(stake_path)
@onready var _nose: Node3D = get_node(nose_path)
@onready var _glow := ChargeGlow.new()


func _ready() -> void:
	_make_poses()
	_stake_rest = _stake.position
	_stake_basis = _stake.basis
	for path in claw_paths:
		var claw := get_node(path) as Node3D
		var radial := Vector3(claw.position.x, claw.position.y, 0.0).normalized()
		_claws.append(claw)
		_claw_rest.append(claw.basis)
		# Turning the stake direction (-Z) toward the radial: the claw tip moves out.
		_claw_axes.append(Vector3.FORWARD.cross(radial).normalized())
	# The drum and the nose ring glow with the stored power.
	_glow.color = Color(1.0, 0.55, 0.2)
	add_child(_glow)
	var drum: Array[MeshInstance3D] = []
	for path in drum_paths:
		drum.append(get_node(path) as MeshInstance3D)
	_glow.setup(drum, get_node(nose_ring_path) as MeshInstance3D, _nose)


## The model on the forearm bone goes with the weapon (a garage swap frees the weapon, not the mech).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_bone_attach):
		_bone_attach.queue_free()


## Called by WeaponController after the node is added: a left view means the left hand.
func setup(weapon_data: WeaponData, weapon_controller: WeaponController) -> void:
	super(weapon_data, weapon_controller)
	if weapon_controller.left_arm_view != is_left:
		is_left = weapon_controller.left_arm_view
		_make_poses()


func _make_poses() -> void:
	_guard = _pose_from(guard_position, guard_direction)
	_windup = _pose_from(windup_position, windup_direction)
	_punch = _pose_from(punch_position, punch_direction)
	_charge = _pose_from(charge_position, charge_direction)
	_action = _guard


func is_melee() -> bool:
	return true


func is_busy() -> bool:
	return state != State.IDLE


## Stops the attack (the mech falls over): no more charge or punch, the arm goes back to rest.
func cancel() -> void:
	if state == State.IDLE:
		return
	controller.mech.is_lunging = false
	controller.mech.melee_charge_speed_scale = 1.0
	if not is_left:
		controller.mech_shield.force_up = false
	if state == State.CLIP or (is_instance_valid(_melee) and _melee.is_external_busy(self)):
		if is_instance_valid(_melee):
			_melee.stop_external(self)
		_end_clip()
		return
	_next(State.RECOVER)


## The model ("Mount"; it moves onto the forearm).
func get_model() -> Node3D:
	return _mount


## Moves the model onto the right forearm (once, after WeaponController has wired the arm IK).
func _attach_to_forearm() -> void:
	if _bone_attach != null:
		return
	var model := get_node_or_null(mirror_path) as Node3D
	var skeleton := controller.mech.find_child("Skeleton3D", true, false) as Skeleton3D if on_forearm_bone else null
	if skeleton != null:
		_bone_attach = BoneAttachment3D.new()
		_bone_attach.name = "PileBunkerMount" + ("L" if is_left else "R")
		_bone_attach.bone_name = forearm_bone_left if is_left else forearm_bone_right
		skeleton.add_child(_bone_attach)
		_mount.reparent(_bone_attach, false)
		_mount.transform = bone_mount_left if is_left else bone_mount_right
		_bone_corners = _model_corners()
		if model != null and (bone_mirror_left if is_left else bone_mirror_right):
			model.transform = Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3.ZERO) * model.transform
		return
	var forearm := controller.holding_arm_ik().mid_joint
	if forearm == null or _mount.get_parent() == forearm:
		return
	_mount.reparent(forearm, false)
	var basis := Basis.from_euler(mount_rotation_deg * PI / 180.0)
	var place := mount_position
	if is_left:
		# The left elbow node is the right one mirrored with its Z axis turned round (the arm rig's joint
		# frames are proper rotations on both sides), so the same model place is flip * place * mirror.
		basis = Basis.from_scale(Vector3(1.0, 1.0, -1.0)) * basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
		place.z = -place.z
		# That place turns the model round (the forearm is on its +X side): mirror the model to put it back.
		if model != null and is_left:
			model.transform = Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3.ZERO) * model.transform
	_mount.transform = Transform3D(basis, place)

func _update(delta: float) -> void:
	_attach_to_forearm()
	_time += delta
	match state:
		State.IDLE:
			_pose_weight = move_toward(_pose_weight, 0.0, delta / _lower_time())
			_twist = move_toward(_twist, 0.0, absf(punch_twist_deg) * delta / _lower_time())
			if trigger_pressed() and can_use() and controller.mech.energy.current >= data.lunge_energy \
					and not _other_bunker_busy():
				power = 0.0
				_next(State.POWER)
				_start_charge_loop()
		State.POWER:
			_update_power(delta)
		State.CHARGE:
			_pose_weight = move_toward(_pose_weight, 1.0, delta * guard_speed)
			_action = _guard
			_twist = charge_twist_deg * smoothstep(0.0, 1.0, _pose_weight)
			if not controller.mech.is_lunging:
				if not _start_clip():
					# No clip: the coded punch, with the arm back on the weapon.
					if is_instance_valid(_melee):
						_melee.stop_external(self)
					var ik := controller.holding_arm_ik()
					if ik.target == null and _saved_target != null:
						ik.target = _saved_target
					_next(State.WINDUP)
		State.WINDUP:
			var t := smoothstep(0.0, 1.0, clampf(_time / windup_time, 0.0, 1.0))
			_pose_weight = 1.0
			_action = _guard.interpolate_with(_windup, t)
			_twist = lerpf(charge_twist_deg, windup_twist_deg, t)
			if _time >= windup_time:
				_next(State.PUNCH)
		State.PUNCH:
			# Fast punch: speeds up to the end.
			var t := pow(clampf(_time / punch_time, 0.0, 1.0), 1.5)
			_punch = _aimed_punch()
			_action = _windup.interpolate_with(_punch, t)
			_twist = lerpf(windup_twist_deg, punch_twist_deg, t)
			if not has_fired:
				_check_contact()
			if _time >= punch_time:
				_next(State.HOLD)
				# One leg left: a punch into nothing throws the mech off balance, the moment the arm
				# is fully out.
				if not has_fired and controller.mech.one_leg and controller.mech.fall_control != null:
					cancel()
					controller.mech.fall_control.fall()
		State.HOLD:
			_punch = _aimed_punch()
			_action = _punch
			_twist = punch_twist_deg
			if not has_fired:
				_check_contact()
			if _time >= hold_time:
				_next(State.RECOVER)
		State.CLIP:
			_update_clip(delta)
		State.LEAP:
			_update_leap()
		State.RECOVER:
			_pose_weight = move_toward(_pose_weight, 0.0, delta / _lower_time())
			_twist = punch_twist_deg * smoothstep(0.0, 1.0, _pose_weight)
			# Not busy after recover_time; IDLE lowers the rest of the way at the same speed.
			if _time >= recover_time or _pose_weight <= 0.0:
				state = State.IDLE
	_update_stake(delta)
	controller.mech.melee_charge_speed_scale = charge_walk_speed_scale if state == State.POWER else 1.0
	# Charge with the shield up. The lunge moves the mech, so the shield does not slow it down.
	if not is_left:
		controller.mech_shield.force_up = state == State.CHARGE
	controller.torso_pose.action_twist_deg = _twist * (-1.0 if is_left else 1.0)


## The model's box corners in the forearm bone's frame (empty when the model is not on the forearm bone). The arm
## rig keeps them off the legs and the body like the hand (an idle Pile Bunker arm swings with the stride).
func forearm_bone_corners() -> Array[Vector3]:
	return _bone_corners


## The box of the model's meshes (stakes in), as 8 corners in the bone attachment's frame.
func _model_corners() -> Array[Vector3]:
	var box := AABB()
	var first := true
	var to_attach := _bone_attach.global_transform.affine_inverse()
	for mesh: MeshInstance3D in _mount.find_children("*", "MeshInstance3D", true, false):
		var place := to_attach * mesh.global_transform
		var aabb := mesh.get_aabb()
		for i in 8:
			var point := place * aabb.get_endpoint(i)
			box = AABB(point, Vector3.ZERO) if first else box.expand(point)
			first = false
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(box.get_endpoint(i))
	return corners


## True while a Pile Bunker in the other hand attacks (two Pile Bunkers, user request 2026-10-30): one attack at a
## time, they share the charge and the body clip.
func _other_bunker_busy() -> bool:
	var weapons := controller.mech.get_node_or_null("WeaponController") as WeaponController
	if weapons == null:
		return false
	var other := weapons.right_weapon if is_left else weapons.left_weapon
	return other is PileBunkerWeapon and other != self and is_instance_valid(other) and (other as PileBunkerWeapon).is_busy()


## The punch clip of clip_number for this hand, or null.
func punch_clip() -> MeleeAttack:
	return clips.get_clip(clip_number, is_left) if clips != null else null


## Shift + 1 to 5: the player's Pile Bunker plays that clip from the next attack (user request 2026-10-29).
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not key.shift_pressed or clips == null:
		return
	if controller == null or not controller.mech.is_in_group(&"player"):
		return
	var number := key.keycode - KEY_0
	if number < 1 or number > 5:
		return
	# A slot with no name is deleted (user request 2026-11-02: delete Shift+2, the coded punch).
	if clips.get_clip_name(number) == "":
		return
	# Not marked as handled: with two Pile Bunkers both switch (user report 2026-11-02: the right one kept clip 1).
	# LoadoutSwitcher ignores number keys with Shift.
	clip_number = number


## Starts the punch clip on the whole body (false: no clip, or the mech cannot play it now).
func _start_clip() -> bool:
	var clip := punch_clip()
	if clip == null:
		return false
	if not is_instance_valid(_melee):
		_melee = controller.mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	if _melee == null:
		return false
	# From the charging loop the punch blends in from its pose; else it starts on its own.
	if not _melee.chain_external(clip, self) and not _melee.play_external(clip, self):
		return false
	# The clip moves the arm: the arm IK lets go of the weapon's grip until the clip has faded out.
	_release_arm()
	_since_fire = 0.0
	_clip_missed = false
	_turn_velocity = 0.0
	_turn_total = 0.0
	_note_aim_line()
	_shoulder_side = _shoulder_offset()
	_next(State.CLIP)
	return true


## The charging clip (user upload 2026-10-30) loops on the whole body while the stake powers up and the mech
## charges; the punch clip then blends in from it.
func _start_charge_loop() -> void:
	if not charge_clip_loop:
		return
	if not is_instance_valid(_melee):
		_melee = controller.mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	if _melee == null or punch_clip() == null:
		return
	var loop := _melee.charge_clip(is_left)
	if loop != null and _melee.play_external(loop, self, true):
		_release_arm()


## The arm IK lets go of the weapon's grip (the clip moves the arm); _end_clip gives it back.
func _release_arm() -> void:
	var ik := controller.holding_arm_ik()
	if ik.target != null:
		_saved_target = ik.target
	ik.target = null


## The punch clip plays: the guard pose and the torso turn fade (the clip moves the body), the stakes fire on
## contact during the strike window, and the arm goes back to the weapon when the clip has faded out.
func _update_clip(delta: float) -> void:
	_pose_weight = move_toward(_pose_weight, 0.0, delta * guard_speed)
	_twist = move_toward(_twist, 0.0, absf(punch_twist_deg) * delta * guard_speed)
	var clip := punch_clip()
	var time := _melee.external_time(self) if is_instance_valid(_melee) else -1.0
	_turn_body(delta, clip, time)
	if has_fired:
		_since_fire += delta
		if clip.cut_after_hit >= 0.0 and _since_fire >= clip.cut_after_hit and time >= 0.0:
			_cut_clip(clip)
	elif _clip_missed and clip.cut_after_hit >= 0.0 and time >= 0.0 and clip.strikes.size() > 0 \
			and time >= clip.strikes[0].y + clip.cut_after_hit:
		_cut_clip(clip)
	elif time >= 0.0 and clip.strikes.size() > 0:
		var window := clip.strikes[0]
		if time >= window.x and time <= window.y:
			_check_clip_contact()
		elif time > window.y:
			_clip_missed = true
		if time > window.y and controller.mech.one_leg and controller.mech.fall_control != null:
			# One leg left: a punch into nothing throws the mech off balance.
			cancel()
			controller.mech.fall_control.fall()
			return
	if not is_instance_valid(_melee) or not _melee.is_external_busy(self):
		_end_clip()


## Turns the whole mech (Mech.set_heading, the way SkeletalMeleeAnimation turns toward its target) so the punching
## shoulder faces the aim line. The clip's travel direction stays as it was (the clip's own root motion). The nose line
## is not chased: it swings with the arm, and the arm aim (clip_aim) takes what the body leaves.
func _turn_body(delta: float, clip: MeleeAttack, time: float) -> void:
	if clip_turn_speed_deg <= 0.0:
		return
	var speed := deg_to_rad(clip_turn_speed_deg)
	var desired := 0.0
	if not has_fired and time >= 0.0 and clip.strikes.size() > 0:
		var window := clip.strikes[0]
		var weight := smoothstep(window.x - clip_turn_lead, window.x, time) \
				* (1.0 - smoothstep(window.y, window.y + clip_aim_release, time))
		var error := _heading_error()
		var body := signf(error) * maxf(absf(error) - deg_to_rad(clip_turn_arm_deg), 0.0)
		desired = clampf(body * clip_turn_gain, -speed, speed) * weight
	_turn_velocity = move_toward(_turn_velocity, desired, deg_to_rad(clip_turn_accel_deg) * delta)
	var limit := deg_to_rad(clip_turn_max_deg)
	var step := clampf(_turn_total + _turn_velocity * delta, -limit, limit) - _turn_total
	if is_zero_approx(step):
		return
	_turn_total += step
	var mech := controller.mech
	mech.set_heading(wrapf(mech.rotation.y + step, -PI, PI))


## Yaw (rad, left positive) the mech must turn for the punching shoulder to face the turn point: the heading toward
## the point, plus the angle the shoulder's side offset makes at that distance.
func _heading_error() -> float:
	var mech := controller.mech
	var to_point := _flat(_turn_point() - mech.global_position)
	var distance := to_point.length()
	if distance < 1.0:
		return 0.0
	var desired := _yaw_of(to_point) + asin(clampf(_shoulder_side / distance, -0.5, 0.5))
	return wrapf(desired - mech.rotation.y, -PI, PI)


## How far the upper arm bone of this hand is to the mech's right of its center (m, negative = left).
func _shoulder_offset() -> float:
	var skeleton := _bone_attach.get_parent() as Skeleton3D if is_instance_valid(_bone_attach) else null
	if skeleton == null:
		return -2.1 if is_left else 2.1
	var bone := skeleton.find_bone("upper_arm_L" if is_left else "upper_arm_R")
	if bone < 0:
		return -2.1 if is_left else 2.1
	var local := controller.mech.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
	return local.x


## Notes the aim line when the clip starts, flat: from the mech to the crosshair point (where the lunge ran to). The body
## turn keeps to this line while the clip plays, so a mech that slides sideways with the clip's travel turns back onto
## it. (The live crosshair point jumps with the camera and the aim shake, and a line through the live mech center
## would slide along with it.)
func _note_aim_line() -> void:
	_aim_line_origin = _flat(controller.mech.global_position)
	var along := _flat(controller.mech_aim.aim_point) - _aim_line_origin
	_aim_line_length = along.length()
	_aim_line_dir = along / _aim_line_length if _aim_line_length > 0.5 else _flat(-controller.mech.global_basis.z).normalized()
	if _aim_line_length <= 0.5:
		_aim_line_length = clip_turn_range


## The point the body turn aims the nose at: on the noted aim line, clip_turn_range ahead of the mech's nearest point on
## that line, or the crosshair point when that is nearer.
func _turn_point() -> Vector3:
	var foot := _aim_line_origin + _aim_line_dir * (_flat(controller.mech.global_position) - _aim_line_origin).dot(_aim_line_dir)
	var reach := clampf(_aim_line_length - (foot - _aim_line_origin).dot(_aim_line_dir), 0.0, clip_turn_range)
	return foot + _aim_line_dir * reach


func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v


## Heading (Node3D rotation.y) that faces along the flat vector v.
func _yaw_of(v: Vector3) -> float:
	return atan2(-v.x, -v.z)


## Cuts the clip (MeleeAttack.cut_after_hit): it fades into the pose under it, with a soft landing when it was cut in
## the air (cut_landing_height).
func _cut_clip(clip: MeleeAttack) -> void:
	# Only a mech in the air lands (clip 3 hits before it leaves the ground when the target is near).
	_landing_due = clip.cut_landing_height if _melee.lowest_sole_height() > clip_landing_air_m else 0.0
	_melee.stop_external(self, true, _landing_due > 0.0)


## The arm takes the weapon's grip again and the weapon is idle. A clip cut in the air lands now (the fall fade is over:
## the feet are down).
func _end_clip() -> void:
	var recovery := controller.mech.landing_recovery
	if _landing_due > 0.0 and recovery != null and not controller.mech.is_fallen:
		recovery.start_landing(_landing_due)
	_landing_due = 0.0
	var ik := controller.holding_arm_ik()
	if ik.target == null:
		ik.target = _saved_target
	_pose_weight = 0.0
	state = State.IDLE


## SkeletalMeleeAnimation asks: the clip's travel turns with the mech while the body turn is on.
func clip_travel_follows_heading() -> bool:
	return clip_turn_speed_deg > 0.0 and state == State.CLIP


## Grip the arm IK should hold while the punch clip has the arm (WeaponController.fist_hang_target: the arm rig
## poses it there under the clip, so the clip fades into the rest hold), or null.
func clip_hold_target() -> Node3D:
	if state == State.CLIP or (is_instance_valid(_melee) and _melee.is_external_busy(self)):
		return _saved_target
	return null


## The clip aim for SkeletalMeleeAnimation (empty when none): which arm, the crosshair point (world), the nose in the
## forearm bone's frame, the weight now and the largest turn.
func clip_aim() -> Dictionary:
	if state != State.CLIP or clip_aim_strength <= 0.0 or not is_instance_valid(_bone_attach) or not is_instance_valid(_melee):
		return {}
	var clip := punch_clip()
	var time := _melee.external_time(self)
	if clip == null or clip.strikes.size() == 0 or time < 0.0:
		return {}
	var window := clip.strikes[0]
	var weight := smoothstep(window.x - clip_aim_lead, window.x, time) \
			* (1.0 - smoothstep(window.y, window.y + clip_aim_release, time))
	if has_fired:
		weight *= 1.0 - clampf(_since_fire / maxf(clip_aim_release, 0.01), 0.0, 1.0)
	var nose := (_bone_attach.global_transform.affine_inverse() * _nose.global_transform).origin
	return {"right": not is_left, "point": controller.mech_aim.aim_point, "nose": nose,
			"weight": weight * clip_aim_strength, "max_deg": clip_aim_max_deg}


## Contact during the clip: a ray along the stakes from behind the nose to contact_reach past it.
func _check_clip_contact() -> void:
	var forward := -_nose.global_basis.z.normalized()
	var start := _nose.global_position - forward * clip_contact_back
	var query := PhysicsRayQueryParameters3D.create(start, _nose.global_position + forward * contact_reach,
			collision_mask, controller.mech.get_hit_exclude())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_fire_stake(hit.position, hit.normal, hit.collider, forward)


func _lower_time() -> float:
	return maxf(recover_time * lower_time_scale, 0.01)


func _next(next_state: State) -> void:
	state = next_state
	_time = 0.0


## Holding RMB: the fist pulls back to a guard, the stake cocks back, energy drains into the stake.
## Release RMB or run out of energy: the attack starts.
func _update_power(delta: float) -> void:
	var energy := controller.mech.energy
	var has_energy := energy.try_drain(power_energy_per_second * delta)
	if has_energy:
		power = minf(power + delta / power_time, 1.0)
	_pose_weight = move_toward(_pose_weight, 1.0, delta * guard_speed)
	_action = _charge
	_twist = lerpf(0.0, charge_twist_deg, smoothstep(0.0, 1.0, _pose_weight))
	if controller.camera_shake != null:
		controller.camera_shake.hold_shake(lerpf(power_shake_min, power_shake_max, power))
	if not trigger_held or not has_energy:
		_start()


func _update_stake(delta: float) -> void:
	if has_fired and (state in [State.PUNCH, State.HOLD, State.LEAP] or (state == State.CLIP and _since_fire < hold_time)):
		stake_out = move_toward(stake_out, 1.0, delta / stake_out_time)
	else:
		stake_out = move_toward(stake_out, 0.0, delta / stake_back_time)
	var cocked := -cock_distance * power if state in [State.POWER, State.CHARGE, State.WINDUP] \
			or (state in [State.CLIP, State.LEAP] and not has_fired) else 0.0
	_stake.position = _stake_rest + Vector3(0.0, 0.0, -stake_travel * stake_out - cocked)
	_glow.level = power if state in [State.POWER, State.CHARGE, State.WINDUP, State.PUNCH] \
			or (state in [State.CLIP, State.LEAP] and not has_fired) else 0.0
	_update_spin(delta)
	_update_claws(delta)


## The claws open when the stake hits or the punch misses (the clip's strike window or the punch hold ended) and
## close when the weapon is idle again.
func _update_claws(delta: float) -> void:
	if _claws.is_empty():
		return
	var open := state == State.RECOVER or (state in [State.PUNCH, State.HOLD, State.CLIP, State.LEAP]
			and (has_fired or _clip_missed))
	if open:
		_claw_open = move_toward(_claw_open, 1.0, delta / maxf(claw_open_time, 0.01))
	else:
		_claw_open = move_toward(_claw_open, 0.0, delta / maxf(claw_close_time, 0.01))
	var angle := deg_to_rad(claw_open_deg) * smoothstep(0.0, 1.0, _claw_open)
	for i in _claws.size():
		_claws[i].basis = Basis(_claw_axes[i], angle) * _claw_rest[i]


## The drill spins from the charge until the stake hits or the punch misses.
func _update_spin(delta: float) -> void:
	if spin_speed_deg == 0.0:
		return
	var spinning := not has_fired and (state in [State.POWER, State.CHARGE, State.WINDUP, State.PUNCH, State.HOLD, State.LEAP]
			or (state == State.CLIP and not _clip_missed))
	if spinning:
		_spin = move_toward(_spin, 1.0, delta / maxf(spin_up_time, 0.01))
	else:
		_spin = move_toward(_spin, 0.0, delta / maxf(spin_down_time, 0.01))
	_spin_angle = fmod(_spin_angle + deg_to_rad(spin_speed_deg) * _spin * delta, TAU)
	_stake.basis = _stake_basis * Basis(Vector3.BACK, _spin_angle)


func _start() -> void:
	var mech := controller.mech
	mech.melee_charge_speed_scale = 1.0
	if punch_clip() == null or clip_number in leap_clip_numbers:
		_start_leap()
		return
	_aim_point = controller.mech_aim.aim_point
	var to_point := _aim_point - mech.global_position
	to_point.y = 0.0
	var direction := to_point.normalized()
	if direction.is_zero_approx():
		var aim := controller.mech_aim.aim_direction
		direction = Vector3(aim.x, 0.0, aim.z).normalized()
	var distance := clampf(to_point.length() - stop_distance, 0.0, data.lunge_distance)
	mech.start_lunge(direction, data.lunge_speed, distance)
	# One punch per fire_rate wait, hit or miss.
	_cooldown = 1.0 / maxf(data.fire_rate, 0.01)
	has_fired = false
	_next(State.CHARGE)


## The leap at the target (user request 2026-11-02): the mech jumps toward the blue ring, stopping stop_distance short
## of it, no farther than the forward dodge; the arm swings during the flight so the stakes hit at its end.
func _start_leap() -> void:
	var mech := controller.mech
	_aim_point = controller.mech_aim.aim_point
	if is_instance_valid(_melee) and _melee.is_external_busy(self):
		_melee.stop_external(self)
	var ik := controller.holding_arm_ik()
	if ik.target == null and _saved_target != null:
		ik.target = _saved_target
	var to_point := _aim_point - mech.global_position
	to_point.y = 0.0
	var direction := to_point.normalized()
	if direction.is_zero_approx():
		var aim := controller.mech_aim.aim_direction
		direction = Vector3(aim.x, 0.0, aim.z).normalized()
	var distance := clampf(to_point.length() - stop_distance, 0.0, leap_reach())
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * mech.gravity_scale
	var up_speed := sqrt(2.0 * gravity * maxf(leap_height, 0.1))
	_leap_time = 2.0 * up_speed / gravity
	mech.velocity.y = up_speed
	mech.start_lunge(direction, distance / _leap_time, distance)
	_cooldown = 1.0 / maxf(data.fire_rate, 0.01)
	has_fired = false
	_next(State.LEAP)


## The longest leap (m): leap_max_distance, or the forward dodge length.
func leap_reach() -> float:
	if leap_max_distance >= 0.0:
		return leap_max_distance
	var dodge := controller.mech.dodge
	if dodge != null and dodge.animation != null and dodge.animation.step_forward != null:
		return dodge.animation.step_forward.distance
	return dodge.distance if dodge != null else 12.0


## In the leap: the wind-up, then the swing to the aimed punch; the stakes fire on contact; on the landing the punch
## holds (HOLD, then RECOVER as after the coded punch).
func _update_leap() -> void:
	var t := clampf(_time / maxf(_leap_time, 0.01), 0.0, 1.0)
	_pose_weight = 1.0
	_punch = _aimed_punch()
	if t < leap_swing_start:
		var k := smoothstep(0.0, 1.0, t / maxf(leap_swing_start, 0.01))
		_action = _charge.interpolate_with(_windup, k)
		_twist = lerpf(charge_twist_deg, windup_twist_deg, k)
	else:
		var k := pow(clampf((t - leap_swing_start) / maxf(leap_swing_end - leap_swing_start, 0.01), 0.0, 1.0), 1.5)
		_action = _windup.interpolate_with(_punch, k)
		_twist = lerpf(windup_twist_deg, punch_twist_deg, k)
	if not has_fired and t >= leap_contact_start:
		_check_contact()
	var landed := _time > 0.15 and controller.mech.is_on_floor()
	if landed or _time > _leap_time + 0.4:
		controller.mech.is_lunging = false
		_action = _punch
		_next(State.HOLD)


## Fires the stake when the nose touches something: a ray along the punch line (fist toward the
## aim point) from behind the fist (so a target already inside the arm's reach still counts) to
## contact_reach past the nose.
func _check_contact() -> void:
	# Along the punch line: from the fist toward the aim point (the blue ring), as far as the nose
	# plus contact_reach.
	var forward := (_aim_point - global_position).normalized()
	if forward.is_zero_approx():
		forward = -_nose.global_basis.z.normalized()
	var reach := global_position.distance_to(_nose.global_position) + contact_reach
	var start := global_position - forward * contact_back
	var query := PhysicsRayQueryParameters3D.create(start, global_position + forward * reach,
			collision_mask, controller.mech.get_hit_exclude())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_fire_stake(hit.position, hit.normal, hit.collider, forward)


func _fire_stake(point: Vector3, normal: Vector3, body: Object, forward: Vector3) -> void:
	# Uses a stake but keeps the punch wait that started with the charge.
	var wait := _cooldown
	consume()
	_cooldown = wait
	has_fired = true
	# Back to the start of the punch pose hold, so the stake stays out for the full hold time.
	if state == State.HOLD:
		_time = 0.0
	var force := lerpf(min_power, 1.0, power)
	var effect := IMPACT.instantiate() as Node3D
	controller.get_world().add_child(effect)
	effect.global_position = point
	effect.look_at(point + normal, Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD)
	effect.scale = Vector3.ONE * 2.0 * force
	if body != null and body.has_method(&"on_hit"):
		body.on_hit(data.damage * force, controller.mech.global_position if controller.mech != null else Vector3.INF, &"punch")
		# Stagger: stagger_points with no power, twice that at full power.
		MechStability.hit_body(body, data.stagger_points * (1.0 + power), 0, 0.0,
				controller.mech.global_position if controller.mech != null else Vector3.INF)
	# Strong force: the mech is pushed back, big screen shake and aim kick.
	var mech := controller.mech
	var back := Vector3(-forward.x, 0.0, -forward.z).normalized() * push_back_speed * force
	mech.velocity.x = back.x
	mech.velocity.z = back.z
	controller.mech_aim.kick_aim(data.recoil_up_deg * force, data.recoil_side_deg * force, force)
	if controller.camera_shake != null:
		controller.camera_shake.add_shake(data.shake_trauma * force, data.shake_kick * force)
	fired.emit()


## Punch pose (torso space) with the fist toward the aim point: along the line from the right
## shoulder, inside a cone around straight ahead. The torso turns during the attack, so this is
## worked out again each frame.
func _aimed_punch() -> Transform3D:
	var torso := controller.torso
	var shoulder := controller.holding_arm_ik().root_joint.position
	var local := torso.global_transform.affine_inverse() * _aim_point
	var direction := (local - shoulder).normalized()
	var ahead := _side(punch_direction).normalized()
	var angle := ahead.angle_to(direction)
	var limit := deg_to_rad(punch_cone_deg)
	if angle > limit:
		direction = ahead.slerp(direction, limit / angle).normalized()
	return _pose_at(shoulder + direction * punch_reach, direction)


func get_pose(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	var normal := rest.interpolate_with(aim, t)
	return normal.interpolate_with(_action, smoothstep(0.0, 1.0, _pose_weight))


## A right arm place or direction on this arm's side (mirrored for the left hand).
func _side(vector: Vector3) -> Vector3:
	return WeaponController.mirror_point(vector) if is_left else vector


## Transform whose -Z (stake direction) points along direction, at position.
func _pose_from(point: Vector3, direction: Vector3) -> Transform3D:
	return _pose_at(_side(point), _side(direction))


## Same, with the place and direction already on this arm's side.
func _pose_at(point: Vector3, direction: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(direction.normalized().y) < 0.95 else Vector3.BACK
	return Transform3D(Basis.looking_at(direction.normalized(), up), point)


func get_status_text() -> String:
	var text := super.get_status_text()
	match state:
		State.POWER:
			text += "  POWER %d%%" % roundi(power * 100.0)
		State.CHARGE:
			text += "  CHARGE"
		State.LEAP:
			text += "  HIT" if has_fired else "  LEAP"
		State.WINDUP, State.PUNCH:
			text += "  PUNCH"
		State.CLIP:
			text += "  HIT" if has_fired else "  PUNCH"
		State.HOLD:
			text += "  HIT" if has_fired else "  MISS"
	if clips != null:
		var clip_name := clips.get_clip_name(clip_number)
		text += "  [%d %s%s]" % [clip_number, clip_name, "" if punch_clip() != null else ": none"]
	return text
