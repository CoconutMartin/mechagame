class_name BoosterFlames
extends Node
## Fire from the backpack thrusters while boosting, air boosting, rising on the jump jets,
## and during a dodge hop. Each flame is a Node3D that points down its own -Y axis.
## This script scales the flames by the thrust amount, adds flicker, and sets the glow light.

@export var mech: Mech
@export var dodge: MechDodge
## Flame nodes. Scale 1 on Y = full flame length.
@export var flames: Array[Node3D] = []
## Optional light at the thrusters.
@export var light: OmniLight3D
## Light energy at full thrust.
@export var light_energy: float = 3.0
## Flame length while boosting on the ground (0 to 1).
@export var ground_boost_thrust: float = 0.8
## Flame length in the air (air boost, jump jets rising, dodge hop).
@export var air_thrust: float = 1.0
## Thrust at the start of a dodge hop (a short burst).
@export var dodge_burst: float = 1.4
## How fast the flame grows (1 / seconds).
@export var ignite_speed: float = 12.0
## How fast the flame dies down (1 / seconds).
@export var fade_speed: float = 6.0
## Random change of the flame length each frame (0 to 1).
@export var flicker: float = 0.18

var thrust: float = 0.0


func _physics_process(delta: float) -> void:
	var target := 0.0
	var airborne := not mech.is_on_floor()
	if mech.is_boosting:
		target = air_thrust if airborne else ground_boost_thrust
	elif airborne and mech.velocity.y > 0.0:
		target = air_thrust  # Jump jets or dodge hop going up.
	if dodge != null and dodge.is_dodging:
		target = maxf(target, air_thrust)
	var speed := ignite_speed if target > thrust else fade_speed
	thrust = move_toward(thrust, target, speed * delta)


## Starts a short burst, for example at the dodge start.
func burst() -> void:
	thrust = maxf(thrust, dodge_burst)


func _ready() -> void:
	if dodge != null:
		dodge.dodge_started.connect(burst)
	_process(0.0)


func _process(_delta: float) -> void:
	for flame in flames:
		var length := thrust * (1.0 + randf_range(-flicker, flicker))
		flame.visible = length > 0.02
		var width := 0.6 + 0.4 * minf(thrust, 1.0)
		flame.scale = Vector3(width, maxf(length, 0.001), width)
	if light != null:
		light.visible = thrust > 0.02
		light.light_energy = light_energy * thrust * randf_range(0.85, 1.15)
