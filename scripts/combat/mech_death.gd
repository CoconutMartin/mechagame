class_name MechDeath
extends Node
## How the mech dies (MechHealth.destroyed). The mech stops (Mech.is_wrecked), the normal
## animation stops, and the mech goes to the power down pose (PowerDownPose). By cause:
##   Head: power down, standing.
##   Center torso: side torsos at or below half HP explode with it.
##     None: power down, standing.
##     Both: the whole upper body is blown off; the legs stay standing, powered down.
##     One: that side and the center explode, then the mech takes two steps toward the side that
##          is left and falls over diagonally to that side.
##   Groin: the upper body comes off the legs, falls, and explodes. The legs stay standing.
##   Both legs: the mech falls forward onto its head and crushes it.

@export var mech: Mech
@export var health: MechHealth
@export var breaker: PartBreaker
@export var weapons: WeaponController
@export var power_down: PowerDownPose
@export var mech_fall: MechFall
## The normal animation nodes (they stop).
@export var animation: Node
@export var camera_shake: CameraShake
@export var torso: Node3D
@export var elbow_right: Node3D

## Side torsos at or below this HP fraction explode with the center torso.
@export_range(0.0, 1.0) var side_explode_below: float = 0.5
## Groin destroyed: the fallen upper body explodes after this many seconds.
@export var upper_explode_delay: float = 1.5
## Push of parts blown off by an explosion, m/s.
@export var blow_push: float = 9.0

var _upper: Debris
var _upper_left: float = 0.0


func _ready() -> void:
	health.destroyed.connect(_on_destroyed)


func _on_destroyed(cause: String) -> void:
	mech.is_wrecked = true
	mech_fall.freeze_animation()
	# The held weapon hangs from the right hand.
	if weapons.right_weapon != null and is_instance_valid(elbow_right):
		weapons.right_weapon.reparent(elbow_right, true)
	if camera_shake != null:
		camera_shake.add_shake(0.6, 0.8)
	match cause:
		"Torso C":
			_center_torso()
		"Groin":
			_groin()
		"Leg L", "Leg R":
			# The fall goes the way the mech moves. In the air it falls after landing: the way it
			# moves, or backwards if it has no speed.
			mech_fall.landed.connect(_crush, CONNECT_ONE_SHOT)
			if mech.is_on_floor():
				mech_fall.fall(Vector3.ZERO, Vector3.ZERO, 0, false)
			else:
				mech_fall.fall_on_landing(true)
	power_down.start()


func _center_torso() -> void:
	var exploding: Array[String] = []
	for side in ["Torso L", "Torso R"]:
		if health.get_fraction(side) <= side_explode_below:
			exploding.append(side)
	if exploding.is_empty():
		breaker.explode_at(breaker.center_of(health.get_nodes("Torso C")), 3.0)
		return
	breaker.blow_away("Torso C")
	_blow_off("Head", Vector3.UP)
	for side in exploding:
		var left := side == "Torso L"
		breaker.blow_away(side)
		var out := -mech.global_basis.x if left else mech.global_basis.x
		_blow_off("Arm L" if left else "Arm R", out + Vector3.UP)
		_blow_off("Back L" if left else "Back R", out + Vector3.UP)
		health.remove_part(side)
	if exploding.size() == 2:
		# The whole upper body is gone. The legs stay.
		for key in ["Shield"]:
			health.remove_part(key)
		torso.visible = false
		return
	# One side is left: two steps toward it, then fall over diagonally to that side.
	var remaining_left := exploding[0] == "Torso R"
	var side_dir := -mech.global_basis.x if remaining_left else mech.global_basis.x
	mech_fall.fall(side_dir - mech.global_basis.z, side_dir)


## The upper body comes off the legs and falls, then explodes.
func _groin() -> void:
	breaker.blow_away("Groin", 0.6)
	for key in ["Head", "Torso C", "Torso L", "Torso R", "Arm L", "Arm R", "Shield", "Back L", "Back R"]:
		health.remove_part(key)
	var push := Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)).normalized()
	_upper = breaker.drop([torso] as Array[Node3D], push)
	if _upper != null:
		_upper.life = 60.0
		_upper_left = upper_explode_delay


func _physics_process(delta: float) -> void:
	if _upper_left <= 0.0:
		return
	_upper_left -= delta
	if _upper_left <= 0.0 and is_instance_valid(_upper):
		var center := _upper.global_position
		for i in 3:
			breaker.explode_at(center + Vector3(randf_range(-2.0, 2.0), randf_range(0.0, 2.0), randf_range(-2.0, 2.0)), 8.0)
		if camera_shake != null:
			camera_shake.add_shake(0.5, 0.6)
		for child in _upper.get_children():
			if child is Node3D and not child is DamageSmoke:
				(child as Node3D).visible = false


## Both legs gone: a fall to the front lands on the head and crushes it; a fall to the back lands
## on the backpack and it explodes.
func _crush() -> void:
	if mech_fall.local_direction.z > 0.3 and health.is_part_alive("Booster"):
		health.break_part("Booster")
		return
	_crush_head()


func _crush_head() -> void:
	var nodes := health.get_nodes("Head")
	if nodes.is_empty() or not is_instance_valid(nodes[0]) or not nodes[0].visible:
		return
	breaker.explode_at(breaker.center_of(nodes), 2.5)
	health.remove_part("Head")
	for node in nodes:
		if is_instance_valid(node):
			node.visible = false
	DamageSmoke.create(torso, Vector3.UP * 3.5, true)


## A part flies off in an explosion (if it is still on).
func _blow_off(key: String, away: Vector3) -> void:
	if not health.is_part_alive(key) and not health.get_nodes(key).any(func(n): return is_instance_valid(n) and mech.is_ancestor_of(n)):
		return
	health.remove_part(key)
	var saved := breaker.drop_push
	breaker.drop_push = blow_push
	match key:
		"Arm L", "Arm R":
			breaker.break_arm(key, away)
		"Back L", "Back R":
			breaker.break_back(key, away)
		_:
			breaker.drop(health.get_nodes(key), away)
	breaker.drop_push = saved
