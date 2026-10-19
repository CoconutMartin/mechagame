class_name SkeletalJumpPose
extends SkeletonModifier3D
## Jump and landing leg poses of the rigged mech (user request 2026-10-13, from the reference pose
## prompt "jump charge and hard landing"):
## A, charge: while the jump jets charge (MechJumpCharge, full in 3 s) the mech crouches with the
##   charge: hips back and down, the torso leans forward from the hips, knees forward, feet flat where
##   they stand. Release (the launch) lets go of the crouch fast.
## A2, launch: the first part of the flight the legs push long and the toes point down.
## B0, air: then the legs reach down, a little bent, toes a little down.
## B, landing: at contact the legs compress fast (a spring, with a small overshoot) as deep as the fall
##   was high (full at land_full_height, the top of a full jump), wider feet, the torso drops and leans;
##   the pose holds through the landing recovery (MechLandingRecovery) and lets go in its last part.
## Clips (user requests 2026-10-15 and phase 4, 2026-10-18; JumpClipDirector decides when, AirClipBody
## puts them on the body with the feet on the floor): Jumping_Up over A and A2 (its crouch follows the
## charge, then the push and the tuck while rising), Jumping_Down from the top of a jump or the walk off
## an edge, and Landing timed so its touchdown frame meets the real touchdown, then its crouch and rise
## through the recovery. Falls under min_fall_height and the dodge step landing keep the coded landing
## crouch (B).
## The legs use a two-bone solve (the ankle on its target, the knee toward the front, the foot flat).
## The arms keep their weapon holds (SkeletalArmRig runs after this node and follows the torso).
## A skeleton modifier must be a child of the Skeleton3D; this node moves itself there at start. Keep
## it after SkeletalAimStance and before SkeletalArmRig.

@export var model: Node3D
@export var mech: Mech
@export var jump_charge: MechJumpCharge
@export var landing_recovery: MechLandingRecovery

@export_group("A Charge")
## Inner knee angle (degrees), torso lean from the hips (degrees) and hips moved back (m), at full charge.
@export var charge_knee_deg: float = 105.0
@export var charge_lean_deg: float = 22.0
@export var charge_hips_back: float = 0.35
## How fast the crouch follows the charge going up and lets go at the launch (per second).
@export var charge_in_speed: float = 3.0
@export var charge_out_speed: float = 8.0

@export_group("A2 Launch and B0 Air")
## Launch: how long the pushed-out legs last after the takeoff (s), and the toe drop (degrees).
@export var launch_time: float = 0.35
@export var launch_toe_deg: float = 25.0
## Air: inner knee angle and toe drop (degrees); it blends in from the end of the launch.
@export var air_knee_deg: float = 140.0
@export var air_toe_deg: float = 12.0
## The air pose blends in and out at this speed (per second).
@export var air_speed: float = 4.0

@export_group("B Landing")
## At a fall of land_full_height (m): inner knee angle, torso lean (degrees), hips back and feet out (m).
@export var land_knee_deg: float = 95.0
@export var land_lean_deg: float = 15.0
@export var land_hips_back: float = 0.2
@export var land_feet_out: float = 0.25
@export var land_full_height: float = 9.0
## Higher falls compress more, up to this many times the full landing.
@export var land_max_scale: float = 1.15
## Shorter falls compress at least this part of the full landing.
@export var land_min_scale: float = 0.25
## The pose lets go in this last part of the recovery time.
@export_range(0.05, 1.0) var land_release_part: float = 0.45
## Impact spring: speed (swings per second) and damping (1 = no overshoot).
@export var impact_frequency: float = 3.5
@export_range(0.05, 1.0) var impact_damping: float = 0.45
## Extra speed into the compression at contact (part of one spring swing): the overshoot.
@export var impact_kick: float = 0.2

## Knees point forward and this much out to the side (0: straight forward; knees out ran the thighs
## into side-held items: the forearm cannon, a free hand).
@export var knee_out: float = 0.0

