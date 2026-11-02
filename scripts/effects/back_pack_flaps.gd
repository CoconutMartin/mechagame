class_name BackPackFlaps
extends Node
## Moving outlet parts on a back pack that open while boosting: louver flaps (Boost Pack, user request 2026-10-31:
## "turn the grilles into flaps that open when boosting and close when not boosting"; nodes OutletFlap<outlet>_<n>)
## and jet nozzle petals (Quad Booster, Jet Pack, user request 2026-10-31: "the nozzles open and close when boosting and
## when not, like in jet fighters"; nodes NozzlePetal<outlet>_<n>). Each part turns about its own X axis (the hinge);
## closed (as built) at rest, open while the mech boosts, rises on the jump jets or hops in a dodge.
## Jump charge (user request 2026-11-02: "petals should also close/open when charging to jump"): while the mech holds
## jump on the ground the petals close down further as the charge builds (the louvers crack open to vent), then they
## snap open at the launch. BackPackMount adds this node when the model has them.

## Flap angle when fully open (degrees; the top edge swings out).
@export var open_angle_deg: float = 90.0
## Nozzle petal angle when fully open (degrees; the tip swings out from the nozzle axis). The petals are built
## tilted in by 22 degrees, so 30 opens the nozzle a little wider than straight.
@export var petal_open_deg: float = 30.0
## Nozzle petal angle at full jump charge (degrees; negative turns the tip in). The petals are built tilted in by 22
## degrees, so -30 closes the nozzle down to 52 degrees in.
@export var petal_charge_deg: float = -30.0
## Louver flap angle at full jump charge, as a fraction of the open angle (the louvers crack open to vent).
@export var flap_charge_fraction: float = 0.3
## Jump charge (fraction of full height) at which the petals are fully closed down.
@export var charge_full: float = 0.6
## How fast the flaps open (fraction of the full swing per second).
@export var open_speed: float = 6.0
## How fast the flaps close (fraction of the full swing per second).
@export var close_speed: float = 3.0
## How fast the parts snap open at a jump launch, and out of the charge pose (fraction of the swing per second).
@export var snap_speed: float = 18.0
## How fast the charge pose follows the charge (fraction of the swing per second).
@export var charge_follow_speed: float = 8.0
## Seconds after the jump release in which an opening counts as the launch snap.
@export var snap_window: float = 0.3

var mech: Mech
## 0 = closed, 1 = fully open (boost, jump jets, dodge hop).
var amount: float = 0.0
## 0 = rest, 1 = closed down for the jump charge.
var squeeze: float = 0.0

var _model: Node3D
var _flaps: Array[Node3D] = []
var _rest: Array[Basis] = []
## Full open angle of each part (radians).
var _angles: Array[float] = []
## Angle of each part at full jump charge (radians).
var _charge_angles: Array[float] = []
var _was_charging: bool = false
var _snap_left: float = 0.0


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
		flaps._add(node as Node3D, deg_to_rad(flaps.open_angle_deg), deg_to_rad(flaps.open_angle_deg * flaps.flap_charge_fraction))
	for node in petal_nodes:
		flaps._add(node as Node3D, deg_to_rad(flaps.petal_open_deg), deg_to_rad(flaps.petal_charge_deg))
	target.add_child(flaps)
	return flaps


func _add(node: Node3D, angle: float, charge_angle: float) -> void:
	_flaps.append(node)
	_rest.append(node.basis)
	_angles.append(angle)
	_charge_angles.append(charge_angle)


func _physics_process(delta: float) -> void:
	var visible_pack := is_instance_valid(_model) and _model.is_visible_in_tree() and not mech.is_wrecked
	var thrusting := visible_pack and BoosterFlames.target_thrust(mech, mech.dodge, 1.0, 1.0) > 0.0
	var charging := visible_pack and not thrusting and mech.jump_charge != null and mech.jump_charge.is_charging
	if _was_charging and not charging:
		_snap_left = snap_window
	_was_charging = charging
	_snap_left = maxf(_snap_left - delta, 0.0)
	var squeeze_target := 0.0
	if charging:
		squeeze_target = clampf(mech.jump_charge.charge / maxf(charge_full, 0.01), 0.0, 1.0)
	# Out of the charge pose in one jump (the launch) or softly (a canceled jump).
	var launching := _snap_left > 0.0
	if squeeze_target > squeeze:
		squeeze = move_toward(squeeze, squeeze_target, charge_follow_speed * delta)
	else:
		squeeze = move_toward(squeeze, squeeze_target, (snap_speed if launching else charge_follow_speed) * delta)
	var target := 1.0 if thrusting else 0.0
	var speed := close_speed
	if target > amount:
		speed = snap_speed if launching else open_speed
	amount = move_toward(amount, target, speed * delta)
	_apply()


func _apply() -> void:
	# Ease in and out, so the flaps start and stop softly.
	var open := smoothstep(0.0, 1.0, amount)
	var closed := smoothstep(0.0, 1.0, squeeze) * (1.0 - open)
	for i in _flaps.size():
		if is_instance_valid(_flaps[i]):
			_flaps[i].basis = _rest[i] * Basis(Vector3.RIGHT, _angles[i] * open + _charge_angles[i] * closed)


## Parts in use (for tests).
func get_flaps() -> Array[Node3D]:
	return _flaps


## Full open angle of part i (degrees, for tests).
func get_open_angle(i: int) -> float:
	return rad_to_deg(_angles[i])


## Angle of part i at full jump charge (degrees, for tests).
func get_charge_angle(i: int) -> float:
	return rad_to_deg(_charge_angles[i])
