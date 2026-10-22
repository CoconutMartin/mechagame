class_name MechStability
extends Node
## Stagger meter of one mech (user choice 2026-10-16: the arcade stagger spec "B", with the crouch as a
## brace and a stability bar on the target). Each weapon hit adds stagger points (WeaponData
## .stagger_points), scaled by the mech's weight class and by the brace (kneeling). Points from one shot
## (shotgun pellets, a beam's ticks, a missile volley) add up to at most that shot's cap. The meter
## falls after decay_delay seconds with no new points (a slow weapon can hold it longer: stagger_hold_s, so
## its hits still add up between shots). At threshold the mech staggers once (signal
## staggered), the meter goes to 0 and for protection_time seconds new points are ignored (not kept).
## One big shot (knock_points or more from one shot) knocks the mech down instead (signal knocked_down):
## the War Hammer, a full Pile Bunker (user choice 2026-10-17: only big single hits; two Auto Cannon
## hits or two missile volleys at once only fill the meter). Damage is not changed here.
## SkeletalStaggerAnimation adds this node to its mech and plays the clips.

## The mech staggers (the meter reached threshold). from: where the hit came from (Vector3.INF = not known).
signal staggered(from: Vector3)
## The mech takes a knock-down (knock_points within knock_window).
signal knocked_down(from: Vector3)
## Points taken in this hit, after the class and brace scale (the flinch size uses it).
signal hit_taken(points: float, from: Vector3)

## Meter value that staggers the mech.
@export var threshold: float = 100.0
## Seconds after the last points before the meter starts to fall.
@export var decay_delay: float = 1.0
## Points the meter loses per second once it falls.
@export var decay_rate: float = 18.0
## Seconds after a stagger in which new points are ignored (no chain staggers). Damage still applies.
@export var protection_time: float = 1.0
## Part of the threshold the meter keeps after a stagger (0 = empty).
@export_range(0.0, 1.0) var after_stagger_fraction: float = 0.0
## Incoming points scale per weight class: light, medium, heavy.
@export var light_scale: float = 1.25
@export var medium_scale: float = 1.0
@export var heavy_scale: float = 0.65
## Incoming points scale while the mech kneels (the brace; 0.75 = 25% less).
@export_range(0.0, 1.0) var brace_scale: float = 0.75
## Points (after scaling) that knock the mech down instead of a stagger.
@export var knock_points: float = 45.0
## True: only the points of one shot count toward knock_points. False: all hits within knock_window add up.
@export var single_shot_knock: bool = true
## Seconds in which hits add up toward knock_points (only when single_shot_knock is off).
@export var knock_window: float = 0.3

## The mech this meter belongs to (its weight class and kneel). Null: medium, no brace.
var mech: Mech
## Meter now (0 to threshold).
var value: float = 0.0

## Seconds left before the meter starts to fall.
var _hold_left: float = 0.0
var _protection_left: float = 0.0
## Points per shot id this far (for the per-shot caps); entries go after shot_memory seconds.
var _shots: Dictionary = {}
## [time, points] of recent hits for the knock-down window.
var _recent: Array = []
var _clock: float = 0.0
## Seconds a shot id is remembered (longer than any pellet or beam spread of one shot).
const SHOT_MEMORY := 3.0


## The stability meter of what a hit body belongs to (a PartHitbox of a mech), or null.
static func of_body(body: Object) -> MechStability:
	var hitbox := body as PartHitbox
	if hitbox == null or hitbox.health == null:
		return null
	return hitbox.health.stability


## Adds a weapon's stagger points to whatever body a hit landed on (nothing for non-mech bodies).
## shot_id: one number per shot (0 = its own shot); cap: most points that shot gives (0 = no cap).
## hold: seconds the meter keeps these points before it falls (0 = decay_delay; WeaponData.stagger_hold_s).
static func hit_body(body: Object, points: float, shot_id: int = 0, cap: float = 0.0, from: Vector3 = Vector3.INF,
		hold: float = 0.0) -> void:
	var stability := of_body(body)
	if stability != null:
		stability.add_hit(points, shot_id, cap, from, hold)


## A new shot id (pellets of one blast, ticks of one beam, missiles of one volley share it).
static func new_shot_id() -> int:
	return randi() | 1


## Fraction of the meter (0 to 1), for the stability bar.
func get_fraction() -> float:
	return clampf(value / maxf(threshold, 0.001), 0.0, 1.0)


## True during the anti-chain-stagger protection.
func is_protected() -> bool:
	return _protection_left > 0.0


## Scale for this mech: weight class times brace.
func get_scale() -> float:
	var scale := medium_scale
	if mech != null and is_instance_valid(mech):
		match WeightClass.of_mech(mech):
			WeightClass.Class.LIGHT:
				scale = light_scale
			WeightClass.Class.HEAVY:
				scale = heavy_scale
		if mech.kneel != null and mech.kneel.is_kneeling:
			scale *= brace_scale
	return maxf(scale, 0.0)


## Adds the points of one hit. Returns the points added to the meter (after scale and cap).
## hold: seconds before the meter falls (0 = decay_delay). The longest hold still running counts.
func add_hit(points: float, shot_id: int = 0, cap: float = 0.0, from: Vector3 = Vector3.INF, hold: float = 0.0) -> float:
	if not is_finite(points) or points <= 0.0:
		return 0.0
	var scaled := points * get_scale()
	var shot_total := 0.0
	if shot_id != 0:
		var so_far: float = _shots.get(shot_id, [0.0, _clock])[0]
		if cap > 0.0:
			scaled = minf(scaled, maxf(cap * get_scale() - so_far, 0.0))
		shot_total = so_far + scaled
		_shots[shot_id] = [shot_total, _clock]
	else:
		shot_total = scaled
	if scaled <= 0.0:
		return 0.0
	hit_taken.emit(scaled, from)
	if is_protected():
		return 0.0
	_recent.append([_clock, scaled])
	var knock_sum := shot_total
	if not single_shot_knock:
		knock_sum = 0.0
		for entry: Array in _recent:
			if _clock - float(entry[0]) <= knock_window:
				knock_sum += float(entry[1])
	if knock_points > 0.0 and knock_sum >= knock_points:
		_reset_after_stagger()
		knocked_down.emit(from)
		return scaled
	value += scaled
	_hold_left = maxf(_hold_left, maxf(decay_delay, hold) if is_finite(hold) else decay_delay)
	if value >= threshold:
		_reset_after_stagger()
		staggered.emit(from)
	return scaled


## Moves the timers on (decay, protection, memory). Physics frames call it; tests call it directly.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_clock += delta
	_protection_left = maxf(_protection_left - delta, 0.0)
	# Only the time past the hold counts in the frame the hold ends.
	var waiting := minf(delta, _hold_left)
	_hold_left -= waiting
	if delta > waiting:
		value = maxf(value - decay_rate * (delta - waiting), 0.0)
	for id in _shots.keys():
		if _clock - float(_shots[id][1]) > SHOT_MEMORY:
			_shots.erase(id)
	while not _recent.is_empty() and _clock - float(_recent[0][0]) > knock_window:
		_recent.pop_front()


func _physics_process(delta: float) -> void:
	advance(delta)


func _reset_after_stagger() -> void:
	value = clampf(threshold * after_stagger_fraction, 0.0, threshold)
	_protection_left = maxf(protection_time, 0.0)
	_hold_left = maxf(decay_delay, 0.0)
	_recent.clear()
