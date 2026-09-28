class_name BeamRifleWeapon
extends MechWeapon
## A two-hand beam sniper rifle. RMB aims down sight (zoom). Hold LMB to charge (charge_time to
## full), release LMB to fire. A charged shot is a sustained beam (like a Kamehameha): it keeps
## firing along the mech aim for up to discharge_time seconds (full charge), hits every tick, pushes
## the aim up and shakes the screen. Damage and beam width grow with the charge. A quick tap fires
## a short shot. Uses heat: overheats after a few shots, then cools to zero.

const BEAM := preload("res://scenes/effects/beam_shot.tscn")
const IMPACT := preload("res://scenes/effects/impact_spark.tscn")
const MARK := preload("res://scenes/effects/bullet_mark.tscn")

## Layers the beam hits: 1 world, 2 mechs, 3 props.
@export_flags_3d_physics var collision_mask: int = 7
## Seconds of holding LMB for a full charge.
@export var charge_time: float = 3.0
## Damage and beam width of a shot with no charge, as a part of a full shot.
@export_range(0.0, 1.0) var min_power: float = 0.25
## Beam time at full charge, in seconds. Less charge = shorter beam (at least min_discharge).
@export var discharge_time: float = 2.0
@export var min_discharge: float = 0.15
## Hit, spark, aim push and shake interval during a sustained beam, in seconds.
@export var tick_time: float = 0.1
## Small steady camera shake while charging: trauma at no charge and at full charge.
@export var charge_shake_min: float = 0.08
@export var charge_shake_max: float = 0.22
## Shake while the beam fires (screen, aim and torso) x this value. 0.7 = 30% less (revision 63).
@export var discharge_shake: float = 0.7
## Screen shake when the charge is released x this value. 0.075 = 85% less than 0.5 (revision 65).
@export var release_shake: float = 0.075
## Extra screen shake and aim jitter at full charge = weapon data values x this value.
@export var full_charge_kick: float = 2.0

## 0 to 1 while LMB is held.
var charge: float = 0.0
## Seconds left in the beam discharge. 0 = not firing.
var discharge_left: float = 0.0

var _power: float = 0.0
var _tick: float = 0.0
var _beam: BeamShot = null
var _last_mark: float = 0.0

@onready var _muzzle: Node3D = $Muzzle
@onready var _glow := ChargeGlow.new()


func _ready() -> void:
	# The barrel coils and the emitter lens light up with the charge.
	add_child(_glow)
	var coils: Array[MeshInstance3D] = []
	for i in 3:
		coils.append(get_node("Coil%d" % i) as MeshInstance3D)
	_glow.setup(coils, $Emitter as MeshInstance3D, _muzzle)


## True while charging or firing (WeaponController keeps it active and raised).
func is_busy() -> bool:
	return trigger_held or discharge_left > 0.0


func _update(delta: float) -> void:
	_glow.level = 1.0 if discharge_left > 0.0 else charge
	if discharge_left > 0.0:
		_update_discharge(delta)
		return
	if trigger_held and not overheated:
		charge = minf(charge + delta / charge_time, 1.0)
		if controller.camera_shake != null:
			controller.camera_shake.hold_shake(lerpf(charge_shake_min, charge_shake_max, charge))
	elif trigger_released() and can_use():
		_start_discharge()
		charge = 0.0
	else:
		charge = 0.0


func _start_discharge() -> void:
	consume()
	_power = lerpf(min_power, 1.0, charge)
	discharge_left = maxf(discharge_time * charge, min_discharge)
	_tick = 0.0
	_beam = BEAM.instantiate() as BeamShot
	_beam.width *= lerpf(0.5, 1.6, charge)
	_beam.hold = true
	controller.get_world().add_child(_beam)
	var kick := lerpf(1.0, full_charge_kick, charge)
	controller.mech_aim.kick_aim(data.recoil_up_deg * kick * 0.5, data.recoil_side_deg * kick * 0.5, kick)
	if controller.camera_shake != null:
		controller.camera_shake.add_shake(data.shake_trauma * kick * release_shake, data.shake_kick * kick * release_shake)
	fired.emit()


func _update_discharge(delta: float) -> void:
	discharge_left -= delta
	var origin := _muzzle.global_position
	var direction := (controller.mech_aim.aim_point - origin).normalized()
	var end := origin + direction * data.range_m
	var query := PhysicsRayQueryParameters3D.create(origin, end, collision_mask, [controller.mech.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
	if is_instance_valid(_beam):
		_beam.show_beam(origin, end)
	# The shoulders and torso shake while the beam fires (more with more charge).
	controller.torso_pose.action_shake = _power * discharge_shake
	_tick -= delta
	if _tick <= 0.0:
		_tick += tick_time
		if not hit.is_empty():
			# Damage per tick adds up to the shot damage x power over the full beam time.
			var share := tick_time / maxf(discharge_time, tick_time)
			_impact(hit.position, hit.normal, hit.collider, data.damage * _power * share * 2.0)
		# The beam pushes the aim up a little and shakes the view while it fires.
		var kick := _power * discharge_shake
		controller.mech_aim.kick_aim(data.recoil_up_deg * 0.12 * kick, data.recoil_side_deg * 0.2 * kick, 0.3 * kick)
		if controller.camera_shake != null:
			controller.camera_shake.add_shake(0.03 * kick, 0.02 * kick)
	if discharge_left <= 0.0:
		discharge_left = 0.0
		controller.torso_pose.action_shake = 0.0
		if is_instance_valid(_beam):
			_beam.release()
		_beam = null


func _impact(point: Vector3, normal: Vector3, body: Object, damage: float) -> void:
	var effect := IMPACT.instantiate() as Node3D
	controller.get_world().add_child(effect)
	effect.global_position = point
	effect.look_at(point + normal, Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD)
	if body != null and body.has_method(&"on_hit"):
		body.on_hit(damage)
	if body is Mech or body is TargetDummy:
		return
	# A scorch mark about every 0.3 s along the beam path.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_mark < 0.3:
		return
	_last_mark = now
	var mark := MARK.instantiate() as Node3D
	controller.get_world().add_child(mark)
	var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	mark.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), point)


func get_status_text() -> String:
	var text := super.get_status_text()
	if discharge_left > 0.0:
		text += "  FIRING %.1f s" % discharge_left
	elif trigger_held:
		text += "  CHARGE %s %d%%" % [_bar(charge), roundi(charge * 100.0)]
	return text
