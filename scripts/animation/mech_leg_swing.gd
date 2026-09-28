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
@export var dodge: MechDodge
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
@export var knee_bend_deg: float = 60.0
## Extra hip lift of the leg that swings forward, in degrees. Raises the knee.
@export var knee_lift_deg: float = 20.4
## Body drop at each foot strike, in meters.
@export var bob_height: float = 0.3
## Body roll toward the planted leg while walking, in degrees, for a 10 m mech.
## Sway scales with Mech.height_m (a 20 m mech sways twice as much).
@export var sway_deg: float = 0.63
## Body roll while running, in degrees, for a 10 m mech.
@export var run_sway_deg: float = 0.84
## Body side shift toward the planted leg, in meters, for a 10 m mech.
@export var sway_shift: float = 0.063
## Mech height (meters) for the sway values above.
@export var sway_reference_height: float = 10.0

@export_group("Turn Steps")
## Knee lift for steps while turning in place, as a part of the walking knee lift (0 to 1).
@export var turn_step_amount: float = 0.6
## Leg turn speed (degrees per second) that gives full turning steps.
@export var turn_step_full_rate_deg: float = 30.0

@export_group("Run")
## Hip swing while running (Shift held before boost), in degrees.
@export var run_hip_swing_deg: float = 40.0
## Knee bend of the forward leg while running, in degrees.
@export var run_knee_bend_deg: float = 70.0
## Extra hip lift of the forward leg while running, in degrees.
@export var run_knee_lift_deg: float = 20.0
## Body drop at each foot strike while running, in meters.
@export var run_bob_height: float = 0.5

@export_group("Boost Skid")
## Skid pose: the left leg braces forward, the right leg stays under the body, knees bent.
@export var skid_front_hip_deg: float = 28.0
@export var skid_front_knee_deg: float = 20.0
@export var skid_back_hip_deg: float = -8.0
@export var skid_back_knee_deg: float = 35.0
## Body drop in the skid pose, in meters.
@export var skid_drop: float = 0.6

@export_group("Boost Exit Leap")
## Leap pose: the left leg reaches forward to land, the right leg trails.
@export var leap_front_hip_deg: float = 35.0
@export var leap_front_knee_deg: float = 10.0
@export var leap_back_hip_deg: float = -30.0
@export var leap_back_knee_deg: float = 70.0

@export_group("Landing")
## Crouch after a short landing (near 0 m fall), in degrees of hip bend. Knees bend twice as much.
@export var landing_crouch_min_deg: float = 8.0
## Crouch after a fall from landing_crouch_full_height or higher, in degrees of hip bend.
@export var landing_crouch_max_deg: float = 40.0
## Fall height (meters) that gives the deepest landing crouch.
@export var landing_crouch_full_height: float = 9.0
## Crouch while boosting on the ground, in degrees of hip bend. Knees bend twice as much
## (20 = knee bent 40 degrees, an inside knee angle of 140 degrees).
@export var boost_crouch_deg: float = 14.0

@export_group("Kneel")
## Left (front) leg: thigh forward, shin straight down to the foot.
@export var kneel_front_hip_deg: float = 70.0
@export var kneel_front_knee_deg: float = 70.0
## Right (back) leg: thigh down, shin back along the ground, knee on the ground.
@export var kneel_back_hip_deg: float = -5.0
@export var kneel_back_knee_deg: float = 90.0
## Body drop when fully down, in meters. Puts the right knee on the ground.
@export var kneel_drop: float = 1.74
## Leg tuck at the top of a dodge hop, in degrees of hip bend (x the dodge tuck amount).
@export var dodge_tuck_deg: float = 50.0
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
var _run: float = 0.0
var _turn_step: float = 0.0
var _stride_scale: float = 1.0
var _leap: float = 0.0
var _skid: float = 0.0
var _upper_rest_x: float = 0.0
var _air_knee: float = 0.0
var _upper_rest_y: float = 0.0


func _ready() -> void:
	_upper_rest_y = upper_body.position.y
	_upper_rest_x = upper_body.position.x


