class_name MechLegSwing
extends Node
## Placeholder walk animation for box mechs: hip swing, knee bend, body bob, and sway.
## Phase 8 replaces it with full animation on rigged models.
## It reads the walk cycle from MechFootsteps, so each footstep shake matches a foot strike.

@export var mech: Mech
@export var footsteps: MechFootsteps
## Moves up and down with the walk. Hips must be children of this node.
@export var upper_body: Node3D
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D

@export_group("Walk")
## Largest hip swing forward and back, in degrees, at full walk speed.
@export var hip_swing_deg: float = 22.0
## Largest knee bend of the leg that swings forward, in degrees.
@export var knee_bend_deg: float = 30.0
## Body drop at each foot strike, in meters.
@export var bob_height: float = 0.3
## Body roll toward the planted leg, in degrees.
@export var sway_deg: float = 1.5

@export_group("Boost and Air")
## Legs trail back this much while boosting, in degrees.
@export var boost_trail_deg: float = 12.0
## Knee bend in the air, in degrees.
@export var air_knee_deg: float = 15.0
## How fast the pose blends between walk, boost, and air.
@export var blend_speed: float = 6.0

var _walk_amount: float = 0.0
var _trail: float = 0.0
var _air_knee: float = 0.0
var _upper_rest_y: float = 0.0


func _ready() -> void:
	_upper_rest_y = upper_body.position.y


# Runs in physics frames so it stays smooth with physics interpolation.
func _physics_process(delta: float) -> void:
	var on_floor := mech.is_on_floor()
	var walking := on_floor and not mech.is_boosting
	var speed_ratio := clampf(mech.get_horizontal_speed() / mech.walk_speed, 0.0, 1.0)
	var blend := 1.0 - exp(-blend_speed * delta)
	_walk_amount = lerpf(_walk_amount, speed_ratio if walking else 0.0, blend)
	_trail = lerpf(_trail, 1.0 if mech.is_boosting else 0.0, blend)
	_air_knee = lerpf(_air_knee, 0.0 if on_floor else 1.0, blend)

	var phase := footsteps.get_cycle_phase()
	var hip := deg_to_rad(hip_swing_deg) * _walk_amount * cos(phase)
	var trail := -deg_to_rad(boost_trail_deg) * _trail
	# The leg that moves forward lifts its foot by bending the knee.
	var knee := deg_to_rad(knee_bend_deg) * _walk_amount
	var air := deg_to_rad(air_knee_deg) * _air_knee

	hip_left.rotation.x = hip + trail + air * 0.5
	hip_right.rotation.x = -hip + trail + air * 0.5
	knee_left.rotation.x = -knee * maxf(0.0, -sin(phase)) - air
	knee_right.rotation.x = -knee * maxf(0.0, sin(phase)) - air

	# Lowest at foot strike (phase = 0, PI), highest between steps.
	upper_body.position.y = _upper_rest_y - bob_height * _walk_amount * (cos(2.0 * phase) + 1.0) * 0.5
	upper_body.rotation.z = deg_to_rad(sway_deg) * _walk_amount * cos(phase)
