class_name MechStats
extends RefCounted
## Final mech stats from StatCalculator.

var total_weight_t: float = 0.0
var load_capacity_t: float = 0.0
var load_ratio: float = 0.0
## Speed factor from the weight formula (walk speed / legs base speed).
var weight_factor: float = 1.0
var walk_speed: float = 0.0
var boost_speed_multiplier: float = 1.5
var boost_acceleration: float = 0.0
var boost_energy_per_second: float = 0.0
var torso_turn_speed_deg: float = 0.0
var leg_turn_speed_deg: float = 0.0
var leg_turn_speed_standing_deg: float = 0.0
var jump_height: float = 0.0
var energy_capacity: float = 0.0
var energy_output: float = 0.0
var recharge_delay: float = 0.0
var recoil_multiplier: float = 1.0
## Head lock-on speed (the lock range and max locks are in WeaponData).
var lock_on_speed: float = 1.0
## Auxiliary equipment slots of the back pack (0 without a back pack).
var aux_slots: int = 0
## Max HP of each part (with mods). Keys: "Head", "Core", "Arm L", "Arm R", "Legs".
var part_hp: Dictionary = {}
