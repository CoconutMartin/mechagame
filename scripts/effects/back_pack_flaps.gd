class_name BackPackFlaps
extends Node
## Moving outlet parts on a back pack that open while boosting: louver flaps (Boost Pack, user request 2026-10-31:
## "turn the grilles into flaps that open when boosting and close when not boosting"; nodes OutletFlap<outlet>_<n>)
## and jet nozzle petals (Quad Booster, user request 2026-10-31: "the nozzles open and close when boosting and when
## not, like in jet fighters"; nodes NozzlePetal<outlet>_<n>). Each part turns about its own X axis (the hinge);
## closed (as built) at rest, open while the mech boosts. BackPackMount adds this node when the model has them.

## Flap angle when fully open (degrees; the top edge swings out).
@export var open_angle_deg: float = 90.0
## Nozzle petal angle when fully open (degrees; the tip swings out from the nozzle axis). The petals are built
## tilted in by 22 degrees, so 30 opens the nozzle a little wider than straight.
@export var petal_open_deg: float = 30.0
## How fast the flaps open (fraction of the full swing per second).
@export var open_speed: float = 6.0
## How fast the flaps close (fraction of the full swing per second).
@export var close_speed: float = 3.0

var mech: Mech
## 0 = closed, 1 = fully open.
var amount: float = 0.0

var _model: Node3D
var _flaps: Array[Node3D] = []
var _rest: Array[Basis] = []
## Full open angle of each part (radians).
var _angles: Array[float] = []


## Adds the flaps for a pack model (null when the model has no OutletFlap or NozzlePetal nodes).
static func attach(target: Mech, pack_model: Node3D) -> BackPackFlaps:
	if target == null or pack_model == null:
		return null
	var flap_nodes := pack_model.find_children("OutletFlap*", "Node3D", true, false)
	var petal_nodes := pack_model.find_children("NozzlePetal*", "Node3D", true, false)
	if flap_nodes.is_empty() and petal_nodes.is_empty():
		return null
	var flaps := BackPackFlaps.new()
	flaps.name = "BackPackFlaps"
	flaps.mech = target
	flaps._model = pack_model
	for node in flap_nodes:
		flaps._add(node as Node3D, deg_to_rad(flaps.open_angle_deg))
	for node in petal_nodes:
		flaps._add(node as Node3D, deg_to_rad(flaps.petal_open_deg))
	target.add_child(flaps)
	return flaps


func _add(node: Node3D, angle: float) -> void:
	_flaps.append(node)
	_rest.append(node.basis)
	_angles.append(angle)


func _physics_process(delta: float) -> void:
	var on := is_instance_valid(_model) and _model.is_visible_in_tree() and mech.is_boosting and not mech.is_wrecked
	var target := 1.0 if on else 0.0
	amount = move_toward(amount, target, (open_speed if target > amount else close_speed) * delta)
	_apply()


func _apply() -> void:
	# Ease in and out, so the flaps start and stop softly.
	var t := smoothstep(0.0, 1.0, amount)
	for i in _flaps.size():
		if is_instance_valid(_flaps[i]):
			_flaps[i].basis = _rest[i] * Basis(Vector3.RIGHT, _angles[i] * t)


## Parts in use (for tests).
func get_flaps() -> Array[Node3D]:
	return _flaps


## Full open angle of part i (degrees, for tests).
func get_open_angle(i: int) -> float:
	return rad_to_deg(_angles[i])
