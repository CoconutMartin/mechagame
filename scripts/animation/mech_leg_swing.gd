class_name MechLegSwing
extends Node
## Placeholder walk animation for box mechs: hip swing, knee bend, body bob, and sway.
## Phase 8 replaces it with full animation on rigged models.
## It reads the walk cycle from MechFootsteps, so each footstep shake matches a foot strike.

@export var mech: Mech
@export var footsteps: MechFootsteps
@export var leg_twist: MechLegTwist
@export var landing_recovery: MechLandingRecovery
@export var jump_charge: MechJumpCharge
@export var kneel: MechKneel
## Moves up and down with the walk. The hips must be inside this node.
@export var upper_body: Node3D
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D

@export_group("Walk")
## Largest hip swing forward and back, in degrees, at full walk speed.
@export var hip_swing_deg: float = 28.0
## Largest knee bend of the leg that swings forward, in degrees.
@export var knee_bend_deg: float = 30.0
## Body drop at each foot strike, in meters.
@export var bob_height: float = 0.3
## Body roll toward the planted leg, in degrees.
@export var sway_deg: float = 1.5

@export_group("Landing")
## Crouch after a short landing (near 0 m fall), in degrees of hip bend. Knees bend twice as much.
@export var landing_crouch_min_deg: float = 8.0
## Crouch after a fall from landing_crouch_full_height or higher, in degrees of hip bend.
@export var landing_crouch_max_deg: float = 40.0
## Fall height (meters) that gives the deepest landing crouch.
@export var landing_crouch_full_height: float = 9.0
## Crouch while boosting on the ground, in degrees of hip bend. Knees bend twice as much
## (20 = knee bent 40 degrees, an inside knee angle of 140 degrees).
@export var boost_crouch_deg: float = 20.0

@export_group("Kneel")
## Left (front) leg: thigh forward, shin straight down to the foot.
@export var kneel_front_hip_deg: float = 70.0
@export var kneel_front_knee_deg: float = 70.0
## Right (back) leg: thigh down, shin back along the ground, knee on the ground.
@export var kneel_back_hip_deg: float = -5.0
@export var kneel_back_knee_deg: float = 90.0
## Body drop when fully down, in meters. Puts the right knee on the ground.
@export var kneel_drop: float = 1.74
## Crouch at full jump charge, in degrees of hip bend.
@export var charge_crouch_deg: float = 30.0
## Hip to foot length, in meters. Used to keep the feet on the ground in a crouch.
@export var leg_length: float = 5.2

@export_group("Boost and Air")
## Legs trail back this much while boosting, in degrees.
@export var boost_trail_deg: float = 12.0
## Knee bend in the air, in degrees.
@export var air_knee_deg: float = 15.0
## How fast the pose blends between walk, boost, and air.
@export var blend_speed: float = 6.0

var _walk_amount: float = 0.0
var _trail: float = 0.0
var _boost_crouch: float = 0.0
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
	_boost_crouch = lerpf(_boost_crouch, 1.0 if mech.is_boosting and on_floor else 0.0, blend)
	_air_knee = lerpf(_air_knee, 0.0 if on_floor else 1.0, blend)

	var phase := footsteps.get_cycle_phase()
	# Walking backward: the lifted leg moves back, so the knee bend flips.
	var lift := sin(phase) * (-1.0 if leg_twist.moving_backward else 1.0)
	var hip := deg_to_rad(hip_swing_deg) * _walk_amount * cos(phase)
	# Legs trail behind the move direction. Backward, the legs face forward, so the trail flips.
	var trail := -deg_to_rad(boost_trail_deg) * _trail * (-1.0 if leg_twist.moving_backward else 1.0)
	# The leg that moves forward lifts its foot by bending the knee.
	var knee := deg_to_rad(knee_bend_deg) * _walk_amount
	var air := deg_to_rad(air_knee_deg) * _air_knee
	# Crouch just after landing, deeper for higher falls, then the mech stands up.
	var fall_ratio := clampf(landing_recovery.fall_height / landing_crouch_full_height, 0.0, 1.0)
	var landing_depth := deg_to_rad(lerpf(landing_crouch_min_deg, landing_crouch_max_deg, fall_ratio))
	var landing_crouch := landing_depth * sin(landing_recovery.get_fraction() * PI * 0.5)
	# The mech crouches deeper as the jump jets charge.
	var charge_crouch := deg_to_rad(charge_crouch_deg) * jump_charge.charge
	# Low stance while boosting on the ground.
	var boost_crouch := deg_to_rad(boost_crouch_deg) * _boost_crouch
	var crouch := maxf(maxf(landing_crouch, charge_crouch), boost_crouch)

	hip_left.rotation.x = hip + trail + air * 0.5 + crouch
	hip_right.rotation.x = -hip + trail + air * 0.5 + crouch
	knee_left.rotation.x = -knee * maxf(0.0, -lift) - air - crouch * 2.0
	knee_right.rotation.x = -knee * maxf(0.0, lift) - air - crouch * 2.0

	# Lowest at foot strike (phase = 0, PI), highest between steps.
	var bob := bob_height * _walk_amount * (cos(2.0 * phase) + 1.0) * 0.5
	# A crouch shortens the legs. Lower the body by the same amount so the feet stay down.
	var crouch_drop := leg_length * (1.0 - cos(crouch))
	upper_body.position.y = _upper_rest_y - bob - crouch_drop

	# Kneel: blend both legs and the body height to the kneel pose.
	var k := smoothstep(0.0, 1.0, kneel.amount)
	if k > 0.0:
		hip_left.rotation.x = lerpf(hip_left.rotation.x, deg_to_rad(kneel_front_hip_deg), k)
		knee_left.rotation.x = lerpf(knee_left.rotation.x, -deg_to_rad(kneel_front_knee_deg), k)
		hip_right.rotation.x = lerpf(hip_right.rotation.x, deg_to_rad(kneel_back_hip_deg), k)
		knee_right.rotation.x = lerpf(knee_right.rotation.x, -deg_to_rad(kneel_back_knee_deg), k)
		upper_body.position.y = lerpf(upper_body.position.y, _upper_rest_y - kneel_drop, k)
		upper_body.rotation.z = lerpf(upper_body.rotation.z, 0.0, k)
	upper_body.rotation.z = deg_to_rad(sway_deg) * _walk_amount * cos(phase)
