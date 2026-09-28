class_name PileBunkerWeapon
extends MechWeapon
## A pile bunker on the right forearm (like the shield on the left). RMB: a shield charge, then a punch.
## The weapon root is only the fist target for the arm IK; the model ("Mount") moves onto the forearm.
## The mech charges toward the target (or along the aim) with the shield up and the torso turned
## so the left shoulder (shield) leads. At the end of the charge the torso twists back and the right
## arm pulls back, then the arm punches forward. When the front of the pile bunker touches something,
## the stake (the "needle") fires out with a strong force. No contact = no shot (no ammo used).
## Uses ammo (one stake cartridge per shot) and the lunge uses energy.

const IMPACT := preload("res://scenes/effects/impact_spark.tscn")

## Weapon poses in torso space: position of the grip, then the direction the stake points.
## Guard: fist in front of the right chest during the charge.
@export var guard_position: Vector3 = Vector3(2.3, 1.8, -1.6)
@export var guard_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
## Wind-up: fist pulled back at the right side.
@export var windup_position: Vector3 = Vector3(2.5, 1.6, 0.6)
@export var windup_direction: Vector3 = Vector3(-0.1, 0.0, -1.0)
## Punch: arm reaching forward.
@export var punch_position: Vector3 = Vector3(1.2, 2.3, -4.7)
@export var punch_direction: Vector3 = Vector3(-0.15, 0.0, -1.0)

## Model place on the right forearm (elbow space: -Y runs down the forearm to the fist, -X is the
## outer side, +Z is the top of the forearm).
@export var mount_position: Vector3 = Vector3(-1.0, -1.6, 0.0)
@export var mount_rotation_deg: Vector3 = Vector3(-90.0, 0.0, 180.0)

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
## Time back to the rest pose, in seconds.
@export var recover_time: float = 0.45

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
@export_flags_3d_physics var collision_mask: int = 13

@export_group("Charge")
## Stop this far in front of the target (target center), in meters.
@export var stop_distance: float = 8.0
## Targets inside this cone around the aim can pull the charge, in degrees.
@export var target_cone_deg: float = 20.0

enum State { IDLE, CHARGE, WINDUP, PUNCH, HOLD, RECOVER }

var state: State = State.IDLE
## 0 = stake in, 1 = stake fully out.
var stake_out: float = 0.0
## True from the stake shot until the next charge.
var has_fired: bool = false

var _time: float = 0.0
var _guard := Transform3D.IDENTITY
var _windup := Transform3D.IDENTITY
var _punch := Transform3D.IDENTITY
## 0 = normal pose, 1 = action pose.
var _pose_weight: float = 0.0
## Action pose now (between guard, wind-up and punch).
var _action := Transform3D.IDENTITY
var _twist: float = 0.0
var _stake_rest := Vector3.ZERO

@onready var _mount: Node3D = $Mount
@onready var _stake: Node3D = $Mount/Stake
@onready var _nose: Node3D = $Mount/Nose


func _ready() -> void:
	_guard = _pose_from(guard_position, guard_direction)
	_windup = _pose_from(windup_position, windup_direction)
	_punch = _pose_from(punch_position, punch_direction)
	_action = _guard
	_stake_rest = _stake.position


func is_melee() -> bool:
	return true


func is_busy() -> bool:
	return state != State.IDLE


## Moves the model onto the right forearm (once, after WeaponController has wired the arm IK).
func _attach_to_forearm() -> void:
	var forearm := controller.arm_ik_right.mid_joint
	if forearm == null or _mount.get_parent() == forearm:
		return
	_mount.reparent(forearm, false)
	_mount.transform = Transform3D(Basis.from_euler(mount_rotation_deg * PI / 180.0), mount_position)

