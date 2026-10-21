class_name CollapseMass
extends Node3D
## A building part that lost its support falls as one mass (phase 5c, user choice 2026-10-19): the
## chunks above a failed floor (or any large group that lost its path to the ground) are drawn as one
## body that tips over its edge on the damaged side and sinks, then breaks on the ground: rubble, a big
## dust cloud (CollapseDust) and a ground shake for the player's camera (stronger when closer).
## It has no collision and does no damage (user choice 2026-10-19: falling debris stays harmless).
## BuildingDamage makes it; the chunks are already gone from the building when it starts.

## Tip speed up (radians per second squared) for a mass 12 m tall; it grows as the mass leans
## (x (0.35 + 1.5 sin angle), like a real topple) and is less for a taller mass (x 12 m / its height).
@export var tip_acceleration: float = 1.6
@export var max_tip_speed: float = 1.6
## How fast the mass sinks while it tips (part of gravity).
@export var sink_gravity: float = 0.45
## It breaks when its middle is this part of its height above the ground, or at this tip (radians).
@export var break_height: float = 0.12
@export var max_tip: float = 1.3
## Rubble pieces at the impact (most).
@export var impact_rubble: int = 30
## Rubble pieces made per physics frame after the impact (all at once cost 50 ms).
@export var rubble_per_frame: int = 6
## Camera shake: trauma at the start and at the impact for a player this close (m), less further out.
@export var shake_radius: float = 90.0
@export var start_trauma: float = 0.25
@export var impact_trauma: float = 0.9
@export var impact_kick: float = 1.0

## Set by BuildingDamage before it enters the tree.
var building: BuildingDamage
## Boxes in world space: [Transform3D (box size in the basis), Material].
var boxes: Array = []
## Unit vector (world, level) toward the side it tips to.
var tip_direction: Vector3 = Vector3.FORWARD
## Ground height under it (m).
var ground_y: float = 0.0
var debris_color: Color = Color(0.6, 0.6, 0.58)

var _angle: float = 0.0
var _tip_speed: float = 0.0
var _sink_speed: float = 0.0
var _axis: Vector3 = Vector3.RIGHT
var _corners: PackedVector3Array = []
var _bounds: AABB
var _pivot_start: Vector3
var _age: float = 0.0


func _ready() -> void:
	# The pivot: the bottom edge on the side that still stands (away from the tip side); the tip side
	# drops first and the mass turns over this edge.
	_bounds = AABB()
	var first := true
	for entry: Array in boxes:
		var box := _box_aabb(entry[0] as Transform3D)
		_bounds = box if first else _bounds.merge(box)
		first = false
	var center := _bounds.get_center()
	var reach := absf(tip_direction.x) * _bounds.size.x * 0.5 + absf(tip_direction.z) * _bounds.size.z * 0.5
	global_position = Vector3(center.x, _bounds.position.y, center.z) - tip_direction * reach
	_pivot_start = global_position
	_axis = Vector3.UP.cross(tip_direction).normalized()
	# The look: one MultiMesh per material, boxes relative to the pivot.
	var by_material := {}
	for entry: Array in boxes:
		var list: Array = by_material.get_or_add(entry[1], [])
		var place := entry[0] as Transform3D
		list.append(Transform3D(place.basis, place.origin - global_position))
	var unit := BoxMesh.new()
	for material: Variant in by_material:
		var list: Array = by_material[material]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = unit
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var view := MultiMeshInstance3D.new()
		view.multimesh = mm
		view.material_override = material as Material
		add_child(view)
	for i in 8:
		_corners.append(_bounds.get_endpoint(i) - global_position)
	_shake(start_trauma, 0.3)


func _physics_process(delta: float) -> void:
	_age += delta
	var lean := 0.35 + 1.5 * sin(_angle)
	var tall := 12.0 / maxf(_bounds.size.y, 12.0)
	_tip_speed = minf(_tip_speed + tip_acceleration * tall * lean * delta, max_tip_speed)
	_angle += _tip_speed * delta
	_sink_speed += ProjectSettings.get_setting("physics/3d/default_gravity") * sink_gravity * delta
	global_position.y -= _sink_speed * delta
	global_basis = Basis(_axis, _angle)
	# It breaks when its middle comes down near the ground or it has tipped far over (it has no
	# collision; the part under the ground is hidden by the dust).
	var middle := (global_transform * (_bounds.get_center() - _pivot_start)).y
	if middle <= ground_y + maxf(_bounds.size.y * break_height, 1.5) or _angle >= max_tip or _age > 6.0:
		_impact()


## On the ground: the mass is hidden, the dust cloud and the shake start, and the rubble comes a few
## pieces per frame over the mass's footprint; then the mass goes.
func _impact() -> void:
	set_physics_process(false)
	for child in get_children():
		(child as Node3D).visible = false
	var world := get_parent()
	var area := AABB()
	var first := true
	for corner in _corners:
		var point := global_transform * corner
		area = AABB(point, Vector3.ZERO) if first else area.expand(point)
		first = false
	var footprint := Vector2(maxf(area.size.x, 6.0), maxf(area.size.z, 6.0))
	var center := Vector3(area.get_center().x, ground_y, area.get_center().z)
	CollapseDust.create(world, center + Vector3.UP * 2.0, footprint)
	_shake(impact_trauma, impact_kick)
	var left := mini(impact_rubble, maxi(boxes.size(), 8))
	while left > 0:
		for i in mini(rubble_per_frame, left):
			var entry: Array = boxes[randi() % boxes.size()]
			var size := (entry[0] as Transform3D).basis.get_scale()
			var side := clampf(minf(size.x, minf(size.y, size.z)) * randf_range(0.4, 0.9), 0.4, 1.6)
			var point := center + Vector3(randf_range(-0.5, 0.5) * footprint.x, randf_range(0.5, 3.0),
					randf_range(-0.5, 0.5) * footprint.y)
			var away := (point - center).normalized() * randf_range(3.0, 8.0) + Vector3.UP * randf_range(2.0, 5.0)
			Rubble.spawn(world, point, Vector3(side, side * randf_range(0.5, 1.0), side * randf_range(0.6, 1.2)),
					debris_color, away, entry[1] as Material)
		left -= rubble_per_frame
		await get_tree().physics_frame
	queue_free()


## Shakes the player's camera, less with distance.
func _shake(trauma: float, kick: float) -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var mech := node as Node3D
		if mech == null:
			continue
		var near := 1.0 - clampf(mech.global_position.distance_to(global_position) / shake_radius, 0.0, 1.0)
		if near <= 0.0:
			continue
		var shake := mech.find_child("Camera", true, false) as CameraShake
		if shake != null:
			shake.add_shake(trauma * near, kick * near)


static func _box_aabb(place: Transform3D) -> AABB:
	var size := place.basis.get_scale()
	return AABB(place.origin - size * 0.5, size)
