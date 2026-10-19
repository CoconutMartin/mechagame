class_name JumpClipDirector
extends RefCounted
## Decides which jump, fall and landing clips play and at which time (user requests 2026-10-15 and
## phase 4, 2026-10-18). Three layers, each over the one before it (the last one that is full hides the rest):
##   0 jump_up (Jumping_Up): its crouch follows the jump charge (0 to crouch_time), the release plays the
##     push to takeoff_time (over MechJumpCharge.push_time on the ground, or in air_push_time after the
##     launch when push_time is 0), and the rest of the clip (the legs tuck) plays while the mech rises,
##     timed to end near the top of the jump, then holds.
##   1 fall_start (Jumping_Down): from the top of a jump or the walk off an edge, the start of the fall;
##     it plays to its hold frame and holds while the mech is in the air.
##   2 landing (Landing): the clip time follows the predicted time to impact (ray down, gravity), so its
##     touchdown frame meets the real touchdown; on the ground it plays on through the crouch and the rise,
##     stretched to the landing recovery, then it is released.
## Falls under min_fall_height keep the coded landing crouch (SkeletalJumpPose), and so do all other
## landings (dodge step). The coded landing is off (coded_landing) while the landing clip plays.

const LAYERS := 3

var mech: Mech
var jump_charge: MechJumpCharge
var landing_recovery: MechLandingRecovery
var jump_up: AirClip
var fall_start: AirClip
var landing: AirClip
## Falls shorter than this (m) play no clip (the coded landing crouch). The drop is the height already
## fallen plus the height to the ground.
var min_fall_height: float = 1.0
## Seconds in the air before the fall clip may start (a step down gives none).
var start_delay: float = 0.1
## Ground layer for the ray down.
var ground_mask: int = 1
## Slowest and fastest landing clip playback when it is stretched to the recovery time.
var min_land_speed: float = 0.6
var max_land_speed: float = 1.5
## Part of the rise time (launch to the top) the tuck of jump_up takes; slowest and fastest playback.
var rise_part: float = 0.85
var min_rise_speed: float = 0.25
var max_rise_speed: float = 1.5
## Seconds the push (crouch to takeoff_time) takes in the air when the mech launches at the release.
var air_push_time: float = 0.12

## Per layer now.
var weights: Array[float] = [0.0, 0.0, 0.0]
var times: Array[float] = [0.0, 0.0, 0.0]
## 1 = the coded landing crouch plays, 0 = a landing clip plays instead.
var coded_landing: float = 1.0
## Predicted seconds to the ground in the last frame in the air (INF = unknown).
var time_to_impact: float = INF

var _air_time: float = 0.0
var _falling_clip: bool = false
var _peak_y: float = 0.0
var _last_left: float = 0.0
## True while the landing clip plays on the ground.
var _landing_clip: bool = false
## jump_up: the clip time at the release, and true from the push until the top of the jump.
var _release_time: float = -1.0
var _rising: bool = false
var _rise_speed: float = 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func clips() -> Array[AirClip]:
	return [jump_up, fall_start, landing]


func update(delta: float) -> void:
	var free := not mech.is_wrecked and not mech.is_fallen
	var on_floor := mech.is_on_floor()
	var flying := not on_floor and free and not mech.dodge.is_dodging and not mech.is_exiting_boost
	var recovering := landing_recovery != null and landing_recovery.is_recovering()
	var new_landing := recovering and on_floor and landing_recovery.time_left > _last_left + 0.0001
	_last_left = landing_recovery.time_left if landing_recovery != null else 0.0
	if on_floor:
		_peak_y = mech.global_position.y
	else:
		_peak_y = maxf(_peak_y, mech.global_position.y)
	time_to_impact = INF
	var targets: Array[float] = [0.0, 0.0, 0.0]
	if flying:
		_landing_clip = false
		_air_time += delta
		_update_rise(delta, targets)
		_update_air(delta, targets)
	else:
		_air_time = 0.0
		if on_floor and free:
			_update_charge(targets)
		if new_landing and free:
			_start_landing()
		if _landing_clip and recovering and free and on_floor:
			_update_landing(targets)
		else:
			_landing_clip = false
			_falling_clip = false
	coded_landing = 0.0 if _landing_clip else 1.0
	_slew(delta, targets, free)


## On the ground: the crouch follows the charge, then the push to the takeoff.
func _update_charge(targets: Array[float]) -> void:
	_rising = false
	if jump_charge == null or not jump_charge.is_charging:
		_release_time = -1.0
		return
	# A launch can follow in any frame of the charge.
	_rising = true
	targets[0] = 1.0
	if jump_charge.is_pushing:
		if _release_time < 0.0:
			_release_time = times[0]
		times[0] = lerpf(_release_time, jump_up.takeoff_time, smoothstep(0.0, 1.0, jump_charge.push))
	else:
		_release_time = -1.0
		times[0] = jump_up.crouch_time * smoothstep(0.0, 1.0, jump_charge.charge)


