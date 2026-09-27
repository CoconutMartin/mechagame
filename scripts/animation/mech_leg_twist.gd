class_name MechLegTwist
extends Node
## Turns the legs and pelvis toward the move direction, while the upper body faces the aim.
## Strafing turns the legs to the side. Walking backward keeps the legs forward and reverses the step.

@export var mech: Mech
## Pelvis and hips. Rotates around Y.
@export var lower_body: Node3D
## Largest leg twist away from the upper body, in degrees.
@export var max_twist_deg: float = 75.0
## Twist speed in degrees per second.
@export var twist_speed_deg: float = 240.0
## Below this speed (m/s) the legs keep their current twist.
@export var min_speed: float = 1.0

## True when the legs step backward. MechLegSwing reads it.
var moving_backward: bool = false


func _physics_process(delta: float) -> void:
	# Stopped: the legs keep their last twist (no reset).
	var target := lower_body.rotation.y
	var local_velocity := mech.global_basis.inverse() * mech.velocity
	local_velocity.y = 0.0
	moving_backward = false
	if local_velocity.length() > min_speed:
		# Yaw of the move direction, relative to the body front (-Z).
		var angle := atan2(-local_velocity.x, -local_velocity.z)
		if absf(angle) > deg_to_rad(100.0):
			# Mostly backward: face the legs forward and step in reverse.
			angle -= signf(angle) * PI
			moving_backward = true
		var limit := deg_to_rad(max_twist_deg)
		target = clampf(angle, -limit, limit)
	lower_body.rotation.y = move_toward(lower_body.rotation.y, target, deg_to_rad(twist_speed_deg) * delta)