func _update(delta: float) -> void:
	_attach_to_forearm()
	_time += delta
	match state:
		State.IDLE:
			_pose_weight = move_toward(_pose_weight, 0.0, delta / recover_time)
			_twist = move_toward(_twist, 0.0, absf(punch_twist_deg) * delta / recover_time)
			if trigger_pressed() and can_use() and controller.mech.energy.current >= data.lunge_energy:
				_start()
		State.CHARGE:
			_pose_weight = move_toward(_pose_weight, 1.0, delta * guard_speed)
			_action = _guard
			_twist = charge_twist_deg * smoothstep(0.0, 1.0, _pose_weight)
			if not controller.mech.is_lunging:
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
			_action = _windup.interpolate_with(_punch, t)
			_twist = lerpf(windup_twist_deg, punch_twist_deg, t)
			if not has_fired:
				_check_contact()
			if _time >= punch_time:
				_next(State.HOLD)
		State.HOLD:
			_action = _punch
			_twist = punch_twist_deg
			if not has_fired:
				_check_contact()
			if _time >= hold_time:
				_next(State.RECOVER)
		State.RECOVER:
			_pose_weight = move_toward(_pose_weight, 0.0, delta / recover_time)
			_twist = punch_twist_deg * smoothstep(0.0, 1.0, _pose_weight)
			if _pose_weight <= 0.0:
				state = State.IDLE
	_update_stake(delta)
	# Charge with the shield up. The lunge moves the mech, so the shield does not slow it down.
	controller.mech_shield.force_up = state == State.CHARGE
	controller.torso_pose.action_twist_deg = _twist


func _next(next_state: State) -> void:
	state = next_state
	_time = 0.0


func _update_stake(delta: float) -> void:
	if has_fired and (state == State.PUNCH or state == State.HOLD):
		stake_out = move_toward(stake_out, 1.0, delta / stake_out_time)
	else:
		stake_out = move_toward(stake_out, 0.0, delta / stake_back_time)
	_stake.position = _stake_rest + Vector3(0.0, 0.0, -stake_travel * stake_out)


func _start() -> void:
	controller.mech.energy.try_drain(data.lunge_energy)
	var mech := controller.mech
	var aim := controller.mech_aim.aim_direction
	var direction := Vector3(aim.x, 0.0, aim.z).normalized()
	var distance := data.lunge_distance
	var target := _find_target()
	if target != null:
		var to_target := target.global_position - mech.global_position
		to_target.y = 0.0
		direction = to_target.normalized()
		distance = clampf(to_target.length() - stop_distance, 0.0, data.lunge_distance)
	mech.start_lunge(direction, data.lunge_speed, distance)
	# One punch per fire_rate wait, hit or miss.
	_cooldown = 1.0 / maxf(data.fire_rate, 0.01)
	has_fired = false
	_next(State.CHARGE)


## Fires the stake when the nose touches something: a ray along the stake from behind the grip
## (so a target already inside the arm's reach still counts) to contact_reach past the nose.
func _check_contact() -> void:
	var forward := -_nose.global_basis.z.normalized()
	var start := global_position - forward * contact_back
	var query := PhysicsRayQueryParameters3D.create(start, _nose.global_position + forward * contact_reach,
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
	var effect := IMPACT.instantiate() as Node3D
	controller.get_world().add_child(effect)
	effect.global_position = point
	effect.look_at(point + normal, Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD)
	effect.scale = Vector3.ONE * 2.0
	if body != null and body.has_method(&"on_hit"):
		body.on_hit(data.damage)
	# Strong force: the mech is pushed back, big screen shake and aim kick.
	var mech := controller.mech
	var back := Vector3(-forward.x, 0.0, -forward.z).normalized() * push_back_speed
	mech.velocity.x = back.x
	mech.velocity.z = back.z
	controller.mech_aim.kick_aim(data.recoil_up_deg, data.recoil_side_deg, 1.0)
	if controller.camera_shake != null:
		controller.camera_shake.add_shake(data.shake_trauma, data.shake_kick)
	fired.emit()


## The nearest lockable target in the aim cone within the charge reach.
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance := data.lunge_distance + stop_distance + 2.0
	var origin := controller.mech.global_position
	var aim := controller.mech_aim.aim_direction
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var target := node as Node3D
		var to_target := target.global_position - origin
		var distance := to_target.length()
		if distance > best_distance:
			continue
		if rad_to_deg(aim.angle_to(to_target.normalized())) > target_cone_deg:
			continue
		best = target
		best_distance = distance
	return best


func get_pose(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	var normal := rest.interpolate_with(aim, t)
	return normal.interpolate_with(_action, smoothstep(0.0, 1.0, _pose_weight))


## Transform whose -Z (stake direction) points along direction, at position.
func _pose_from(position: Vector3, direction: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(direction.normalized().y) < 0.95 else Vector3.BACK
	return Transform3D(Basis.looking_at(direction.normalized(), up), position)


func get_status_text() -> String:
	var text := super.get_status_text()
	match state:
		State.CHARGE:
			text += "  CHARGE"
		State.WINDUP, State.PUNCH:
			text += "  PUNCH"
		State.HOLD:
			text += "  HIT" if has_fired else "  MISS"
	return text
