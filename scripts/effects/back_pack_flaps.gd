class_name BackPackFlaps
extends Node
## Louver flaps on a back pack's outlets (Boost Pack, user request 2026-10-31: "turn the grilles into flaps that
## open when boosting and close when not boosting"). The pack model has OutletFlap<outlet>_<n> nodes: each turns
## about its own X axis (the hinge). Closed (0) they cover the grille; while the mech boosts they turn open.
## BackPackMount adds this node when the model has OutletFlap nodes.

## Flap angle when fully open (degrees; the top edge swings out).
@export var open_angle_deg: float = 65.0
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


## Adds the flaps for a pack model (null when the model has no OutletFlap nodes).
static func attach(target: Mech, pack_model: Node3D) -> BackPackFlaps:
	if target == null or pack_model == null:
		return null
	var found := pack_model.find_children("OutletFlap*", "Node3D", true, false)
	if found.is_empty():
		return null
	var flaps := BackPackFlaps.new()
	flaps.name = "BackPackFlaps"
	flaps.mech = target
	flaps._model = pack_model
	for node in found:
		flaps._flaps.append(node as Node3D)
		flaps._rest.append((node as Node3D).basis)
	target.add_child(flaps)
	return flaps


func _physics_process(delta: float) -> void:
	var on := is_instance_valid(_model) and _model.is_visible_in_tree() and mech.is_boosting and not mech.is_wrecked
	var target := 1.0 if on else 0.0
	amount = move_toward(amount, target, (open_speed if target > amount else close_speed) * delta)
	_apply()


func _apply() -> void:
	# Ease in and out, so the flaps start and stop softly.
	var angle := deg_to_rad(open_angle_deg) * smoothstep(0.0, 1.0, amount)
	for i in _flaps.size():
		if is_instance_valid(_flaps[i]):
			_flaps[i].basis = _rest[i] * Basis(Vector3.RIGHT, angle)


## Flaps in use (for tests).
func get_flaps() -> Array[Node3D]:
	return _flaps
