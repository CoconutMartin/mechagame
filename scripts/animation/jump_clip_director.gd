class_name JumpClipDirector
extends RefCounted
## Decides which jump, fall and landing clips play and at which time (user request 2026-10-15).
## Three layers, each over the one before it (the last one that is full hides the rest):
##   0 fall_start (Jumping_Down): from the top of a jump or the walk off an edge, the start of the fall;
##     it plays to its hold frame and holds while the mech is in the air.
##   1 fall_end (Falling_To_Landing): the clip time follows the predicted time to impact (ray down, gravity),
##     so its touchdown frame meets the real touchdown. After a fall of at least min_fall_height and under
##     hard_fall_height it plays on through its crouch and rise, stretched to the landing recovery.
##   2 hard_landing (Landing_position): after a fall of hard_fall_height or more: the crouch, held until the
##     end of the recovery, then released.
## Falls under min_fall_height keep the coded landing crouch (SkeletalJumpPose), and so do all other
## landings (dodge step). The coded landing is off (coded_landing) while a landing clip plays.

const LAYERS := 3

var mech: Mech
var landing_recovery: MechLandingRecovery
var fall_start: AirClip
var fall_end: AirClip
var hard_landing: AirClip
## Falls shorter than this (m) play no clip (the coded landing crouch). The drop is the height already
## fallen plus the height to the ground.
var min_fall_height: float = 1.0
## Falls of this height (m) or more land with the hard landing clip; shorter ones with Falling_To_Landing.
var hard_fall_height: float = 3.0
## Seconds in the air before the fall clip may start (a step down gives none).
var start_delay: float = 0.1
## Ground layer for the ray down.
var ground_mask: int = 1
## Slowest and fastest landing clip playback when it is stretched to the recovery time.
var min_land_speed: float = 0.6
var max_land_speed: float = 1.5

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
## 0 none, 1 Falling_To_Landing plays on, 2 hard landing.
var _tier: int = 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func clips() -> Array[AirClip]:
	return [fall_start, fall_end, hard_landing]


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
		_tier = 0
		_air_time += delta
		_update_air(delta, targets)
	else:
		_air_time = 0.0
		if new_landing and free:
			_start_landing()
		if _tier > 0 and recovering and free and on_floor:
			_update_landing(targets)
		else:
			_tier = 0
			_falling_clip = false
	coded_landing = 0.0 if _tier > 0 else 1.0
	_slew(delta, targets, free)


## In the air: the fall start, then the touchdown clip by the predicted time to impact.
func _update_air(delta: float, targets: Array[float]) -> void:
	if mech.velocity.y > 0.0 or _air_time < start_delay:
		return
	var remaining := _height_above_ground()
	if not _falling_clip:
		if (_peak_y - mech.global_position.y) + remaining < min_fall_height:
			return
		_falling_clip = true
		times[0] = 0.0
		times[1] = 0.0
	targets[0] = 1.0
	times[0] = minf(times[0] + delta * fall_start.speed_scale, fall_start.get_hold_time())
	time_to_impact = _impact_time(remaining)
	if time_to_impact <= fall_end.contact_time:
		targets[1] = 1.0
		times[1] = maxf(times[1], fall_end.contact_time - time_to_impact)


## A new landing: the clip for the height of the fall.
func _start_landing() -> void:
	var height := landing_recovery.fall_height
	if height < min_fall_height:
		_tier = 0
	elif height < hard_fall_height:
		_tier = 1
	else:
		_tier = 2
	if _tier == 1:
		times[1] = maxf(times[1], fall_end.contact_time)
	elif _tier == 2:
		times[1] = maxf(times[1], fall_end.contact_time)
		times[2] = hard_landing.contact_time


## On the ground after the landing: the clip plays on, stretched to the recovery, and is released in the
## last part.
func _update_landing(targets: Array[float]) -> void:
	var duration := maxf(landing_recovery.duration, 0.05)
	var elapsed := duration - landing_recovery.time_left
	var layer := _tier
	var clip := fall_end if _tier == 1 else hard_landing
	var release := clampf(landing_recovery.time_left / minf(clip.blend_out, duration * 0.6), 0.0, 1.0)
	var span := clip.get_hold_time() - clip.contact_time
	var speed := clampf(span / maxf(duration - clip.blend_out, 0.05), min_land_speed, max_land_speed)
	times[layer] = clip.contact_time + minf(elapsed * speed, span)
	targets[layer] = smoothstep(0.0, 1.0, release)
	if _tier == 2:
		targets[1] = 1.0
		times[1] = fall_end.contact_time
	# The layers under it stay until it is full, but not while it is released.
	for lower in layer:
		targets[lower] = 1.0 if (weights[layer] < 0.999 and release >= 1.0) else 0.0


## Weights move to their targets; a full layer hides the ones under it.
func _slew(delta: float, targets: Array[float], free: bool) -> void:
	var all := clips()
	for i in LAYERS:
		var clip := all[i]
		var rate := 1.0 / maxf(clip.blend_in if targets[i] > weights[i] else clip.blend_out, 0.01)
		if not free:
			rate = 12.0
		if _tier == 2 and i == 2 and targets[i] > weights[i]:
			rate = 12.0
		# Release (landing, last part): the weight follows its target at once.
		var at_once := _tier > 0 and i == _tier and targets[i] < weights[i]
		weights[i] = targets[i] if at_once else move_toward(weights[i], targets[i], rate * delta)
	for i in range(LAYERS - 1, 0, -1):
		if weights[i] >= 0.999:
			for lower in i:
				weights[lower] = 0.0
	for i in LAYERS:
		if weights[i] <= 0.0 and targets[i] <= 0.0 and not _falling_clip and _tier == 0:
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
