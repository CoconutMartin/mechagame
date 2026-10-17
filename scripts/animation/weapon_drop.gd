class_name WeaponDrop
extends Node
## A hand weapon that fell out of the mech's hand when it was knocked down face down (user request
## 2026-10-15). It holds the weapon node in the level and moves it along a short arc from the hand to a
## rest place on the ground, turning once in the air and hopping once as it lands. After that it lies
## there until the mech picks it up (WeaponPickup) or the mech is gone. Plain arc, no physics body: the
## rest place is known in advance, so the mech can reach it after the get-up.
## The weapon lies upright with its muzzle in the wanted direction, on the lowest point of its meshes.
## Weapons on the ground (user rules 2026-10-17): they do nothing (the weapon node is disabled) and take no
## damage. A drop with an owner (owner_weapons: the knock-down drop) waits for that mech only; a free drop
## (a Tab drop, a dead mech's weapon, a weapon whose arm broke) can be taken by any mech, and it goes away
## after despawn_time seconds when no mech is near. GroundWeapons keeps the count at a limit.

signal landed

## Gravity of the fall in m/s².
@export var gravity: float = 24.0
## The shortest flight in seconds (a short drop is tossed a little).
@export var min_flight_time: float = 0.7
## Turns of the weapon in the air.
@export var spins: float = 1.0
## Hop after the landing: height in meters and time in seconds.
@export var bounce_height: float = 0.35
@export var bounce_time: float = 0.3
## Ground for the rest height (physics layers: world and buildings).
@export_flags_3d_physics var ground_mask: int = 17
@export_group("Despawn")
## A free weapon goes away after this many seconds with no mech within despawn_distance (meters).
@export var despawn_time: float = 60.0
@export var despawn_distance: float = 30.0
## The weapon shrinks away over this many seconds (user rule 2026-10-17).
@export var fade_time: float = 0.5
@export_group("")

## The dropped weapon (a child of this node while it lies on the ground).
var weapon: MechWeapon
var is_landed: bool = false
## Only this controller may take the weapon (the mech that dropped it face down). Null: any mech may.
## (Not named "owner": that is a Node property.)
var owner_weapons: WeaponController
## The node that is taking the weapon now (WeaponPickup); nobody else takes it meanwhile.
var reserved_by: Node
## Order of creation (GroundWeapons.trim frees the oldest first).
var serial: int = 0

static var _next_serial: int = 0

var _start := Transform3D.IDENTITY
var _land := Transform3D.IDENTITY
var _time: float = 0.0
var _flight: float = 1.0
var _speed_up: float = 0.0
## A move along the ground (a weapon that came to rest out of reach, or in the way): it turns about
## _move_pivot and slides by _move_offset, both smoothly over _move_time seconds.
var _move_from := Transform3D.IDENTITY
var _move_offset := Vector3.ZERO
var _move_yaw: float = 0.0
var _move_pivot := Vector3.ZERO
var _move_time: float = 0.0
var _move_left: float = 0.0
## Despawn: seconds with no mech near, the check timer, and the fade (-1 = not fading).
var _away_time: float = 0.0
var _check_left: float = 0.0
var _mech_is_near: bool = true
var _fade_left: float = -1.0
var _full_scale := Vector3.ONE


## Takes the weapon (it moves under the new node, where it is) and drops it. grip_spot: where its right
## grip should lie (world; y = the floor height if the ground is not found). face: the world direction
## (flat) of the muzzle, or, for a two-hand weapon, of the line from the right grip to the left grip.
## max_count: the most weapons on the ground (the oldest free one goes when there are more).
static func create(weapon_node: MechWeapon, level: Node, grip_spot: Vector3, face: Vector3, two_hand: bool,
		max_count: int = 8) -> WeaponDrop:
	var drop := WeaponDrop.new()
	drop.name = "WeaponDrop"
	level.add_child(drop)
	drop.add_to_group(GroundWeapons.GROUP)
	drop.serial = _next_serial
	_next_serial += 1
	drop.weapon = weapon_node
	drop._plan(grip_spot, face, two_hand)
	weapon_node.reparent(drop, true)
	# Nothing on the ground works: no fire, no pose, no reads of the old mech (BeamRifleWeapon reads it every frame).
	weapon_node.process_mode = Node.PROCESS_MODE_DISABLED
	GroundWeapons.trim(level.get_tree(), max_count, drop)
	return drop


## True when the weapon has landed, still hangs under this node, nobody is taking it, and the controller
## may take it (no owner, or the owner).
func is_pickable_by(controller: WeaponController) -> bool:
	if not is_landed or is_queued_for_deletion() or _fade_left >= 0.0:
		return false
	if not is_instance_valid(weapon) or weapon.get_parent() != self:
		return false
	if is_instance_valid(reserved_by):
		return false
	return owner_weapons == null or owner_weapons == controller


## True when GroundWeapons.trim may free this drop: nobody owns it and nobody is taking it.
func is_free_to_remove() -> bool:
	return owner_weapons == null and not is_instance_valid(reserved_by)


## The grip marker of the weapon (GripRight or GripLeft) in the world, or the weapon place without one.
func get_grip_position(marker_name: StringName) -> Vector3:
	var marker := weapon.get_node_or_null(NodePath(marker_name)) as Node3D if is_instance_valid(weapon) else null
	if marker == null:
		return weapon.global_position if is_instance_valid(weapon) else Vector3.ZERO
	return marker.global_position


## Slides the resting weapon by offset (world) over time seconds.
func slide_by(offset: Vector3, time: float) -> void:
	move_by(offset, 0.0, time)


## Turns the resting weapon about the vertical axis by yaw radians (about its right grip) over time seconds.
func turn_by(yaw: float, time: float) -> void:
	move_by(Vector3.ZERO, yaw, time)


