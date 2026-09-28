class_name BladeWeapon
extends MechWeapon
## A beam blade (right arm), held upright in the right hand at rest. RMB: a lunge slash.
## The mech charges toward the target (or along the aim) with the shield up, lifting the blade
## overhead. At the end of the charge it swings the blade straight down, fast. The lunge uses
## energy, the slash adds heat. Targets in front within the slash reach get hit (damage in Phase 4).

const IMPACT := preload("res://scenes/effects/impact_spark.tscn")

## Blade pose overhead (during the charge) and at the end of the down swing (torso space).
## Position of the hilt, then the direction the blade points.
@export var windup_position: Vector3 = Vector3(1.3, 5.6, 0.4)
@export var windup_direction: Vector3 = Vector3(0.0, 0.55, 1.0)
@export var slash_end_position: Vector3 = Vector3(0.9, 1.3, -3.3)
@export var slash_end_direction: Vector3 = Vector3(-0.1, -0.6, -1.0)
## Torso turn during the dash: to the right, so the left shoulder (shield) leads. Degrees.
@export var dash_twist_deg: float = -45.0
## Torso turn at the end of the down swing: to the left, so the right shoulder comes forward.
@export var swing_twist_deg: float = 35.0
## Down swing time in seconds.
@export var swing_time: float = 0.18
## How fast the blade lifts overhead at the start of the charge (1 / seconds).
@export var lift_speed: float = 5.0
## Time to come back to rest after the swing, in seconds.
@export var recover_time: float = 0.35
## Stop this far in front of the target, in meters.
@export var stop_distance: float = 7.0
## Targets inside this cone around the aim can pull the lunge, in degrees.
@export var target_cone_deg: float = 20.0

enum State { IDLE, LUNGE, SWING, RECOVER }

var state: State = State.IDLE
var _time: float = 0.0
var _hit_done: bool = false
var _windup := Transform3D.IDENTITY
var _slash_end := Transform3D.IDENTITY
## Pose weight: 0 = normal pose, 1 = slash pose.
var _pose_weight: float = 0.0
## 0 = wind-up, 1 = end of the swing.
var _swing: float = 0.0


func _ready() -> void:
	_windup = _pose_from(windup_position, windup_direction)
	_slash_end = _pose_from(slash_end_position, slash_end_direction)


func _update(delta: float) -> void:
	_time += delta
	match state:
		State.IDLE:
			_pose_weight = move_toward(_pose_weight, 0.0, delta / recover_time)
			if trigger_pressed() and can_use() and controller.mech.energy.current >= data.lunge_energy:
				_start()
		State.LUNGE:
			_pose_weight = move_toward(_pose_weight, 1.0, delta * lift_speed)
			_swing = 0.0
			if not controller.mech.is_lunging and _pose_weight >= 1.0:
				state = State.SWING
				_time = 0.0
				_hit_done = false
				if controller.camera_shake != null:
					controller.camera_shake.add_shake(0.1, 0.15)
		State.SWING:
			_pose_weight = 1.0
			# Fast down swing: accelerates to the end.
			_swing = pow(clampf(_time / swing_time, 0.0, 1.0), 1.6)
			if not _hit_done and _swing > 0.5:
				_hit_done = true
				_hit_targets()
			if _time >= swing_time:
				state = State.RECOVER
				_time = 0.0
		State.RECOVER:
			_pose_weight = move_toward(_pose_weight, 0.0, delta / recover_time)
			if _pose_weight <= 0.0:
				state = State.IDLE
	# Charge with the shield up.
	controller.mech_shield.force_up = state == State.LUNGE
	# Shoulders: left shoulder leads the dash, then the torso twists the right shoulder forward
	# with the down swing.
	var twist := lerpf(dash_twist_deg, swing_twist_deg, _swing) if state != State.IDLE else 0.0
	if state == State.RECOVER or state == State.IDLE:
		twist = swing_twist_deg * smoothstep(0.0, 1.0, _pose_weight)
	elif state == State.LUNGE:
		twist = dash_twist_deg * smoothstep(0.0, 1.0, _pose_weight)
	controller.torso_pose.action_twist_deg = twist


func _start() -> void:
	consume()
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
	state = State.LUNGE
	_time = 0.0
	fired.emit()


## The nearest lockable target in the aim cone within the lunge reach.
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance := data.lunge_distance + stop_distance + data.slash_reach
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


## Hits lockable targets in front within the slash reach (sparks now, damage in Phase 4).
func _hit_targets() -> void:
	var mech := controller.mech
	var aim := controller.mech_aim.aim_direction
	var forward := Vector3(aim.x, 0.0, aim.z).normalized()
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var target := node as Node3D
		var to_target := target.global_position - mech.global_position
		to_target.y = 0.0
		if to_target.length() > data.slash_reach + 3.0 or forward.dot(to_target.normalized()) < 0.3:
			continue
		var effect := IMPACT.instantiate() as Node3D
		controller.get_world().add_child(effect)
		effect.global_position = target.global_position + Vector3.UP * 5.0
		if target.has_method(&"on_hit"):
			target.on_hit(data.damage)
	if controller.camera_shake != null:
		controller.camera_shake.add_shake(0.15, 0.2)


func get_pose(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	var normal := rest.interpolate_with(aim, t)
	var slash := _windup.interpolate_with(_slash_end, _swing)
	return normal.interpolate_with(slash, smoothstep(0.0, 1.0, _pose_weight))


## Transform whose -Z (blade direction) points along direction, at position.
func _pose_from(position: Vector3, direction: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(direction.normalized().y) < 0.95 else Vector3.BACK
	return Transform3D(Basis.looking_at(direction.normalized(), up), position)


func get_status_text() -> String:
	var text := super.get_status_text()
	if state != State.IDLE:
		text += "  SLASH"
	return text