## The weapon frame (held weapons, shield, free hand places) moves this much (torso space: +Y up, -Z
## forward) at the deepest crouch, so the thighs coming up keep off the arms (SkeletalArmRig).
@export var weapon_lift: Vector3 = Vector3(0.0, 0.8, -0.15)
## Jump guard height (user choice 2026-10-19: "the arms lift the weapon up to the chest"): at full guard
## the weapon frame (weapons, shield, free hand places) rises straight up until its origin is at least
## this high above the feet (m; the torso frame stands about 5.6 m high), so the clip poses (Jumping_Up,
## Landing: deep lean, thighs high) keep the knees off the weapons and hands. The arms reach up toward it.
@export var guard_height: float = 6.5

@export_group("Guard")
## Guard (user choice 2026-10-19: "the arms lift the weapon up to the chest"): during the charge, a
## clip jump, the fall and the landing clip the weapon frame rises to guard_height and free or fist
## hands go to a guard place in front of the chest (SkeletalArmRig), so the knees coming up keep off the
## weapons and hands. How fast the guard comes on and goes off (per second).
@export var guard_in_speed: float = 4.0
@export var guard_out_speed: float = 2.5
## The guard goes off this many seconds before the landing recovery ends, so the weapons are back in
## their own hold as the mech stands up (user request 2026-10-19).
@export var guard_release_lead: float = 0.5

@export_group("Clips")
## Jumping_Up: the charge crouch, the push and the tuck while rising.
@export var jump_up_clip: AirClip = preload("res://data/jump_clips/jump_up.tres")
## Jumping_Down: the start of a fall (holds its pose while the mech is in the air).
@export var fall_start_clip: AirClip = preload("res://data/jump_clips/fall_start.tres")
## Landing: the end of a fall; its touchdown frame meets the real touchdown, then the crouch and rise.
@export var landing_clip: AirClip = preload("res://data/jump_clips/landing.tres")
## Falls shorter than this (m) play no landing clip and keep the coded landing crouch (the landing
## recovery's min_height: its short fall delay).
@export var min_fall_height: float = 1.0
## Seconds in the air before the fall clip may start.
@export var fall_clip_delay: float = 0.1
## Ground layer for the ray that predicts the touchdown (1 = world).
@export_flags_3d_physics var ground_mask: int = 1

@export_group("Bones")
@export var pelvis_bone: StringName = &"pelvis"
@export var leg_bones_left: PackedStringArray = ["thigh_L", "shin_L", "foot_L"]
@export var leg_bones_right: PackedStringArray = ["thigh_R", "shin_R", "foot_R"]

## Weights now (0 to 1; landing up to land_max_scale).
var crouch: float = 0.0
var launch: float = 0.0
var air: float = 0.0
var landing: float = 0.0

## The clip layers (null until the skeleton is there).
var director: JumpClipDirector
## Crouch depth of the clip pose now (0 to 1), for the weapon lift.
var clip_depth: float = 0.0
## Guard now (0 to 1): see guard_in_speed.
var guard: float = 0.0

var _clip_body: AirClipBody
var _landing_speed: float = 0.0
var _air_time: float = 0.0
var _last_recovery_left: float = 0.0


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


## Weapon offset now (torso space): weapon_lift by the crouch or landing depth.
func weapon_offset() -> Vector3:
	return weapon_lift * clampf(maxf(crouch, landing), 0.0, 1.0)


## Jump guard: how far (m) the weapon frame rises straight up when its origin is height m above the feet.
func guard_rise(height: float) -> float:
	return maxf(guard_height - height, 0.0) * smoothstep(0.0, 1.0, guard)