## In the air after a push: the tuck plays while the mech rises; it ends at the top.
func _update_rise(delta: float, targets: Array[float]) -> void:
	if not _rising:
		return
	if mech.velocity.y <= 0.0:
		_rising = false
		return
	var hold := jump_up.get_hold_time()
	if _air_time <= delta * 1.5:
		var rise_time := mech.velocity.y / maxf(_gravity * mech.gravity_scale, 0.1)
		var span := hold - jump_up.takeoff_time
		var push_left := maxf(jump_up.takeoff_time - times[0], 0.0) / _air_push_speed()
		var tuck_time := maxf(rise_time * rise_part - push_left, 0.05)
		_rise_speed = clampf(span / tuck_time, min_rise_speed, max_rise_speed)
	targets[0] = 1.0
	if times[0] < jump_up.takeoff_time:
		# Launched at the release: the rest of the push, fast.
		times[0] = minf(times[0] + delta * _air_push_speed(), jump_up.takeoff_time)
	else:
		times[0] = minf(times[0] + delta * _rise_speed, hold)


## Clip seconds per second of the push in the air (crouch_time to takeoff_time in air_push_time).
func _air_push_speed() -> float:
	return (jump_up.takeoff_time - jump_up.crouch_time) / maxf(air_push_time, 0.01)


## In the air: the fall start, then the touchdown clip by the predicted time to impact.
func _update_air(delta: float, targets: Array[float]) -> void:
	if mech.velocity.y > 0.0 or _air_time < start_delay:
		return
	var remaining := _height_above_ground()
	if not _falling_clip:
		if (_peak_y - mech.global_position.y) + remaining < min_fall_height:
			return
		_falling_clip = true
		times[1] = 0.0
		times[2] = 0.0
	targets[1] = 1.0
	times[1] = minf(times[1] + delta * fall_start.speed_scale, fall_start.get_hold_time())
	time_to_impact = _impact_time(remaining)
	if time_to_impact <= landing.contact_time:
		targets[2] = 1.0
		times[2] = maxf(times[2], landing.contact_time - time_to_impact)


## A new landing: the landing clip after a fall of min_fall_height or more.
func _start_landing() -> void:
	_landing_clip = landing_recovery.fall_height >= min_fall_height
	if _landing_clip:
		times[2] = maxf(times[2], landing.contact_time)


## On the ground after the landing: the clip plays on, stretched to the recovery, and is released in the
## last part.
func _update_landing(targets: Array[float]) -> void:
	var duration := maxf(landing_recovery.duration, 0.05)
	var elapsed := duration - landing_recovery.time_left
	var release := clampf(landing_recovery.time_left / minf(landing.blend_out, duration * 0.6), 0.0, 1.0)
	var span := landing.get_hold_time() - landing.contact_time
	var speed := clampf(span / maxf(duration - landing.blend_out, 0.05), min_land_speed, max_land_speed)
	times[2] = landing.contact_time + minf(elapsed * speed, span)
	targets[2] = smoothstep(0.0, 1.0, release)
	# The fall pose stays under it until it is full, but not while it is released.
	targets[1] = 1.0 if (_falling_clip and weights[2] < 0.999 and release >= 1.0) else 0.0


## Weights move to their targets; a full layer hides the ones under it.
func _slew(delta: float, targets: Array[float], free: bool) -> void:
	var all := clips()
	for i in LAYERS:
		var clip := all[i]
		var rate := 1.0 / maxf(clip.blend_in if targets[i] > weights[i] else clip.blend_out, 0.01)
		if not free:
			rate = 12.0
		# Release (landing, last part): the weight follows its target at once.
		var at_once := _landing_clip and i == 2 and targets[i] < weights[i]
		weights[i] = targets[i] if at_once else move_toward(weights[i], targets[i], rate * delta)
	for i in range(LAYERS - 1, 0, -1):
		if weights[i] >= 0.999:
			for lower in i:
				weights[lower] = 0.0
	for i in LAYERS:
		if weights[i] <= 0.0 and targets[i] <= 0.0 and not _falling_clip and not _landing_clip and not _rising:
			times[i] = 0.0


func is_active() -> bool:
	return weights[0] > 0.001 or weights[1] > 0.001 or weights[2] > 0.001


## Height of the mech's feet above the ground under it (m), by a ray down.
func _height_above_ground(extra: Vector3 = Vector3.ZERO) -> float:
	var from := mech.global_position + extra + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 200.0, ground_mask)
	query.exclude = mech.get_hit_exclude()
	var hit := mech.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	return maxf(from.y - (hit.position as Vector3).y - 0.5, 0.0)


## Seconds until the feet reach the ground: the fall under gravity, the ground taken again where the
## mech will be (its sideways speed).
func _impact_time(remaining: float) -> float:
	var gravity := _gravity * mech.gravity_scale
	var down := maxf(-mech.velocity.y, 0.0)
	var height := remaining
	var time := INF
	for pass_index in 2:
		if height == INF:
			return INF
		time = (-down + sqrt(down * down + 2.0 * gravity * height)) / gravity
		if pass_index == 0:
			var sideways := Vector3(mech.velocity.x, 0.0, mech.velocity.z) * time
			height = _height_above_ground(sideways)
	return time
