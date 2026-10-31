class_name BackPackPart
extends PartData
## A back pack (pulse scan phase, user answer 2026-10-14): it carries auxiliary equipment
## (EquipmentData) in its slots. Slot 1 is used with key X (action aux_1), slot 2 with aux_2.
## Each back pack also gives one bonus in percent (user decision 2026-10-31, replaces the FCS slot).

enum Bonus { NONE, ENERGY, HP, BOOST }

## Number of auxiliary equipment slots.
@export_range(0, 4) var aux_slots: int = 2
## Ammo canisters the pack carries (an ammo pack, user request 2026-10-31); each one is a full magazine for a weapon
## that has no reserve left. The model has one node Canister1..N per canister. 0 = not an ammo pack.
@export_range(0, 12) var ammo_canisters: int = 0
## Weapon kinds the canisters fit (the Missile Pack, user request 2026-10-31: missile pods only). Empty = every
## ammo weapon.
@export var canister_kinds: Array[WeaponData.Kind] = []
## Attack drones (a drone pack, user design 2026-10-31): the model's Drone1..N nodes fly off with key T
## (DroneLauncher). Null = no drones.
@export var drone: DroneData


## True when this pack's canisters fit a weapon of this data (null = any).
func canister_fits(weapon: WeaponData) -> bool:
	return canister_kinds.is_empty() or weapon == null or weapon.kind in canister_kinds
## The stat this back pack improves.
@export var bonus: Bonus = Bonus.NONE
## Size of the bonus in percent (6 = 6% more).
@export var bonus_percent: float = 0.0


## The mod stat the bonus changes, or -1 without a bonus.
func get_mod_stat() -> int:
	match bonus:
		Bonus.ENERGY:
			return ModData.Stat.ENERGY_CAPACITY
		Bonus.HP:
			return ModData.Stat.PART_HP
		Bonus.BOOST:
			return ModData.Stat.BOOST_THRUST
	return -1
