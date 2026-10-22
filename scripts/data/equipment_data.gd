class_name EquipmentData
extends PartData
## Base data for auxiliary equipment in a back pack slot (BackPackPart). Subclasses make the node that
## does the work on the mech (create_device).

## Equipment grade: 1 (basic) to 3 (best). Grades are not in the rest of the game yet.
@export_range(1, 3) var grade: int = 1


## The node that runs this equipment on a mech. slot: 1-based back pack slot (input action aux_<slot>).
func create_device(_slot: int) -> Node:
	return null
