class_name MechStability
extends Node
## Stagger meter of one mech (user choice 2026-10-16: the arcade stagger spec "B", with the crouch as a
## brace and a stability bar on the target). Each weapon hit adds stagger points (WeaponData
## .stagger_points), scaled by the mech's weight class and by the brace (kneeling). Points from one shot
## (shotgun pellets, a beam's ticks, a missile volley) add up to at most that shot's cap. The meter
## falls after decay_delay seconds with no new points. At threshold the mech staggers once (signal
## staggered), the meter goes to 0 and for protection_time seconds new points are ignored (not kept).
## Many points in a short time (knock_points within knock_window) knock the mech down instead (signal
## knocked_down): the War Hammer, a full Pile Bunker, two missile pods. Damage is not changed here.
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
## Points (after scaling) within knock_window seconds that knock the mech down instead of a stagger.
@export var knock_points: float = 45.0
@export var knock_window: float = 0.3

## The mech this meter belongs to (its weight class and kneel). Null: medium, no brace.
var mech: Mech
## Meter now (0 to threshold).
var value: float = 0.0

var _since_points: float = 0.0
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
static func hit_body(body: Object, points: float, shot_id: int = 0, cap: float = 0.0, from: Vector3 = Vector3.INF) -> void:
	var stability := of_body(body)
	if stability != null:
		stability.add_hit(points, shot_id, cap, from)


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
func add_hit(points: float, shot_id: int = 0, cap: float = 0.0, from: Vector3 = Vector3.INF) -> float:
	if not is_finite(points) or points <= 0.0:
		return 0.0
	var scaled := points * get_scale()
	if shot_id != 0 and cap > 0.0:
		var scaled_cap := cap * get_scale()
		var so_far: float = _shots.get(shot_id, [0.0, _clock])[0]
		scaled = minf(scaled, maxf(scaled_cap - so_far, 0.0))
		_shots[shot_id] = [so_far + scaled, _clock]
	if scaled <= 0.0:
		return 0.0
	hit_taken.emit(scaled, from)
	if is_protected():
		return 0.0
	_recent.append([_clock, scaled])
	var window_sum := 0.0
	for entry: Array in _recent:
		if _clock - float(entry[0]) <= knock_window:
			window_sum += float(entry[1])
	if knock_points > 0.0 and window_sum >= knock_points:
		_reset_after_stagger()
		knocked_down.emit(from)
		return scaled
	value += scaled
	_since_points = 0.0
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
	_since_points += delta
	if _since_points > decay_delay:
		# Only the time past the delay counts in the frame the delay ends.
		var falling := minf(delta, _since_points - decay_delay)
		value = maxf(value - decay_rate * falling, 0.0)
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
	_since_points = 0.0
	_recent.clear()
