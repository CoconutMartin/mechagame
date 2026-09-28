class_name PartHitbox
extends StaticBody3D
## A hit box on one part of a mech (layer 4, "hitboxes"). It moves with the part. Weapons call
## on_hit(damage) on it, and it sends the damage to MechHealth for its part.

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
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.2)
	shape.shape = box
	shape.position = bounds.get_center()
	hitbox.add_child(shape)
	parent.add_child(hitbox)
	return hitbox


func on_hit(damage: float) -> void:
	if health != null:
		health.damage(part_key, damage)
