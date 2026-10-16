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
## Layers the bullet hits: 1 world, 3 props, 4 hitboxes, 5 buildings.
@export_flags_3d_physics var collision_mask: int = 29
## Pull down in m/s² (small, so the path looks almost straight).
@export var gravity: float = 4.0
## A hit on the ground with at least this damage leaves a road crater (cannon shells; Crater).
@export var crater_min_damage: float = 150.0
## Crater radius (meters) at crater_min_damage; bigger with more damage.
@export var crater_radius: float = 1.0

var velocity: Vector3 = Vector3.ZERO
## Damage on a hit (at full damage range).
var damage: float = 100.0
## The weapon's data: its damage falloff by the distance from the muzzle to the hit
## (WeaponData.damage_factor), and its max range (the bullet ends there). Null: no falloff, the bullet
## ends after lifetime.
var weapon_data: WeaponData
## Bodies the bullet does not hit (the mech that fired it).
var exclude: Array[RID] = []

var _age: float = 0.0
## Where the bullet started (the muzzle), set on its first physics frame.
var _origin: Vector3 = Vector3.INF
## Meters flown since the muzzle.
var _travelled: float = 0.0
## The tracer streak behind the bullet (scene: a box from the bullet back along +Z).
@onready var _tracer: Node3D = get_node_or_null("Tracer")
@onready var _tracer_length: float = _tracer.position.z * 2.0 if _tracer != null else 0.0


func _ready() -> void:
	_update_tracer()


## The streak grows out of the muzzle as the bullet flies (user report 2026-10-15: at the muzzle the
## full 10.5 m streak reached back through the gun, so bullets seemed to start behind it).
func _update_tracer() -> void:
	if _tracer == null or _tracer_length <= 0.0:
		return
	var amount := clampf(_travelled / _tracer_length, 0.01, 1.0)
	_tracer.scale.z = amount
	_tracer.position.z = _tracer_length * 0.5 * amount


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime or (weapon_data != null and _origin.is_finite()
			and _origin.distance_to(global_position) >= weapon_data.range_m):
		queue_free()
		return
	if not _origin.is_finite():
		_origin = global_position
	velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit.position, hit.normal, hit.collider)
		return
	global_position = to
	_travelled += from.distance_to(to)
	_update_tracer()
	look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)


## Damage of a hit at a point, after the range falloff (distance from the muzzle to the point). The
## falloff is applied here only once; MechHealth subtracts the result from the part.
func get_damage(point: Vector3) -> float:
	if weapon_data == null or not _origin.is_finite():
		return damage
	return damage * weapon_data.damage_factor(_origin.distance_to(point))


func _impact(point: Vector3, normal: Vector3, hit_body: Object = null) -> void:
	if impact_scene != null:
		var effect := impact_scene.instantiate() as Node3D
		get_parent().add_child(effect)
		effect.global_position = point
		if absf(normal.dot(Vector3.UP)) < 0.99:
			effect.look_at(point + normal, Vector3.UP)
		else:
			effect.look_at(point + normal, Vector3.FORWARD)
	var hit_damage := get_damage(point)
	if hit_body != null and hit_body.has_method(&"on_hit"):
		hit_body.on_hit(hit_damage, point - velocity.normalized() * 10.0)
	if hit_body is GroundSlab and hit_damage >= crater_min_damage and normal.y > 0.7:
		Crater.spawn(get_parent(), point, crater_radius * sqrt(damage / crater_min_damage), hit_body as Node)
	if mark_scene != null and not (hit_body is PartHitbox or hit_body is TargetDummy):
		var mark := mark_scene.instantiate() as Node3D
		get_parent().add_child(mark)
		# The decal projects down its -Y axis: point +Y along the surface normal.
		var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
		mark.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), point)
	queue_free()
