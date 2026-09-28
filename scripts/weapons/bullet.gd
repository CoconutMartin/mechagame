class_name Bullet
extends Node3D
## A fast bullet with a glowing tracer. Moves in straight steps and checks each step with a ray,
## so it cannot pass through thin walls. Makes an impact effect (sparks, dust) and a bullet mark
## where it hits and damages what it hits (on_hit).

@export var impact_scene: PackedScene
## Mark left on the surface (a decal). Not on mechs.
@export var mark_scene: PackedScene
## Seconds before the bullet disappears when it hits nothing.
@export var lifetime: float = 2.0
## Layers the bullet hits: 1 world, 3 props, 4 hitboxes.
@export_flags_3d_physics var collision_mask: int = 13
## Pull down in m/s² (small, so the path looks almost straight).
@export var gravity: float = 4.0

var velocity: Vector3 = Vector3.ZERO
## Damage on a hit.
var damage: float = 100.0
## Bodies the bullet does not hit (the mech that fired it).
var exclude: Array[RID] = []

var _age: float = 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit.position, hit.normal, hit.collider)
		return
	global_position = to
	look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)


func _impact(point: Vector3, normal: Vector3, hit_body: Object = null) -> void:
	if impact_scene != null:
		var effect := impact_scene.instantiate() as Node3D
		get_parent().add_child(effect)
		effect.global_position = point
		if absf(normal.dot(Vector3.UP)) < 0.99:
			effect.look_at(point + normal, Vector3.UP)
		else:
			effect.look_at(point + normal, Vector3.FORWARD)
	if hit_body != null and hit_body.has_method(&"on_hit"):
		hit_body.on_hit(damage)
	if mark_scene != null and not (hit_body is PartHitbox or hit_body is TargetDummy):
		var mark := mark_scene.instantiate() as Node3D
		get_parent().add_child(mark)
		# The decal projects down its -Y axis: point +Y along the surface normal.
		var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
		mark.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), point)
	queue_free()
