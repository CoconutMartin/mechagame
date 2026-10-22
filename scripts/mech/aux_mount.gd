class_name AuxMount
extends Node
## Holds the devices of the back pack's auxiliary equipment (pulse scan phase): one child per filled
## slot, made by EquipmentData.create_device. Weapon mounts call AuxMount.mount after the weapons.


## Adds an AuxMount with the loadout's equipment devices to mech (nothing without a back pack).
static func mount(mech: Mech, loadout: Loadout) -> AuxMount:
	if mech == null or loadout == null or loadout.back_pack == null:
		return null
	var holder := AuxMount.new()
	holder.name = "AuxMount"
	mech.add_child(holder)
	for i in mini(loadout.aux.size(), loadout.back_pack.aux_slots):
		var item := loadout.aux[i]
		if item != null:
			var device := item.create_device(i + 1)
			if device != null:
				holder.add_child(device)
	return holder


## The first device of a type (for the HUD), or null.
static func find_device(mech: Node, type: Variant) -> Node:
	var holder := mech.get_node_or_null(^"AuxMount") if mech != null else null
	if holder == null:
		return null
	for child in holder.get_children():
		if is_instance_of(child, type):
			return child
	return null
