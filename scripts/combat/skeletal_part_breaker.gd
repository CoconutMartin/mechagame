class_name SkeletalPartBreaker
extends Node
## What happens to a rigged mech's part when it is damaged or destroyed (the PartBreaker rules for a
## mech with a skeleton). Below half HP a part smokes. Destroyed parts:
##   Head: explodes and falls off (the mech dies).
##   Arm: falls off.
##   Side torso: explodes, its shoulder and its arm fall off.
##   Leg: explodes and smokes. One leg left: walks 60% slower; boost speed stays.
##   Center torso, groin: explode (the mech dies).
## Falling parts are the skinned meshes frozen at their pose now, in rigid debris.

@export var mech: Mech
@export var health: MechHealth
@export var hitboxes: SkeletalHitboxes
@export var camera_shake: CameraShake
## Part HP fraction where smoke starts.
@export_range(0.0, 1.0) var smoke_below: float = 0.5
## One leg destroyed: walk speed x this value.
@export var one_leg_speed_scale: float = 0.4
## Kick of a falling part, m/s (sideways and up).
@export var drop_push: float = 5.0

var _smoking: Dictionary = {}


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.part_destroyed.connect(_on_part_destroyed)


func _on_damaged(key: String, _amount: float) -> void:
	if _smoking.has(key) or not health.is_part_alive(key) or health.get_fraction(key) >= smoke_below:
		return
	var place := _part_place(key)
	if not place.is_empty():
		_smoking[key] = DamageSmoke.create(place[0], place[1])


func _on_part_destroyed(key: String) -> void:
	if camera_shake != null:
		camera_shake.add_shake(0.25, 0.3)
	var center := get_center(key)
	match key:
		"Head":
			PartBreaker.explode_in(_world(), center, 3.0)
			_drop(key, Vector3.UP)
		"Arm L", "Arm R":
			PartBreaker.explode_in(_world(), center, 2.0)
			_drop(key, _side_out(key))
		"Torso L", "Torso R":
			PartBreaker.explode_in(_world(), center, 7.0)
			_heavy_smoke(key)
			_drop(key, _side_out(key))
			var arm := "Arm L" if key == "Torso L" else "Arm R"
			if health.is_part_alive(arm):
				health.remove_part(arm)
				_drop(arm, _side_out(arm))
		"Leg L", "Leg R":
			PartBreaker.explode_in(_world(), center, 3.0)
			_heavy_smoke(key)
			if health.is_alive():
				mech.one_leg = true
				mech.broken_leg_side = -1.0 if key == "Leg L" else 1.0
				mech.walk_speed *= one_leg_speed_scale
				mech.boost_speed_multiplier /= one_leg_speed_scale
		_:
			PartBreaker.explode_in(_world(), center, 7.0)


## Middle of a part's meshes now (world).
func get_center(key: String) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for mesh: MeshInstance3D in hitboxes.part_meshes.get(key, []):
		if not is_instance_valid(mesh):
			continue
		var local := (mesh.transform * mesh.get_aabb()).get_center()
		if hitboxes.skeleton.is_ancestor_of(mesh):
			sum += _posed(mesh) * (mesh.transform.affine_inverse() * local)
		else:
			sum += mesh.global_position
		count += 1
	return sum / count if count > 0 else mech.global_position + Vector3.UP * 7.0


## The part's meshes fall off: each becomes a plain (not skinned) mesh at its pose now, in debris.
func _drop(key: String, away: Vector3) -> void:
	var nodes: Array[Node3D] = []
	for mesh: MeshInstance3D in hitboxes.part_meshes.get(key, []):
		if not is_instance_valid(mesh) or not hitboxes.skeleton.is_ancestor_of(mesh):
			continue
		var posed := _posed(mesh)
		mesh.skin = null
		mesh.skeleton = NodePath()
		mesh.global_transform = posed
		nodes.append(mesh)
	var push := mech.velocity + (away.normalized() + Vector3.UP * 0.8) * drop_push
	Debris.drop(nodes, _world(), push)


## World transform that shows a mesh skinned to one bone at the bone's pose now.
func _posed(mesh: MeshInstance3D) -> Transform3D:
	var skeleton := hitboxes.skeleton
	var bone: int = hitboxes.mesh_bones[mesh]
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) \
			* skeleton.get_bone_global_rest(bone).affine_inverse() * mesh.transform


func _heavy_smoke(key: String) -> void:
	var place := _part_place(key)
	if not place.is_empty():
		DamageSmoke.create(place[0], place[1], true)


## Where a part's smoke goes: [parent, offset] from its first hitbox (it follows the bone). A
## destroyed part has no hitboxes left: the middle of its meshes, on the bone of its first mesh.
func _part_place(key: String) -> Array:
	for hitbox in health.hitboxes.get(key, []):
		if is_instance_valid(hitbox) and hitbox.get_child_count() > 0:
			return [hitbox.get_parent(), hitbox.position + (hitbox.get_child(0) as Node3D).position]
	var meshes: Array = hitboxes.part_meshes.get(key, [])
	if meshes.is_empty() or not is_instance_valid(meshes[0]):
		return []
	var holder := hitboxes.get_attachment(hitboxes.mesh_bones[meshes[0]])
	return [holder, holder.to_local(get_center(key))]


func _side_out(key: String) -> Vector3:
	return -mech.global_basis.x if key.ends_with("L") else mech.global_basis.x


func _world() -> Node:
	return get_tree().current_scene if get_tree().current_scene != null else mech.get_parent()
