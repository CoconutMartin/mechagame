class_name MechLegStrain
extends Node
## A heavily compromised leg (a leg part at or below compromised_fraction of its max HP) cannot take
## hard moves (user request 2026-10-15):
##   A dodge roll costs that leg roll_damage_fraction of its max HP (absolute points of max HP:
##   10% -> 8%) and the roll goes roll_speed_factor as fast.
##   A landing from a fall costs it up to landing_damage_fraction of its max HP: nothing below
##   landing_min_height, then a straight line up to the full amount at the top jump height.
## The damage uses hit kind &"environment": the hit reaction treats it as a weak flinch (4%) and the
## stagger rules count 4% of it, so a strain never plays a big hit clip or a stun. While a dodge plays
## the hit reaction stays out anyway.
## MechDodge makes this node (it needs no scene wiring) and calls strain_roll(). It listens to
## MechLandingRecovery for the landings.

const LEG_KEYS: Array[String] = ["Leg L", "Leg R"]

@export var mech: Mech
## A leg is heavily compromised at or below this fraction of its max HP.
@export_range(0.0, 1.0) var compromised_fraction: float = 0.10
## HP lost by each heavily compromised leg per dodge roll, as a fraction of its max HP.
@export_range(0.0, 1.0) var roll_damage_fraction: float = 0.02
## HP lost by each heavily compromised leg at a landing from the top jump height, as a fraction of its
## max HP.
@export_range(0.0, 1.0) var landing_damage_fraction: float = 0.02
## Falls lower than this (meters) cost nothing.
@export var landing_min_height: float = 1.0
## Fall height (meters) with the full landing damage. 0 = the top jump height (MechJumpCharge.full_height).
@export var landing_full_height: float = 0.0
## Roll speed multiplier while a leg is heavily compromised (0.5 = 50% lower).
@export_range(0.05, 1.0) var roll_speed_factor: float = 0.5
## False: a strain never destroys the leg (it stops at 1 HP). True: it can break the leg.
@export var can_destroy_leg: bool = false


func _ready() -> void:
	if mech != null and mech.landing_recovery != null:
		mech.landing_recovery.fall_landed.connect(strain_landing)


## True when at least one leg is alive and at or below compromised_fraction of its max HP.
func is_compromised() -> bool:
	for key in LEG_KEYS:
		if is_leg_compromised(key):
			return true
	return false


func is_leg_compromised(key: String) -> bool:
	var health := mech.health if mech != null else null
	if health == null or not health.max_hp.has(key) or not health.hp.has(key):
		return false
	var current: float = health.hp[key]
	var maximum: float = health.max_hp[key]
	return current > 0.0 and maximum > 0.0 and current <= maximum * compromised_fraction + 0.0001


## Multiplier for the roll's ground speed: roll_speed_factor while a leg is heavily compromised.
func get_roll_speed_factor() -> float:
	return roll_speed_factor if is_compromised() else 1.0


## A dodge roll starts: each heavily compromised leg loses roll_damage_fraction of its max HP.
func strain_roll() -> void:
	_hurt_legs(roll_damage_fraction)


## A landing from a fall of this many meters: each heavily compromised leg loses a part of
## landing_damage_fraction of its max HP (see get_landing_scale).
func strain_landing(height: float) -> void:
	_hurt_legs(landing_damage_fraction * get_landing_scale(height))


## 0 to 1: the share of the full landing damage for this fall height (0 below landing_min_height,
## 1 at the top jump height, a straight line between).
func get_landing_scale(height: float) -> float:
	var full := landing_full_height
	if full <= 0.0:
		full = mech.jump_charge.full_height if mech != null and mech.jump_charge != null else 9.0
	return clampf(inverse_lerp(landing_min_height, maxf(full, landing_min_height + 0.01), height), 0.0, 1.0)


func _hurt_legs(fraction: float) -> void:
	if fraction <= 0.0 or mech == null or mech.health == null:
		return
	# Check both legs first: a hurt leg must not change which legs count.
	var hurt: Array[String] = []
	for key in LEG_KEYS:
		if is_leg_compromised(key):
			hurt.append(key)
	for key in hurt:
		var amount: float = mech.health.max_hp[key] * fraction
		if not can_destroy_leg:
			amount = minf(amount, mech.health.hp[key] - 1.0)
		if amount > 0.0:
			mech.health.damage(key, amount, Vector3.INF, &"environment")