# Runs in physics frames so it stays smooth with physics interpolation.
func _physics_process(delta: float) -> void:
	var on_floor := mech.is_on_floor()
	var walking := on_floor and not mech.is_boosting
	var speed_ratio := clampf(mech.get_horizontal_speed() / mech.walk_speed, 0.0, 1.0)
	var blend := 1.0 - exp(-blend_speed * delta)
	_walk_amount = lerpf(_walk_amount, speed_ratio if walking else 0.0, blend)
	# Steps in place while the legs turn and the mech stands still.
	var standing := on_floor and mech.get_horizontal_speed() < footsteps.min_speed
	var turn_ratio := clampf(absf(rad_to_deg(mech.leg_turn_rate)) / turn_step_full_rate_deg, 0.0, 1.0)
	_turn_step = lerpf(_turn_step, turn_ratio * turn_step_amount if standing else 0.0, blend)
	var lift_amount := maxf(_walk_amount, _turn_step)
	_trail = lerpf(_trail, 1.0 if mech.is_boosting else 0.0, blend)
	_boost_crouch = lerpf(_boost_crouch, 1.0 if mech.is_boosting and on_floor else 0.0, blend)
	_air_knee = lerpf(_air_knee, 0.0 if on_floor else 1.0, blend)
	_run = lerpf(_run, 1.0 if mech.is_running else 0.0, blend)
	_skid = lerpf(_skid, 1.0 if mech.is_skidding else 0.0, 1.0 - exp(-blend_speed * 2.5 * delta))
	var leaping := mech.is_exiting_boost and not on_floor
	_leap = lerpf(_leap, 1.0 if leaping else 0.0, 1.0 - exp(-blend_speed * 2.0 * delta))
	# Longer planned strides (boost exit big step) swing the legs wider.
	var stride_scale := clampf(footsteps.get_stride(mech.get_horizontal_speed()) / footsteps.stride_length, 0.5, 1.6)
	_stride_scale = lerpf(_stride_scale, stride_scale if footsteps.has_stride_plan() else 1.0, blend)

	var phase := footsteps.get_cycle_phase()
	# Walking backward: the lifted leg moves back, so the knee bend flips.
	var lift := sin(phase) * (-1.0 if leg_twist.moving_backward else 1.0)
	var hip := deg_to_rad(lerpf(hip_swing_deg, run_hip_swing_deg, _run)) * _stride_scale * _walk_amount * cos(phase)
	# The forward-swinging leg also lifts at the hip, so the knee comes up.
	var knee_lift := deg_to_rad(lerpf(knee_lift_deg, run_knee_lift_deg, _run)) * lift_amount
	# Legs trail behind the move direction. Backward, the legs face forward, so the trail flips.
	var trail := -deg_to_rad(boost_trail_deg) * _trail * (-1.0 if leg_twist.moving_backward else 1.0)
	# The leg that moves forward lifts its foot by bending the knee.
	var knee := deg_to_rad(lerpf(knee_bend_deg, run_knee_bend_deg, _run)) * lift_amount
	var air := deg_to_rad(air_knee_deg) * _air_knee
	# Crouch just after landing, deeper for higher falls, then the mech stands up.
	var fall_ratio := clampf(landing_recovery.fall_height / landing_crouch_full_height, 0.0, 1.0)
	var landing_depth := deg_to_rad(lerpf(landing_crouch_min_deg, landing_crouch_max_deg, fall_ratio))
	var landing_crouch := landing_depth * sin(landing_recovery.get_fraction() * PI * 0.5)
	# The mech crouches deeper as the jump jets charge.
	var charge_crouch := deg_to_rad(charge_crouch_deg) * jump_charge.charge
	# Low stance while boosting on the ground.
	var boost_crouch := deg_to_rad(boost_crouch_deg) * _boost_crouch
	var dodge_tuck := deg_to_rad(dodge_tuck_deg) * dodge.get_tuck()
	# Dodge recovery crouch (only the part above upright).
	dodge_tuck = maxf(dodge_tuck, deg_to_rad(dodge.recover_crouch_deg) * maxf(dodge.get_recovery_pose(), 0.0))
	var crouch := maxf(maxf(maxf(landing_crouch, charge_crouch), boost_crouch), dodge_tuck)

	hip_left.rotation.x = hip + knee_lift * maxf(0.0, -lift) + trail + air * 0.5 + crouch
	hip_right.rotation.x = -hip + knee_lift * maxf(0.0, lift) + trail + air * 0.5 + crouch
	knee_left.rotation.x = -knee * maxf(0.0, -lift) - air - crouch * 2.0
	knee_right.rotation.x = -knee * maxf(0.0, lift) - air - crouch * 2.0

	# Lowest at foot strike (phase = 0, PI), highest between steps.
	var bob := lerpf(bob_height, run_bob_height, _run) * _walk_amount * (cos(2.0 * phase) + 1.0) * 0.5
	# A crouch shortens the legs. Lower the body by the same amount so the feet stay down.
	# In the air the tuck does not lower the body (the feet are off the ground).
	var drop_angle := crouch if mech.is_on_floor() else maxf(maxf(landing_crouch, charge_crouch), boost_crouch)
	var crouch_drop := leg_length * (1.0 - cos(drop_angle))
	upper_body.position.y = _upper_rest_y - bob - crouch_drop

	# Boost skid: braced stance while the feet slide.
	if _skid > 0.001:
		hip_left.rotation.x = lerpf(hip_left.rotation.x, deg_to_rad(skid_front_hip_deg), _skid)
		knee_left.rotation.x = lerpf(knee_left.rotation.x, -deg_to_rad(skid_front_knee_deg), _skid)
		hip_right.rotation.x = lerpf(hip_right.rotation.x, deg_to_rad(skid_back_hip_deg), _skid)
		knee_right.rotation.x = lerpf(knee_right.rotation.x, -deg_to_rad(skid_back_knee_deg), _skid)
		upper_body.position.y -= skid_drop * _skid

	# Boost exit leap: left leg forward to land on, right leg trailing.
	if _leap > 0.001:
		hip_left.rotation.x = lerpf(hip_left.rotation.x, deg_to_rad(leap_front_hip_deg), _leap)
		knee_left.rotation.x = lerpf(knee_left.rotation.x, -deg_to_rad(leap_front_knee_deg), _leap)
		hip_right.rotation.x = lerpf(hip_right.rotation.x, deg_to_rad(leap_back_hip_deg), _leap)
		knee_right.rotation.x = lerpf(knee_right.rotation.x, -deg_to_rad(leap_back_knee_deg), _leap)

	# Kneel: blend both legs and the body height to the kneel pose.
	var k := smoothstep(0.0, 1.0, kneel.amount)
	if k > 0.0:
		hip_left.rotation.x = lerpf(hip_left.rotation.x, deg_to_rad(kneel_front_hip_deg), k)
		knee_left.rotation.x = lerpf(knee_left.rotation.x, -deg_to_rad(kneel_front_knee_deg), k)
		hip_right.rotation.x = lerpf(hip_right.rotation.x, deg_to_rad(kneel_back_hip_deg), k)
		knee_right.rotation.x = lerpf(knee_right.rotation.x, -deg_to_rad(kneel_back_knee_deg), k)
		upper_body.position.y = lerpf(upper_body.position.y, _upper_rest_y - kneel_drop, k)
		upper_body.rotation.z = lerpf(upper_body.rotation.z, 0.0, k)
		upper_body.position.x = lerpf(upper_body.position.x, _upper_rest_x, k)
	var size := mech.height_m / sway_reference_height
	var sway := deg_to_rad(lerpf(sway_deg, run_sway_deg, _run)) * size * _walk_amount * cos(phase)
	upper_body.rotation.z = sway
	upper_body.position.x = _upper_rest_x - sway_shift * size * _walk_amount * cos(phase)
