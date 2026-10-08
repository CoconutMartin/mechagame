class_name PartBreaker
extends Node
## What happens to a part when it is damaged or destroyed (MechHealth signals). MechDeath handles
## the death of the whole mech and uses the helpers here.
## Below half HP a part smokes. Destroyed parts:
##   Head: falls off (the mech dies).
##   Arm: falls off with its weapon (right) or its shield (left). That weapon is lost.
##   Side torso: its armor is blown away, and its arm (and back unit on that side) falls off.
##   Leg: explodes, the armor is gone and the inner frame shows. One leg left: walks 60% slower
##        with short limping steps; boost speed stays and the jump jets still work; the mech falls
##        over after a ground boost (MechFall).
##   Shield, back unit: falls off, that weapon is lost.
##   Booster (backpack): explodes, no more boost; the fuel blast damages the torso parts
##        (fuel_damage x the mech's total max HP, split over center, left and right torso).

const EXPLOSION := preload("res://scenes/effects/explosion.tscn")
const IMPACT := preload("res://scenes/effects/impact_spark.tscn")

@export var mech: Mech
@export var health: MechHealth
@export var weapons: WeaponController
@export var camera_shake: CameraShake
## The frame (Visual). Its socket nodes stay; the part nodes on them fall off.
@export var frame: Node3D

## Part HP fraction where smoke starts.
@export_range(0.0, 1.0) var smoke_below: float = 0.5
## One leg destroyed: walk (and boost) speed x this value.
@export var one_leg_speed_scale: float = 0.4
## Booster explosion damage, as a part of the mech's total max HP (all parts). It is split evenly
## over the center, left and right torso.
@export var fuel_damage: float = 0.2
## Kick of a falling part, m/s (sideways and up).
@export var drop_push: float = 5.0

var _smoking := {}


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.part_destroyed.connect(_on_part_destroyed)


func _on_damaged(key: String, _amount: float) -> void:
	if _smoking.has(key) or not health.is_part_alive(key) or health.get_fraction(key) >= smoke_below:
		return
	var place := _part_place(key)
	if place.is_empty():
		return
	_smoking[key] = DamageSmoke.create(place[0], place[1])


func _on_part_destroyed(key: String) -> void:
	if camera_shake != null:
		camera_shake.add_shake(0.25, 0.3)
	match key:
		"Head":
			drop(health.get_nodes(key), Vector3.UP)
		"Arm L", "Arm R":
			break_arm(key, _side_out(key))
		"Torso L", "Torso R":
			_break_side_torso(key)
		"Leg L", "Leg R":
			_break_leg(key)
		"Shield":
			var nodes := weapons.shield_nodes.duplicate()
			weapons.lose_shield()
			drop(nodes, -mech.global_basis.x)
		"Back L", "Back R":
			break_back(key, Vector3.UP - mech.global_basis.z)
		"Booster":
			_break_booster()


## An arm falls off (no explosion) with its weapon or shield.
func break_arm(key: String, away: Vector3) -> void:
	var left := key == "Arm L"
	var nodes := health.get_nodes(key) + _loose_children(["ShoulderL", "ElbowL"] if left else ["ShoulderR", "ElbowR"])
	if left:
		nodes += weapons.shield_nodes
		if health.is_part_alive("Shield"):
			health.remove_part("Shield")
		weapons.lose_left_arm()
	else:
		if weapons.right_weapon != null:
			nodes.append(weapons.right_weapon)
		weapons.lose_right_weapon()
	drop(nodes, away)
	_socket_smoke("ShoulderL" if left else "ShoulderR")


## A back unit falls off.
func break_back(key: String, away: Vector3) -> void:
	var pod := weapons.back_left if key == "Back L" else weapons.back_right
	if pod == null:
		return
	if health.is_part_alive(key):
		health.remove_part(key)
	weapons.lose_back_weapon(pod)
	drop([pod] as Array[Node3D], away)


## Side torso destroyed: armor blown away, the arm and the back unit on that side fall off.
func _break_side_torso(key: String) -> void:
	var left := key == "Torso L"
	blow_away(key, 0.5)
	var arm := "Arm L" if left else "Arm R"
	if health.is_part_alive(arm):
		health.remove_part(arm)
		break_arm(arm, _side_out(arm))
	var back := "Back L" if left else "Back R"
	if health.is_part_alive(back):
		break_back(back, _side_out(arm) + Vector3.UP)


## A leg explodes: its armor is gone and the inner frame shows.
func _break_leg(key: String) -> void:
	var left := key == "Leg L"
	var knee := frame.find_child("KneeL" if left else "KneeR", true, false) as Node3D
	if knee != null:
		explode_at(knee.global_position, 3.0)
		DamageSmoke.create(knee, Vector3.ZERO, true)
	for node in health.get_nodes(key):
		_strip_armor(node)
	if health.is_alive():
		mech.one_leg = true
		mech.broken_leg_side = -1.0 if left else 1.0
		mech.walk_speed *= one_leg_speed_scale
		# The boosters still work: boost speed stays the same. The limping steps are shorter.
		mech.boost_speed_multiplier /= one_leg_speed_scale
		mech.footsteps.stride_length *= one_leg_speed_scale
		_fall_after_leg_loss()


