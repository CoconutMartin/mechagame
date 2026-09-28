class_name PartBreaker
extends Node
## What happens when a part is damaged or destroyed (MechHealth signals).
## Below half HP a part smokes. Destroyed parts:
##   Head: falls off. Lock-on range and speed drop, the aim shakes more.
##   Arm: falls off with its weapon (right) or its shield (left). That weapon is lost.
##   Legs: stay on, smoke and sparks. Speed drops 60%, no jump.
##   Shield, back unit: falls off, that weapon is lost.
##   Core: the mech explodes (MechHealth.destroyed).

const EXPLOSION := preload("res://scenes/effects/explosion.tscn")

@export var mech: Mech
@export var health: MechHealth
@export var assembler: MechAssembler
@export var weapons: WeaponController
@export var mech_aim: MechAim
@export var jump_charge: MechJumpCharge
@export var camera_shake: CameraShake
## The frame (Visual). Its socket nodes stay; the part nodes on them fall off.
@export var frame: Node3D

## Part HP fraction where smoke starts.
@export_range(0.0, 1.0) var smoke_below: float = 0.5
## Head destroyed: lock-on range and speed x this value, extra aim shake in degrees.
@export var head_lock_scale: float = 0.5
@export var head_jitter_deg: float = 0.6
## Legs destroyed: walk (and boost) speed x this value.
@export var legs_speed_scale: float = 0.4
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
			_drop(_nodes(key), Vector3.UP)
			mech.stats.lock_range *= head_lock_scale
			mech.stats.lock_on_speed *= head_lock_scale
			mech_aim.idle_jitter_deg += head_jitter_deg
			mech_aim.walk_jitter_deg += head_jitter_deg
		"Arm L":
			_break_left_arm(-mech.global_basis.x)
		"Arm R":
			_break_right_arm(mech.global_basis.x)
		"Legs":
			for hip in ["HipL", "HipR"]:
				var socket := frame.find_child(hip, true, false) as Node3D
				if socket != null:
					DamageSmoke.create(socket, Vector3.ZERO, true)
			mech.walk_speed *= legs_speed_scale
			jump_charge.process_mode = Node.PROCESS_MODE_DISABLED
		"Shield":
			var nodes := weapons.shield_nodes.duplicate()
			weapons.lose_shield()
			_drop(nodes, -mech.global_basis.x)
		"Back L", "Back R":
			var pod := weapons.back_left if key == "Back L" else weapons.back_right
			weapons.lose_back_weapon(pod)
			if pod != null:
				_drop([pod] as Array[Node3D], Vector3.UP - mech.global_basis.z)
		"Core":
			_destroy_mech()


## The whole mech explodes: arms and head fly off, the rest goes dark, input stops.
func _destroy_mech() -> void:
	var world := _world()
	for i in 3:
		var effect := EXPLOSION.instantiate() as Node3D
		world.add_child(effect)
		effect.global_position = mech.global_position + Vector3(randf_range(-2.0, 2.0), 4.0 + i * 2.5, randf_range(-2.0, 2.0))
	if camera_shake != null:
		camera_shake.add_shake(0.8, 1.0)
	if health.is_part_alive("Head"):
		health.remove_part("Head")
		_drop(_nodes("Head"), Vector3.UP * 2.0)
	if health.is_part_alive("Arm L"):
		health.remove_part("Arm L")
		_break_left_arm(-mech.global_basis.x + Vector3.UP)
	if health.is_part_alive("Arm R"):
		health.remove_part("Arm R")
		_break_right_arm(mech.global_basis.x + Vector3.UP)
	for pod in [weapons.back_left, weapons.back_right]:
		weapons.lose_back_weapon(pod)
	DamageSmoke.create(frame, Vector3.UP * 6.0, true)
	mech.is_wrecked = true


## The left arm falls off with its shield.
func _break_left_arm(away: Vector3) -> void:
	var nodes := _nodes("Arm L") + weapons.shield_nodes + _loose_children(["ShoulderL", "ElbowL"])
	if health.is_part_alive("Shield"):
		health.remove_part("Shield")
	weapons.lose_left_arm()
	_drop(nodes, away)
	_stump_smoke("ShoulderL")


## The right arm falls off with its weapon.
func _break_right_arm(away: Vector3) -> void:
	var nodes := _nodes("Arm R") + _loose_children(["ShoulderR", "ElbowR"])
	if weapons.right_weapon != null:
		nodes.append(weapons.right_weapon)
	weapons.lose_right_weapon()
	_drop(nodes, away)
	_stump_smoke("ShoulderR")


func _nodes(key: String) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	nodes.assign(assembler.part_nodes.get(key, []))
	return nodes


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


func _drop(nodes: Array[Node3D], away: Vector3) -> void:
	var unique: Array[Node3D] = []
	for node in nodes:
		if is_instance_valid(node) and not unique.has(node):
			unique.append(node)
	var push := mech.velocity + (away.normalized() + Vector3.UP * 0.8) * drop_push
	Debris.drop(unique, _world(), push)


func _stump_smoke(socket_name: String) -> void:
	var socket := frame.find_child(socket_name, true, false) as Node3D
	if socket != null:
		DamageSmoke.create(socket, Vector3.ZERO, true)


## Where a part's smoke goes: [parent, offset] from its first hitbox.
func _part_place(key: String) -> Array:
	for hitbox in health.hitboxes.get(key, []):
		if is_instance_valid(hitbox) and hitbox.get_child_count() > 0:
			return [hitbox.get_parent(), hitbox.position + (hitbox.get_child(0) as Node3D).position]
	return []


func _world() -> Node:
	return get_tree().current_scene if get_tree().current_scene != null else mech.get_parent()
