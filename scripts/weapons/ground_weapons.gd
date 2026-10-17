class_name GroundWeapons
extends RefCounted
## The weapons that lie on the ground (WeaponDrop): who is near, and the limit on how many there are.
## Static helpers only. Every WeaponDrop is in the group GROUP while it exists.

const GROUP := &"ground_weapons"


## The nearest weapon on the ground that picker may take, within radius meters (flat distance from the
## point to the right grip of the weapon). Null: none.
static func nearest(tree: SceneTree, from: Vector3, radius: float, picker: WeaponController) -> WeaponDrop:
	var best: WeaponDrop = null
	var best_distance := radius
	for node: Node in tree.get_nodes_in_group(GROUP):
		var drop := node as WeaponDrop
		if drop == null or not drop.is_pickable_by(picker):
			continue
		var grip := drop.get_grip_position(&"GripRight")
		var distance := Vector2(grip.x - from.x, grip.z - from.z).length()
		if distance <= best_distance:
			best_distance = distance
			best = drop
	return best


## Keeps at most max_count weapons on the ground (user rule 2026-10-17: 8): the oldest weapon that has no
## owner and that nobody is picking up goes first. keep (the weapon that was just dropped) never goes.
## A weapon that belongs to a mech (a knock-down drop) never goes, so the count can stay above the limit.
static func trim(tree: SceneTree, max_count: int, keep: WeaponDrop = null) -> void:
	var drops: Array[WeaponDrop] = []
	for node: Node in tree.get_nodes_in_group(GROUP):
		var drop := node as WeaponDrop
		if drop != null and not drop.is_queued_for_deletion():
			drops.append(drop)
	var over := drops.size() - max_count
	if over <= 0:
		return
	drops.sort_custom(func(a: WeaponDrop, b: WeaponDrop) -> bool: return a.serial < b.serial)
	for drop in drops:
		if over <= 0:
			return
		if drop != keep and drop.is_free_to_remove():
			drop.queue_free()
			over -= 1


## True when any mech that is not wrecked stands within distance meters of the point (flat).
static func mech_near(tree: SceneTree, point: Vector3, distance: float) -> bool:
	for node: Node in tree.get_nodes_in_group(&"lockable"):
		var mech := node as Mech
		if mech == null or mech.is_wrecked:
			continue
		if Vector2(mech.global_position.x - point.x, mech.global_position.z - point.z).length() <= distance:
			return true
	return false
