class_name BrakeThrusters
extends Node
## Two small thrusters at the hips fire while the mech brakes in a skid after a dodge hop.
## They act as stabilizers and brakes: the fire points the way the mech slides (it pushes back
## against the momentum). Each flame is a Node3D that points down its own -Y axis.

@export var mech: Mech
@export var flames: Array[Node3D] = []
## Flame length at full thrust (scale on Y).
@export var thrust: float = 1.0
## Flame tilt down, in degrees, so the fire does not hit the legs.
@export var tilt_down_deg: float = 20.0
## How fast the flame grows (1 / seconds).
@export var ignite_speed: float = 20.0
## How fast the flame dies down (1 / seconds). Slow, so the short skid still shows the fire.
@export var fade_speed: float = 2.5
## Random change of the flame length each frame (0 to 1).
@export var flicker: float = 0.25

var _amount: float = 0.0
var _direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	if flames.is_empty():
		flames = GroupNodes.find(mech, &"brake_flame")  # Flames from the leg part model.


func _physics_process(delta: float) -> void:
	var target := thrust if mech.is_brake_skidding else 0.0
	_amount = move_toward(_amount, target, (ignite_speed if target > _amount else fade_speed) * delta)
	var velocity := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	if velocity.length() > 0.5:
		_direction = velocity.normalized()


func _process(_delta: float) -> void:
	# Flame -Y points along the slide, tilted a little down.
	var along := (_direction + Vector3.DOWN * tan(deg_to_rad(tilt_down_deg))).normalized()
	var y := -along
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	for flame in flames:
		var length := _amount * (1.0 + randf_range(-flicker, flicker))
		flame.visible = length > 0.02
		flame.global_basis = Basis(x, y * maxf(length, 0.001), z)
