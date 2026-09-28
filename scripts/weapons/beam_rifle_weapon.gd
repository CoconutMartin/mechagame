class_name BeamRifleWeapon
extends MechWeapon
## A two-hand beam sniper rifle. RMB aims down sight (zoom), LMB fires. The beam hits at once
## along a ray to the mech aim point. Uses heat: overheats after a few shots, then cools to zero.

const BEAM := preload("res://scenes/effects/beam_shot.tscn")
const IMPACT := preload("res://scenes/effects/impact_spark.tscn")
const MARK := preload("res://scenes/effects/bullet_mark.tscn")

## Layers the beam hits: 1 world, 2 mechs, 3 props.
@export_flags_3d_physics var collision_mask: int = 7

@onready var _muzzle: Node3D = $Muzzle


func _update(_delta: float) -> void:
	if not trigger_held or not can_use():
		return
	if controller.weapon_pose.aim_amount < 0.9:
		return
	_fire()


func _fire() -> void:
	consume()
	var origin := _muzzle.global_position
	var direction := (controller.mech_aim.aim_point - origin).normalized()
	direction = MechWeapon.spread_direction(direction, data.spread_deg)
	var end := origin + direction * data.range_m
	var query := PhysicsRayQueryParameters3D.create(origin, end, collision_mask, [controller.mech.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
		_impact(hit.position, hit.normal, hit.collider)
	var beam := BEAM.instantiate() as BeamShot
	controller.get_world().add_child(beam)
	beam.show_beam(origin, end)
	_after_shot()


func _impact(point: Vector3, normal: Vector3, body: Object) -> void:
	var effect := IMPACT.instantiate() as Node3D
	controller.get_world().add_child(effect)
	effect.global_position = point
	effect.look_at(point + normal, Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD)
	if body is Mech or body is TargetDummy:
		return
	var mark := MARK.instantiate() as Node3D
	controller.get_world().add_child(mark)
	var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	mark.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), point)
