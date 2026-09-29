class_name Loadout
extends Resource
## A full mech build: parts, weapons, plates and mods. MechAssembler builds a mech from it.

@export var display_name: String = ""
@export var head: HeadPart
@export var core: CorePart
@export var arm_left: ArmPart
@export var arm_right: ArmPart
@export var legs: LegPart
## Back units are weapons (slot BACK), for example missile pods.
@export var back_left: WeaponData
@export var back_right: WeaponData
@export var booster: BoosterPart
@export var generator: GeneratorPart
@export var fcs: FcsPart
@export var weapon_left: WeaponData
@export var weapon_right: WeaponData
@export var plates: Array[PlateData] = []
@export var mods: Array[ModData] = []


## All parts and weapons that are set, in a fixed order.
func get_parts() -> Array[PartData]:
	var parts: Array[PartData] = []
	for part: PartData in [head, core, arm_left, arm_right, legs, back_left, back_right, booster, generator, fcs, weapon_left, weapon_right]:
		if part != null:
			parts.append(part)
	return parts



## Frame parts (not weapons) with their hit keys, as [key, part] pairs. The generator and FCS sit
## in the core, so hits on them damage the core. The booster (backpack) has its own HP.
func get_part_slots() -> Array:
	var slots := []
	for pair in [["Head", head], ["Core", core], ["Arm L", arm_left], ["Arm R", arm_right], ["Legs", legs],
			["Booster", booster], ["Core", generator], ["Core", fcs]]:
		if pair[1] != null:
			slots.append(pair)
	return slots
