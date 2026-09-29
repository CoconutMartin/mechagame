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

@export_group("Charge")
## The charge goes toward the mech aim point (the blue ring) and stops this far from it (flat
## distance from the mech center), so the punch reaches it. In meters.
@export var stop_distance: float = 7.0
## The punch goes at the aim point: hand distance from the shoulder (the arm is 5.7 m long), and
## the widest angle from straight ahead, in degrees.
@export var punch_reach: float = 4.9
@export var punch_cone_deg: float = 60.0

enum State { IDLE, POWER, CHARGE, WINDUP, PUNCH, HOLD, RECOVER }

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
## 0 = normal pose, 1 = action pose.
var _pose_weight: float = 0.0
## Action pose now (between guard, wind-up and punch).
var _action := Transform3D.IDENTITY
var _twist: float = 0.0
var _stake_rest := Vector3.ZERO
## The point the charge and the punch go for (world): the blue ring when the attack starts.
var _aim_point := Vector3.ZERO

@onready var _mount: Node3D = $Mount
@onready var _stake: Node3D = $Mount/Stake
@onready var _nose: Node3D = $Mount/Nose
@onready var _glow := ChargeGlow.new()


func _ready() -> void:
	_guard = _pose_from(guard_position, guard_direction)
	_windup = _pose_from(windup_position, windup_direction)
	_punch = _pose_from(punch_position, punch_direction)
	_action = _guard
	_stake_rest = _stake.position
	# The drum and the nose ring glow with the stored power.
	_glow.color = Color(1.0, 0.55, 0.2)
	add_child(_glow)
	var drum: Array[MeshInstance3D] = [$Mount/Drum as MeshInstance3D]
	_glow.setup(drum, $Mount/NoseRing as MeshInstance3D, _nose)


func is_melee() -> bool:
	return true


func is_busy() -> bool:
	return state != State.IDLE


## Stops the attack (the mech falls over): no more charge or punch, the arm goes back to rest.
func cancel() -> void:
	if state == State.IDLE:
		return
	controller.mech.is_lunging = false
	controller.mech_shield.force_up = false
	_next(State.RECOVER)


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
				power = 0.0
				_next(State.POWER)
		State.POWER:
			_update_power(delta)
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


## Holding RMB: the fist pulls back to a guard, the stake cocks back, energy drains into the stake.
## Release RMB or run out of energy: the attack starts.
func _update_power(delta: float) -> void:
	var energy := controller.mech.energy
	var has_energy := energy.try_drain(power_energy_per_second * delta)
	if has_energy:
		power = minf(power + delta / power_time, 1.0)
	_pose_weight = move_toward(_pose_weight, 1.0, delta * guard_speed)
	_action = _guard.interpolate_with(_windup, 0.35 * power)
	_twist = lerpf(0.0, charge_twist_deg, smoothstep(0.0, 1.0, _pose_weight))
	if controller.camera_shake != null:
		controller.camera_shake.hold_shake(lerpf(power_shake_min, power_shake_max, power))
	if not trigger_held or not has_energy:
		_start()


func _update_stake(delta: float) -> void:
	if has_fired and (state == State.PUNCH or state == State.HOLD):
		stake_out = move_toward(stake_out, 1.0, delta / stake_out_time)
	else:
		stake_out = move_toward(stake_out, 0.0, delta / stake_back_time)
	var cocked := -cock_distance * power if state in [State.POWER, State.CHARGE, State.WINDUP] else 0.0
	_stake.position = _stake_rest + Vector3(0.0, 0.0, -stake_travel * stake_out - cocked)
	_glow.level = power if state in [State.POWER, State.CHARGE, State.WINDUP, State.PUNCH] else 0.0


func _start() -> void:
	var mech := controller.mech
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
		body.on_hit(data.damage * force)
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
	var shoulder := controller.arm_ik_right.root_joint.position
	var local := torso.global_transform.affine_inverse() * _aim_point
	var direction := (local - shoulder).normalized()
	var ahead := punch_direction.normalized()
	var angle := ahead.angle_to(direction)
	var limit := deg_to_rad(punch_cone_deg)
	if angle > limit:
		direction = ahead.slerp(direction, limit / angle).normalized()
	return _pose_from(shoulder + direction * punch_reach, direction)


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
		State.POWER:
			text += "  POWER %d%%" % roundi(power * 100.0)
		State.CHARGE:
			text += "  CHARGE"
		State.WINDUP, State.PUNCH:
			text += "  PUNCH"
		State.HOLD:
			text += "  HIT" if has_fired else "  MISS"
	return text
