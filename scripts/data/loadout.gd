class_name Loadout
extends Resource
## A full mech build: parts, weapons and mods. MechAssembler builds a mech from it.

@export var display_name: String = ""
## Mech scene for this loadout, for a mech that is not built from parts (a rigged, skeletal-animation
## mech). Empty: the part-built player mech of the LoadoutSwitcher.
@export var mech_scene: PackedScene
@export var head: HeadPart
@export var core: CorePart
@export var arm_left: ArmPart
@export var arm_right: ArmPart
@export var legs: LegPart
## Back units are weapons (slot BACK), for example missile pods.
@export var back_left: WeaponData
@export var back_right: WeaponData
@export var booster: BoosterPart
## Back pack with auxiliary equipment slots (pulse scan phase). aux[0] goes in slot 1 (key X).
@export var back_pack: BackPackPart
@export var aux: Array[EquipmentData] = []
@export var generator: GeneratorPart
@export var weapon_left: WeaponData
@export var weapon_right: WeaponData
@export var mods: Array[ModData] = []


## All parts and weapons that are set, in a fixed order.
func get_parts() -> Array[PartData]:
	var parts: Array[PartData] = []
	for part: PartData in [head, core, arm_left, arm_right, legs, back_left, back_right, booster, generator, weapon_left, weapon_right]:
		if part != null:
			parts.append(part)
	if back_pack != null:
		parts.append(back_pack)
		for item in get_aux():
			parts.append(item)
	return parts


## The equipment the back pack can hold: aux, cut to its slot count (none without a back pack).
func get_aux() -> Array[EquipmentData]:
	var items: Array[EquipmentData] = []
	if back_pack == null:
		return items
	for i in mini(aux.size(), back_pack.aux_slots):
		if aux[i] != null:
			items.append(aux[i])
	return items



## Frame parts (not weapons) with their hit keys, as [key, part] pairs. The generator sits
## in the core, so hits on them damage the core. The booster (backpack) has its own HP.
func get_part_slots() -> Array:
	var slots := []
	for pair in [["Head", head], ["Core", core], ["Arm L", arm_left], ["Arm R", arm_right], ["Legs", legs],
			["Booster", booster], ["Core", generator]]:
		if pair[1] != null:
			slots.append(pair)
	return slots