## Turns the resting weapon by yaw radians about pivot (world; Vector3.INF = its right grip), then slides
## it by offset (world), smoothly over time seconds.
func move_by(offset: Vector3, yaw: float, time: float, pivot: Vector3 = Vector3.INF) -> void:
	if not is_instance_valid(weapon):
		return
	_move_from = weapon.global_transform
	_move_offset = offset
	_move_yaw = yaw
	_move_pivot = get_grip_position(&"GripRight") if not pivot.is_finite() else pivot
	_move_time = maxf(time, 0.05)
	_move_left = _move_time
	set_physics_process(true)


func _plan(grip_spot: Vector3, face: Vector3, two_hand: bool) -> void:
	_start = weapon.global_transform
	var to_local := _start.affine_inverse()
	var grip := weapon.get_node_or_null("GripRight") as Node3D
	var grip_local := to_local * grip.global_position if grip != null else Vector3.ZERO
	# The line that points the way: the muzzle, or the right grip to the left grip of a two-hand weapon.
	var reference := Vector3(0.0, 0.0, -1.0)
	if two_hand:
		var left := weapon.get_node_or_null("GripLeftRest") as Node3D
		if left == null:
			left = weapon.get_node_or_null("GripLeft") as Node3D
		if left != null:
			reference = to_local * left.global_position - grip_local
	reference.y = 0.0
	var wanted := Vector3(face.x, 0.0, face.z)
	var yaw := 0.0
	if reference.length_squared() > 0.0001 and wanted.length_squared() > 0.0001:
		yaw = reference.signed_angle_to(wanted, Vector3.UP)
	var basis := Basis(Vector3.UP, yaw)
	# Height: the lowest point of the meshes on the ground.
	var low := 0.0
	var first := true
	for mesh in _meshes(weapon):
		var box := mesh.get_aabb()
		var mesh_to_weapon := to_local * mesh.global_transform
		for corner in 8:
			var point := mesh_to_weapon * box.get_endpoint(corner)
			var y := (basis * point).y
			if first or y < low:
				low = y
				first = false
	var ground := _ground_height(grip_spot)
	var turned_grip := basis * grip_local
	var origin := Vector3(grip_spot.x - turned_grip.x, ground - low + 0.02, grip_spot.z - turned_grip.z)
	_land = Transform3D(basis, origin)
	var drop_height := maxf(_start.origin.y - origin.y, 0.1)
	_flight = maxf(sqrt(2.0 * drop_height / gravity), min_flight_time)
	# Vertical start speed that reaches the ground at the end of the flight.
	_speed_up = ((origin.y - _start.origin.y) + 0.5 * gravity * _flight * _flight) / _flight


func _ground_height(spot: Vector3) -> float:
	var space := weapon.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 6.0, spot + Vector3.DOWN * 30.0, ground_mask)
	var hit := space.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else spot.y


func _physics_process(delta: float) -> void:
	if not is_instance_valid(weapon) or weapon.get_parent() != self:
		queue_free()
		return
	if is_landed:
		_update_move(delta)
		_update_despawn(delta)
		return
	_time += delta
	if _time < _flight:
		var s := _time / _flight
		var origin := _start.origin.lerp(_land.origin, s)
		origin.y = _start.origin.y + _speed_up * _time - 0.5 * gravity * _time * _time
		var turn := _start.basis.get_rotation_quaternion().slerp(_land.basis.get_rotation_quaternion(), smoothstep(0.0, 1.0, s))
		turn = turn * Quaternion(Vector3.RIGHT, TAU * spins * s)
		weapon.global_transform = Transform3D(Basis(turn), origin)
		return
	var u := clampf((_time - _flight) / maxf(bounce_time, 0.01), 0.0, 1.0)
	weapon.global_transform = Transform3D(_land.basis, _land.origin + Vector3.UP * bounce_height * 4.0 * u * (1.0 - u))
	if u >= 1.0:
		is_landed = true
		landed.emit()


func _update_move(delta: float) -> void:
	if _move_left <= 0.0:
		return
	_move_left = maxf(_move_left - delta, 0.0)
	var s := smoothstep(0.0, 1.0, 1.0 - _move_left / _move_time)
	var turn := Transform3D(Basis(Vector3.UP, _move_yaw * s), Vector3.ZERO)
	var moved := Transform3D(Basis.IDENTITY, _move_pivot) * turn * Transform3D(Basis.IDENTITY, -_move_pivot) * _move_from
	moved.origin += _move_offset * s
	weapon.global_transform = moved


## A free weapon goes after despawn_time seconds with no mech near (it shrinks away first). An owned or
## reserved weapon stays.
func _update_despawn(delta: float) -> void:
	if _fade_left >= 0.0:
		_fade_left -= delta
		if _fade_left <= 0.0:
			queue_free()
			return
		weapon.scale = _full_scale * maxf(_fade_left / maxf(fade_time, 0.01), 0.001)
		return
	if owner_weapons != null or is_instance_valid(reserved_by):
		_away_time = 0.0
		return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = 0.5
		_mech_is_near = GroundWeapons.mech_near(get_tree(), weapon.global_position, despawn_distance)
	_away_time = 0.0 if _mech_is_near else _away_time + delta
	if _away_time >= despawn_time:
		_fade_left = maxf(fade_time, 0.01)
		_full_scale = weapon.scale


## Visible meshes of the weapon (effects that cast no shadow are left out).
static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).visible and (root as MeshInstance3D).cast_shadow != 0:
		found.append(root as MeshInstance3D)
	for child in root.get_children():
		found.append_array(_meshes(child))
	return found
