class_name DodgeLandingPose
extends Node
## Ending of the dodge hop. The mech lands on its lead leg in a wide, braced stance and slides a
## little. Then the trail leg steps in under the body and the legs blend back to the normal pose.
## Lead leg = the leg on the hop side (left for a left hop, left forward for a forward hop,
## right back for a back hop). Runs after MechLegSwing and changes the hip and knee turns.

@export var mech: Mech
@export var dodge: MechDodge
@export var input: MechInput
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
## Total length of the ending, in seconds.
@export var duration: float = 1.1
## Blend from the air pose into the brace at the touchdown, in seconds.
@export var blend_in_time: float = 0.08
## The trail leg steps in during this part of the ending (0 to 1).
@export var step_start: float = 0.35
@export var step_end: float = 0.75

@export_group("Brace")
## Side hop: lead leg out to the side, in degrees.
@export var side_lead_out_deg: float = 16.0
## Side hop: trail leg out to the other side, in degrees.
@export var side_trail_out_deg: float = 10.0
## Forward or back hop: lead leg swing, in degrees.
@export var split_lead_deg: float = 28.0
## Forward or back hop: trail leg swing the other way, in degrees.
@export var split_trail_deg: float = 18.0
## Knee bend of the lead leg (takes the load), in degrees.
@export var lead_knee_deg: float = 55.0
## Knee bend of the trail leg, in degrees.
@export var trail_knee_deg: float = 20.0
## Knee lift of the trail leg at the top of its step, in degrees of hip bend.
@export var step_lift_deg: float = 30.0
@export_group("")
## When the pilot moves, the ending fades out in this many seconds.
@export var cancel_time: float = 0.15

var _weight: float = 0.0


func _ready() -> void:
	# After MechLegSwing (0), before the skirts (11).
	process_physics_priority = 1


func _physics_process(delta: float) -> void:
	var t := dodge.time_since_landing
	var active := not dodge.is_dodging and t < duration
	var moving := input.move_direction.length_squared() > 0.01 or absf(input.turn_input) > 0.1
	if not active or (moving and t > dodge.recovery_time):
		_weight = move_toward(_weight, 0.0, delta / cancel_time)
	else:
		# Blends in at the touchdown. The pose itself settles to neutral, so the late fade is soft.
		_weight = smoothstep(0.0, blend_in_time, t) * (1.0 - smoothstep(0.85 * duration, duration, t))
	hip_left.rotation.z = 0.0
	hip_right.rotation.z = 0.0
	if _weight <= 0.0:
		return
	_apply(clampf(t / duration, 0.0, 1.0), _weight)


func _apply(progress: float, weight: float) -> void:
	var local := dodge.get_local_direction()
	# 0 = braced, 1 = trail leg back under the body.
	var gather := smoothstep(step_start, step_end, progress)
	# 0 = braced, 1 = lead leg stood up (a little after the trail step).
	var settle := smoothstep(step_start, 0.9, progress)
	var lift := sin(clampf((progress - step_start) / (step_end - step_start), 0.0, 1.0) * PI)
	var lead_left := local.x < -0.5 or local.z < -0.5  # Left hop or forward hop.
	var lead_hip := hip_left if lead_left else hip_right
	var trail_hip := hip_right if lead_left else hip_left
	var lead_knee := knee_left if lead_left else knee_right
	var trail_knee := knee_right if lead_left else knee_left
	var lead_swing := 0.0
	var trail_swing := 0.0
	var lead_out := 0.0
	var trail_out := 0.0
	if absf(local.x) > 0.5:
		lead_out = side_lead_out_deg
		trail_out = side_trail_out_deg
	else:
		var forward := -local.z  # +1 forward hop, -1 back hop.
		lead_swing = split_lead_deg * forward
		trail_swing = -split_trail_deg * forward
	# The lead leg stays planted and slowly stands up. The trail leg lifts and steps in.
	var lead_hip_x := deg_to_rad((lead_swing + lead_knee_deg * 0.4) * (1.0 - settle))
	var lead_knee_x := -deg_to_rad(lead_knee_deg * (1.0 - settle))
	var trail_hip_x := deg_to_rad((trail_swing + trail_knee_deg * 0.4) * (1.0 - gather) + step_lift_deg * lift)
	var trail_knee_x := -deg_to_rad(trail_knee_deg * (1.0 - gather) + step_lift_deg * 1.8 * lift)
	lead_hip.rotation.x = lerpf(lead_hip.rotation.x, lead_hip_x, weight)
	lead_knee.rotation.x = lerpf(lead_knee.rotation.x, lead_knee_x, weight)
	trail_hip.rotation.x = lerpf(trail_hip.rotation.x, trail_hip_x, weight)
	trail_knee.rotation.x = lerpf(trail_knee.rotation.x, trail_knee_x, weight)
	# Legs out to the side. Left leg out = negative Z turn, right leg out = positive.
	var lead_sign := -1.0 if lead_hip == hip_left else 1.0
	lead_hip.rotation.z = deg_to_rad(lead_out * lead_sign * (1.0 - settle)) * weight
	trail_hip.rotation.z = deg_to_rad(trail_out * -lead_sign * (1.0 - gather)) * weight