func _process_modification_with_delta(delta: float) -> void:
	if mech == null:
		return
	var skeleton := get_skeleton()
	if director == null:
		_setup_clips(skeleton)
	director.update(delta)
	_update_weights(delta)
	var coded := crouch > 0.001 or launch > 0.001 or air > 0.001 or absf(landing) > 0.001
	if not coded and not director.is_active():
		clip_depth = 0.0
		return
	var pelvis := skeleton.find_bone(pelvis_bone)
	var legs := [_leg(skeleton, leg_bones_left), _leg(skeleton, leg_bones_right)]
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(pelvis))
	var now := skeleton.get_bone_global_pose(pelvis)
	var upper: float = legs[0].upper
	var lower: float = legs[0].lower
	if coded:
		if mech.is_on_floor():
			_pose_ground(skeleton, pelvis, parent, now, legs, upper, lower)
		else:
			_pose_air(skeleton, now, legs, upper, lower)
	_pose_clips(skeleton, parent, now, legs)


func _setup_clips(skeleton: Skeleton3D) -> void:
	_clip_body = AirClipBody.new()
	_clip_body.setup(skeleton)
	director = JumpClipDirector.new()
	director.mech = mech
	director.jump_charge = jump_charge
	director.landing_recovery = landing_recovery
	director.jump_up = jump_up_clip
	director.fall_start = fall_start_clip
	director.landing = landing_clip
	director.min_fall_height = min_fall_height
	director.start_delay = fall_clip_delay
	director.ground_mask = ground_mask


## The clip layers over the coded pose, then the feet are kept out of the floor.
func _pose_clips(skeleton: Skeleton3D, parent: Transform3D, now: Transform3D, legs: Array) -> void:
	clip_depth = 0.0
	if not director.is_active():
		return
	var floor_height := (skeleton.global_transform.affine_inverse() * mech.global_position).y
	var anchor := ((legs[0].ankle as Vector3) + (legs[1].ankle as Vector3)) * 0.5
	var yaw := atan2(now.basis.z.x, now.basis.z.z) - atan2(parent.basis.z.x, parent.basis.z.z)
	var all := director.clips()
	for i in JumpClipDirector.LAYERS:
		var weight := director.weights[i]
		if weight <= 0.001:
			continue
		var clip := all[i]
		var level := floor_height
		if clip.lift_scale > 0.0:
			level += _clip_body.clip_height(clip, director.times[i]) * clip.lift_scale
		var depth := _clip_body.apply(clip, director.times[i], weight, anchor, yaw, level)
		clip_depth = maxf(clip_depth, depth * weight)
	_clip_body.keep_feet_up(floor_height)


func _update_weights(delta: float) -> void:
	var free := not mech.is_wrecked and not mech.is_fallen
	var on_floor := mech.is_on_floor()
	# A: the crouch follows the charge; the launch (charge back to 0) lets go fast.
	var charging := jump_charge != null and jump_charge.is_charging and on_floor and free
	var standing_up := on_floor and landing_recovery != null and landing_recovery.time_left < guard_release_lead
	var guard_on := free and (charging or (director.is_active() and not standing_up))
	guard = move_toward(guard, 1.0 if guard_on else 0.0, (guard_in_speed if guard_on else guard_out_speed) * delta)
	var crouch_target := smoothstep(0.0, 1.0, jump_charge.charge) if charging else 0.0
	crouch = move_toward(crouch, crouch_target, (charge_in_speed if crouch_target > crouch else charge_out_speed) * delta)
	# A2 and B0: the flight of a jump or a fall (not a dodge hop or the boost exit leap).
	var flying := not on_floor and free and not mech.dodge.is_dodging and not mech.is_exiting_boost
	_air_time = _air_time + delta if flying else 0.0
	var launch_target := 1.0 - smoothstep(0.0, launch_time, _air_time) if flying and mech.velocity.y > 0.0 else 0.0
	launch = move_toward(launch, launch_target, 10.0 * delta)
	var air_target := smoothstep(launch_time * 0.5, launch_time * 1.5, _air_time) if flying else 0.0
	air = move_toward(air, air_target, (air_speed if flying else 12.0) * delta)
	# B: a new landing starts the impact spring toward the depth of the fall, held through the recovery.
	var target := 0.0
	if landing_recovery != null and landing_recovery.is_recovering() and on_floor and free:
		var depth := clampf(landing_recovery.fall_height / land_full_height, land_min_scale, land_max_scale) * director.coded_landing
		var left := landing_recovery.get_fraction()
		target = depth * smoothstep(0.0, land_release_part, left)
		if landing_recovery.time_left > _last_recovery_left + 0.0001:
			_landing_speed += depth * 2.0 * PI * impact_frequency * impact_kick
	_last_recovery_left = landing_recovery.time_left if landing_recovery != null else 0.0
	# The spring in small steps: one long frame must not throw it off.
	var omega := 2.0 * PI * impact_frequency
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var h := delta / steps
	for i in steps:
		_landing_speed += (omega * omega * (target - landing) - 2.0 * impact_damping * omega * _landing_speed) * h
		landing = clampf(landing + _landing_speed * h, 0.0, land_max_scale * 1.2)
	if target <= 0.0 and landing < 0.002 and _landing_speed <= 0.0:
		landing = 0.0
		_landing_speed = 0.0


