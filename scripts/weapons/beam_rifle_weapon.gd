class_name BeamRifleWeapon
extends MechWeapon
## A two-hand beam sniper rifle. RMB aims down sight (zoom). Hold LMB to charge (charge_time to
## full), release LMB to fire. Damage, beam width, screen shake and aim jitter grow with the charge.
## The beam hits at once along a ray to the mech aim point. Uses heat: overheats after a few shots,
## then cools to zero.

const BEAM := preload("res://scenes/effects/beam_shot.tscn")
const IMPACT := preload("res://scenes/effects/impact_spark.tscn")
const MARK := preload("res://scenes/effects/bullet_mark.tscn")

## Layers the beam hits: 1 world, 2 mechs, 3 props.
@export_flags_3d_physics var collision_mask: int = 7
## Seconds of holding LMB for a full charge.
@export var charge_time: float = 3.0
## Damage, beam width and kick of a shot with no charge, as a part of a full shot.
@export_range(0.0, 1.0) var min_power: float = 0.25
## Extra screen shake and aim jitter at full charge = weapon data values x this value.
@export var full_charge_kick: float = 2.0

## 0 to 1 while LMB is held.
var charge: float = 0.0

@onready var _muzzle: Node3D = $Muzzle


## True while charging (WeaponController keeps it as the active weapon and raises it).
func is_busy() -> bool:
	return trigger_held


func _update(delta: float) -> void:
	if trigger_held and not overheated:
		charge = minf(charge + delta / charge_time, 1.0)
	elif trigger_released() and can_use():
		_fire()
		charge = 0.0
	else:
		charge = 0.0


func _fire() -> void:
	consume()
	var power := lerpf(min_power, 1.0, charge)
	var origin := _muzzle.global_position
	var direction := (controller.mech_aim.aim_point - origin).normalized()
	direction = MechWeapon.spread_direction(direction, data.spread_deg)
	var end := origin + direction * data.range_m
	var query := PhysicsRayQueryParameters3D.create(origin, end, collision_mask, [controller.mech.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
		_impact(hit.position, hit.normal, hit.collider, power)
	var beam := BEAM.instantiate() as BeamShot
	beam.width *= lerpf(0.5, 1.5, charge)
	controller.get_world().add_child(beam)
	beam.show_beam(origin, end)
	# Screen shake and aim jitter grow with the charge.
	var kick := lerpf(1.0, full_charge_kick, charge)
	controller.mech_aim.kick_aim(data.recoil_up_deg * kick, data.recoil_side_deg * kick, kick)
	if controller.camera_shake != null:
		controller.camera_shake.add_shake(data.shake_trauma * kick, data.shake_kick * kick)
	fired.emit()


func _impact(point: Vector3, normal: Vector3, body: Object, power: float) -> void:
	var effect := IMPACT.instantiate() as Node3D
	controller.get_world().add_child(effect)
	effect.global_position = point
	effect.look_at(point + normal, Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD)
	if body != null and body.has_method(&"on_hit"):
		body.on_hit(data.damage * power)
	if body is Mech or body is TargetDummy:
		return
	var mark := MARK.instantiate() as Node3D
	controller.get_world().add_child(mark)
	var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	mark.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), point)


func get_status_text() -> String:
	var text := super.get_status_text()
	if trigger_held:
		text += "  CHARGE %s %d%%" % [_bar(charge), roundi(charge * 100.0)]
	return text
