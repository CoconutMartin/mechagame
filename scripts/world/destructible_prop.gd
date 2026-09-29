class_name DestructibleProp
extends StaticBody3D
## A street prop (car, truck, lamppost) that weapons and mechs can wreck (Phase 4c).
##   Weapons: on_hit() takes HP. At 0 HP a vehicle explodes (burnt wreck, blast), a lamppost snaps.
##   Mechs: a mech that walks into the prop kicks it away (it becomes a loose body). A mech that
##   boosts or runs into it (crush_speed or more) wrecks it.
## A wreck or a kicked prop is a Debris body: it tumbles, the mechs walk through it, and it goes
## after wreck_life seconds.

const EXPLOSION := preload("res://scenes/effects/explosion.tscn")
## Layer 2 (mech bodies).
const MECH_MASK := 2
## Layers a prop blast hits: 3 props (value 4) and 4 hitboxes (value 8).
const BLAST_MASK := 4 | 8

## Hit points.
@export var max_hp: float = 400.0
## Mass in tonnes. Heavier props are kicked less far.
@export var mass_t: float = 1.5
## True for vehicles: at 0 HP they explode and leave a burnt wreck.
@export var explodes: bool = true
## Explosion flash size, in meters.
@export var explosion_size: float = 5.0
## Blast of the explosion: damage at the center (30% at the edge) and radius in meters.
@export var blast_damage: float = 80.0
@export var blast_radius: float = 6.0
## A mech this fast or faster (m/s) wrecks the prop when it runs into it.
@export var crush_speed: float = 12.0
## Kick speed = mech speed x this value x 30 / (30 + mass_t).
@export var kick_scale: float = 1.3
## Seconds the wreck stays.
@export var wreck_life: float = 45.0
## Color of the burnt wreck.
@export var burnt_color: Color = Color(0.09, 0.08, 0.08)

var hp: float = 0.0
var _done: bool = false


func _ready() -> void:
	hp = max_hp
	# A contact area with the same shapes finds the mech bodies (the bodies do not collide).
	var area := Area3D.new()
	area.name = "MechContact"
	area.collision_layer = 0
	area.collision_mask = MECH_MASK
	for child in get_children():
		if child is CollisionShape3D:
			area.add_child((child as CollisionShape3D).duplicate())
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func on_hit(damage: float) -> void:
	if _done:
		return
	hp -= damage
	if hp <= 0.0:
		wreck(Vector3(randf_range(-1.0, 1.0), 4.0, randf_range(-1.0, 1.0)))


func _on_body_entered(body: Node3D) -> void:
	var mech := body as Mech
	if _done or mech == null:
		return
	var flat := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	var speed := flat.length()
	var away := global_position - mech.global_position
	away.y = 0.0
	var direction := flat / speed if speed > 0.5 else away.normalized()
	var kick := direction * maxf(speed, 2.0) * kick_scale * 30.0 / (30.0 + mass_t)
	kick.y = 2.5 * 10.0 / (10.0 + mass_t)
	# Deferred: bodies cannot be added during the physics contact step.
	if speed >= crush_speed or mech.is_boosting:
		wreck.call_deferred(kick + Vector3.UP * 2.0)
	else:
		_knock.call_deferred(kick)


## The prop is destroyed: vehicles explode and burn out, others just break loose.
func wreck(push: Vector3) -> void:
	if _done:
		return
	_done = true
	var center := _center()
	if explodes:
		var effect := EXPLOSION.instantiate() as Explosion
		effect.flash_size = explosion_size
		_world().add_child(effect)
		effect.global_position = center
		_burn()
		Blast.apply(get_world_3d(), center, blast_radius, blast_damage, [get_rid()], BLAST_MASK)
	_loose(push, explodes)


## Knocked away by a mech: a loose body with no smoke.
func _knock(push: Vector3) -> void:
	if _done:
		return
	_done = true
	_loose(push, false)


func _loose(push: Vector3, smoke: bool) -> void:
	var meshes: Array[Node3D] = []
	for child in get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	var debris := Debris.drop(meshes, _world(), push, smoke)
	if debris != null:
		debris.life = wreck_life
		debris.mass = maxf(mass_t, 0.2) * 100.0
		debris.angular_velocity *= 1.0 / (1.0 + mass_t * 0.2)
	queue_free()


## Every mesh turns burnt black.
func _burn() -> void:
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = burnt_color
	burnt.roughness = 0.95
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = burnt


func _center() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for child in get_children():
		if child is MeshInstance3D:
			sum += (child as Node3D).global_position
			count += 1
	return sum / count if count > 0 else global_position + Vector3.UP


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else get_parent()