## Ground poses (A and B): the pelvis drops, moves back and leans; the feet stay where they stand.
func _pose_ground(skeleton: Skeleton3D, pelvis: int, parent: Transform3D, now: Transform3D, legs: Array,
		upper: float, lower: float) -> void:
	var land := landing
	var lean := deg_to_rad(charge_lean_deg * crouch + land_lean_deg * land)
	var back := charge_hips_back * crouch + land_hips_back * land
	var out := land_feet_out * minf(land, 1.0)
	var standing := 0.0
	for leg: Dictionary in legs:
		standing += (leg.ankle as Vector3).distance_to((now * leg.hip_local as Vector3)) * 0.5
	var reach := standing
	reach -= (standing - _reach(upper, lower, charge_knee_deg)) * crouch
	reach -= (standing - _reach(upper, lower, land_knee_deg)) * land
	reach = clampf(reach, 0.6, upper + lower - 0.01)
	var turned := Basis(Vector3.RIGHT, lean) * now.basis
	var shift := Vector3(0.0, 0.0, -back)  # model space: +Z is the front
	# Feet out (+X is the mech's left), then the drop that gives the leg reach (searched).
	var ankles: Array[Vector3] = []
	for i in legs.size():
		var side := 1.0 if i == 0 else -1.0
		ankles.append((legs[i].ankle as Vector3) + Vector3.RIGHT * side * out)
	var low := -0.5
	var high := 3.0
	for step in 14:
		var mid := (low + high) * 0.5
		var pose := Transform3D(turned, now.origin + shift + Vector3.DOWN * mid)
		var mean := 0.0
		for i in legs.size():
			mean += ankles[i].distance_to(pose * (legs[i].hip_local as Vector3)) * 0.5
		if mean > reach:
			low = mid
		else:
			high = mid
	var pelvis_pose := Transform3D(turned, now.origin + shift + Vector3.DOWN * (low + high) * 0.5)
	var local := parent.affine_inverse() * pelvis_pose
	skeleton.set_bone_pose_position(pelvis, local.origin)
	skeleton.set_bone_pose_rotation(pelvis, local.basis.get_rotation_quaternion())
	for i in legs.size():
		var side := 1.0 if i == 0 else -1.0
		_solve(skeleton, pelvis_pose, legs[i], ankles[i], legs[i].foot_basis, Vector3(knee_out * side, 0.0, 1.0))


