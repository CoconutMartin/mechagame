class_name CollapseMass
extends Node3D
## A building part that lost its support sags and leans as one mass, then stays (phase 5c, user
## choices 2026-10-19 and 2026-10-21: "no need to make the buildings disintegrate", the collapse stops
## part way and the leaning part stays breakable like any building). The loose chunks become children of
## this node (their collision moves with it) and their boxes are drawn by its own MultiMeshes (one per
## building material slot). It turns over the bottom edge on the side that still stands, so the side of
## the last break drops first, like a topple: the tip speeds up as it leans and is slower for a taller
## mass; it sinks into the ground as it goes. It stops when its middle is down to settle_height of its
## height: a big dust cloud (CollapseDust) and a ground shake for the player's camera (stronger when
## closer). From then on its chunks are normal building chunks again (BuildingDamage: they stand on the
## ground; hits crack, scorch and break them). No damage to mechs (user choice 2026-10-19).

## Tip speed up (radians per second squared) for a mass 12 m tall; it grows as the mass leans
## (x (0.35 + 1.5 sin angle), like a real topple) and is less for a taller mass (x 12 m / its height).
@export var tip_acceleration: float = 1.6
@export var max_tip_speed: float = 1.6
## How fast the mass sinks while it tips (part of gravity).
@export var sink_gravity: float = 0.45
## It stops when its middle is this part of its height above the ground (user picks 2026-10-21: the
## office at its 1.25 s pose, the tower at its 2.25 s pose), at the latest at max_tip (radians) or max_time.
@export var settle_height: float = 0.16
@export var max_tip: float = 0.7
@export var max_time: float = 4.0
## Camera shake: trauma at the start and when it stops, for a player this close (m), less further out.
@export var shake_radius: float = 90.0
@export var start_trauma: float = 0.25
@export var settle_trauma: float = 0.9
@export var settle_kick: float = 1.0

## Set by BuildingDamage before it enters the tree.
var building: BuildingDamage
## Bounds of the mass (world, at the start) and the unit vector (world, level) toward the side it tips to.
var bounds: AABB
var tip_direction: Vector3 = Vector3.FORWARD
## Ground height under it (m).
var ground_y: float = 0.0
## Its MultiMeshes, by building material slot (null where it has no box of that slot).
var multimeshes: Array[MultiMesh] = []
## True once it has stopped.
var settled: bool = false

var _angle: float = 0.0
var _tip_speed: float = 0.0
var _sink_speed: float = 0.0
var _axis: Vector3 = Vector3.RIGHT
var _pivot_start: Vector3
var _middle_local: Vector3
var _age: float = 0.0


## The pivot for these bounds and tip side: the bottom edge on the side that still stands.
static func pivot_of(area: AABB, toward: Vector3) -> Vector3:
	var center := area.get_center()
	var reach := absf(toward.x) * area.size.x * 0.5 + absf(toward.z) * area.size.z * 0.5
	return Vector3(center.x, area.position.y, center.z) - toward * reach


## Makes the look: one MultiMesh per building material slot, filled by BuildingDamage (add_piece).
func make_look(slots: int, materials: Array[Material]) -> void:
	var unit := BoxMesh.new()
	multimeshes.resize(slots)
	for slot in slots:
		if materials[slot] == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = unit
		multimeshes[slot] = mm
		var view := MultiMeshInstance3D.new()
		view.name = "Look_%d" % slot
		view.multimesh = mm
		view.material_override = materials[slot]
		view.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		add_child(view)


func _ready() -> void:
	_pivot_start = global_position
	_middle_local = bounds.get_center() - global_position
	_axis = Vector3.UP.cross(tip_direction).normalized()
	_shake(start_trauma, 0.3)


func _physics_process(delta: float) -> void:
	if settled:
		return
	_age += delta
	var lean := 0.35 + 1.5 * sin(_angle)
	var tall := 12.0 / maxf(bounds.size.y, 12.0)
	_tip_speed = minf(_tip_speed + tip_acceleration * tall * lean * delta, max_tip_speed)
	_angle += _tip_speed * delta
	_sink_speed += ProjectSettings.get_setting("physics/3d/default_gravity") * sink_gravity * delta
	global_position.y -= _sink_speed * delta
	global_basis = Basis(_axis, _angle)
	var middle := (global_transform * _middle_local).y
	if middle <= ground_y + bounds.size.y * settle_height or _angle >= max_tip or _age >= max_time:
		_settle()


## It stops: the dust cloud and the shake. Its chunks stand on the ground for good (BuildingDamage made
## them grounded when the mass started).
func _settle() -> void:
	settled = true
	set_physics_process(false)
	var center := Vector3(bounds.get_center().x, ground_y, bounds.get_center().z) + tip_direction * bounds.size.y * 0.3
	CollapseDust.create(get_parent(), center + Vector3.UP * 2.0, Vector2(maxf(bounds.size.x, 8.0), maxf(bounds.size.z, 8.0)))
	_shake(settle_trauma, settle_kick)


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
