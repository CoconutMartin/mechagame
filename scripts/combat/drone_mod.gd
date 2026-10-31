class_name DroneMod
extends Node
## The device of a drone aux mod (DroneModData) in a back pack slot. It does nothing by itself: DroneLauncher finds
## it (AuxMount.find_device) and reads its data at each launch. Without a drone pack it has no effect.

var data: DroneModData
## Back pack slot, 1-based.
var slot: int = 1


func _ready() -> void:
	name = "DroneMod%d" % slot


## The drone mod on mech's back pack, or null.
static func find_data(mech: Node) -> DroneModData:
	var device := AuxMount.find_device(mech, DroneMod) as DroneMod
	return device.data if device != null else null