## Air poses (A2 and B0): the pelvis stays; the ankles come up toward the hips, the toes point down.
func _pose_air(skeleton: Skeleton3D, now: Transform3D, legs: Array, upper: float, lower: float) -> void:
	var full := upper + lower - 0.01
	var bent := _reach(upper, lower, air_knee_deg)
	for i in legs.size():
		var leg: Dictionary = legs[i]
		var hip: Vector3 = now * (leg.hip_local as Vector3)
		var down := ((leg.ankle as Vector3) - hip).normalized()
		var length := (leg.ankle as Vector3).distance_to(hip)
		length = lerpf(length, full, launch)
		length = lerpf(length, bent, air * (1.0 - launch))
		var toe := deg_to_rad(launch_toe_deg * launch + air_toe_deg * air * (1.0 - launch))
		var side := 1.0 if i == 0 else -1.0
		_solve(skeleton, now, leg, hip + down * length, Basis(Vector3.RIGHT, toe) * (leg.foot_basis as Basis),
				Vector3(knee_out * side, 0.0, 1.0))


## Hip-to-ankle length for an inner knee angle.
static func _reach(upper: float, lower: float, knee_deg: float) -> float:
	return sqrt(upper * upper + lower * lower - 2.0 * upper * lower * cos(deg_to_rad(knee_deg)))


## The leg as it is now: bones, lengths, ankle place, foot turn, hip place in the pelvis.
func _leg(skeleton: Skeleton3D, names: PackedStringArray) -> Dictionary:
	var thigh := skeleton.find_bone(names[0])
	var shin := skeleton.find_bone(names[1])
	var foot := skeleton.find_bone(names[2])
	var pelvis_pose := skeleton.get_bone_global_pose(skeleton.get_bone_parent(thigh))
	return {
		"thigh": thigh, "shin": shin, "foot": foot,
		"upper": skeleton.get_bone_global_rest(thigh).origin.distance_to(skeleton.get_bone_global_rest(shin).origin),
		"lower": skeleton.get_bone_global_rest(shin).origin.distance_to(skeleton.get_bone_global_rest(foot).origin),
		"ankle": skeleton.get_bone_global_pose(foot).origin,
		"foot_basis": skeleton.get_bone_global_pose(foot).basis,
		"hip_local": pelvis_pose.affine_inverse() * skeleton.get_bone_global_pose(thigh).origin,
	}


## Two-bone leg solve with the pelvis at pelvis_pose: the ankle at ankle, the knee toward pole, the
## foot at foot_basis (skeleton space). Sets the three bone rotations.
func _solve(skeleton: Skeleton3D, pelvis_pose: Transform3D, leg: Dictionary, ankle: Vector3, foot_basis: Basis,
		pole: Vector3) -> void:
	var thigh: int = leg.thigh
	var shin: int = leg.shin
	var foot: int = leg.foot
	var upper: float = leg.upper
	var lower: float = leg.lower
	var thigh_pose := pelvis_pose * skeleton.get_bone_pose(thigh)
	var shin_pose := thigh_pose * skeleton.get_bone_pose(shin)
	var foot_pose := shin_pose * skeleton.get_bone_pose(foot)
	var hip := thigh_pose.origin
	var reach := ankle - hip
	var distance := clampf(reach.length(), 0.01, upper + lower - 0.001)
	var along := reach.normalized()
	var cos_hip := clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0)
	var side := pole - along * pole.dot(along)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.FORWARD
	var knee := hip + along * upper * cos_hip + side * upper * sqrt(1.0 - cos_hip * cos_hip)
	var end := hip + along * distance
	var thigh_swing := Basis(Quaternion((shin_pose.origin - hip).normalized(), (knee - hip).normalized()))
	var thigh_basis := thigh_swing * thigh_pose.basis
	var shin_basis := thigh_swing * shin_pose.basis
	var shin_dir := (thigh_swing * (foot_pose.origin - shin_pose.origin)).normalized()
	shin_basis = Basis(Quaternion(shin_dir, (end - knee).normalized())) * shin_basis
	skeleton.set_bone_pose_rotation(thigh, (pelvis_pose.basis.orthonormalized().inverse() * thigh_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(shin, (thigh_basis.orthonormalized().inverse() * shin_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(foot, (shin_basis.orthonormalized().inverse() * foot_basis.orthonormalized()).get_rotation_quaternion())
