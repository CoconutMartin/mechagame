class_name DroneModData
extends EquipmentData
## A drone aux mod (user design 2026-10-31: "the backpack can equip an auxiliary mod that could either (a) double
## drone usage (the drone comes back and can be relaunched) or (b) launch all drones simultaneously (all drones get
## destroyed after)"). Aux equipment: it takes the back pack's aux slot, in place of a pulse scan (user: "aux mods
## are not fixed and interchangeable", back packs keep 1 aux slot). DroneLauncher reads it at each launch.

enum Kind {
	## (a) Each drone flies its attack, comes back to its dock, and can launch again (flights_per_drone in all).
	RECALL,
	## (b) One launch sends every drone on the pack; they are all destroyed after.
	SWARM,
}

@export var kind: Kind = Kind.RECALL
## RECALL: attack flights per drone (2 = double use). A drone shot down is gone.
@export_range(1, 4) var flights_per_drone: int = 2


func create_device(slot: int) -> Node:
	var device := DroneMod.new()
	device.data = self
	device.slot = slot
	return device