## A leg broke on a living mech: in the air it falls over after landing; during a pile bunker
## attack it falls over now.
func _fall_after_leg_loss() -> void:
	var fall := mech.fall_control
	if fall == null:
		return
	if not mech.is_on_floor():
		fall.fall_on_landing()
		return
	var bunker := weapons.right_weapon as PileBunkerWeapon
	if bunker != null and bunker.is_busy():
		bunker.cancel()
		fall.fall()


## The booster (backpack) explodes: no more boost. Its fuel blast damages the torso: fuel_damage x
## the mech's total max HP, split over the torso parts.
func _break_booster() -> void:
	blow_away("Booster", 0.8)
	mech.can_boost = false
	var flames := mech.find_child("BoosterFlames", true, false) as BoosterFlames
	if flames != null:
		flames.disable()
	var total := 0.0
	for key: String in health.max_hp:
		total += health.max_hp[key]
	var torso := ["Torso C", "Torso L", "Torso R"].filter(func(key: String) -> bool: return health.max_hp.has(key))
	if torso.is_empty():
		return
	var blast := total * fuel_damage / torso.size()
	for key: String in torso:
		health.damage.call_deferred(key, blast)


## Blows away the armor of a part with an explosion and sparks. Its skeleton (frame and joint
## meshes: struts, rollers, joint balls and hubs) stays in place.
func blow_away(key: String, size: float = 1.0) -> void:
	var nodes := health.get_nodes(key)
	var center := center_of(nodes)
	explode_at(center, 7.0 * size)
	for node in nodes:
		if is_instance_valid(node):
			_strip_armor(node)
	var place := _part_place(key)
	if not place.is_empty():
		DamageSmoke.create(place[0], place[1], true)


## An explosion effect. size = flash size in meters.
func explode_at(point: Vector3, size: float = 7.0) -> void:
	var effect := EXPLOSION.instantiate() as Explosion
	effect.flash_size = size
	world().add_child(effect)
	effect.global_position = point
	for i in 3:
		var spark := IMPACT.instantiate() as Node3D
		world().add_child(spark)
		spark.global_position = point + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))


## Moves nodes into a falling debris body.
func drop(nodes: Array[Node3D], away: Vector3) -> Debris:
	var unique: Array[Node3D] = []
	for node in nodes:
		if is_instance_valid(node) and not unique.has(node):
			unique.append(node)
	var push := mech.velocity + (away.normalized() + Vector3.UP * 0.8) * drop_push
	return Debris.drop(unique, world(), push)


## Keeps only the inner frame and joints of a part visible.
func _strip_armor(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh := root as MeshInstance3D
		var material := mesh.get_active_material(0)
		var kind := PartLook.material_name(material) if material != null else ""
		if not (kind.begins_with("frame") or kind.begins_with("joint")):
			mesh.visible = false
	for child in root.get_children():
		_strip_armor(child)


func _side_out(arm_key: String) -> Vector3:
	return -mech.global_basis.x if arm_key == "Arm L" else mech.global_basis.x


## Children of these frame sockets that are not frame sockets, hitboxes or smoke (for example the
## pile bunker model on the forearm).
func _loose_children(socket_names: Array) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for socket_name: String in socket_names:
		var socket := frame.find_child(socket_name, true, false)
		if socket == null:
			continue
		for child in socket.get_children():
			if child is Node3D and not child.name in ["ShoulderL", "ShoulderR", "ElbowL", "ElbowR"] \
					and not child is PartHitbox and not child is DamageSmoke:
				found.append(child)
	return found


func _socket_smoke(socket_name: String) -> void:
	var socket := frame.find_child(socket_name, true, false) as Node3D
	if socket != null:
		DamageSmoke.create(socket, Vector3.ZERO, true)


## Where a part's smoke goes: [parent, offset] from its first hitbox or its first node.
func _part_place(key: String) -> Array:
	for hitbox in health.hitboxes.get(key, []):
		if is_instance_valid(hitbox) and hitbox.get_child_count() > 0:
			return [hitbox.get_parent(), hitbox.position + (hitbox.get_child(0) as Node3D).position]
	for node in health.get_nodes(key):
		if is_instance_valid(node) and node.get_parent() is Node3D:
			return [node.get_parent(), node.position]
	return []


## Middle point of nodes (a point in front of the torso if none are left).
func center_of(nodes: Array[Node3D]) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for node in nodes:
		if is_instance_valid(node):
			sum += node.global_position
			count += 1
	return sum / count if count > 0 else mech.global_position + Vector3.UP * 7.0


## The node that holds effects and debris (the level).
func world() -> Node:
	return get_tree().current_scene if get_tree().current_scene != null else mech.get_parent()
