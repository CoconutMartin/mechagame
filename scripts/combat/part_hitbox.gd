class_name PartHitbox
extends AnimatableBody3D
## A hit box on one part of a mech (layer 4, "hitboxes"). It moves with the part (an animatable body:
## physics knows its speed, so flying props and rubble bounce off it). Weapons call
## on_hit(damage, from, kind) on it, and it sends the damage to MechHealth for its part.

const LAYER := 8

var part_key: String = ""
var health: MechHealth


## A box hitbox for part_key that covers bounds (in the parent's space).
static func create(parent: Node3D, key: String, bounds: AABB, mech_health: MechHealth) -> PartHitbox:
	var hitbox := PartHitbox.new()
	hitbox.name = "Hitbox_%s" % key.replace(" ", "")
	hitbox.part_key = key
	hitbox.health = mech_health
	hitbox.collision_layer = LAYER
	hitbox.collision_mask = 0
	# Not synced to physics: with sync on, the body follows only changes of its own local transform
	# (the animation), not the walk of the mech above it, so a moving mech (an AI enemy) kept its
	# hitboxes where it was spawned and shots passed through it.
	hitbox.sync_to_physics = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.2)
	shape.shape = box
	shape.position = bounds.get_center()
	hitbox.add_child(shape)
	parent.add_child(hitbox)
	return hitbox


## from: where the hit came from (world position; Vector3.INF = not known). kind: &"punch" (pile
## bunker), &"blast" (explosion), &"melee" (fists, hammer), &"environment" (buildings, flying props,
## debris) or &"" (anything else).
func on_hit(damage: float, from: Vector3 = Vector3.INF, kind: StringName = &"") -> void:
	if health != null:
		health.damage(part_key, damage, from, kind)
