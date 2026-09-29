class_name PlateMounter
extends RefCounted
## Adds the armor plates of a loadout to the frame as armor slabs (Phase 5). Each part has three
## plate places; the first plate of a slot goes to place 0, the second to place 1, the third to
## place 2 (more plates add HP and weight but no slab). Legs plates cover both legs.
## A place: [socket, surface point, outward normal, face size (the normal axis is 0)], in the
## socket space of the Warden frame. "S" in a socket name is the side (L or R); x is mirrored.

const MATERIAL := preload("res://materials/warden/armor_dark.tres")
const MAX_PLATES := 3

const HEAD := [
	["Torso", Vector3(0.0, 3.72, -0.45), Vector3.UP, Vector3(1.0, 0.0, 1.15)],
	["Torso", Vector3(-0.66, 3.1, -0.5), Vector3.LEFT, Vector3(0.0, 0.75, 1.1)],
	["Torso", Vector3(0.66, 3.1, -0.5), Vector3.RIGHT, Vector3(0.0, 0.75, 1.1)],
]
const CORE := [
	["Torso", Vector3(0.0, 1.45, -0.92), Vector3.FORWARD, Vector3(1.4, 0.7, 0.0)],
	["Torso", Vector3(-1.23, 2.75, -1.17), Vector3.FORWARD, Vector3(0.9, 0.7, 0.0)],
	["Torso", Vector3(1.23, 2.75, -1.17), Vector3.FORWARD, Vector3(0.9, 0.7, 0.0)],
]
## Right side values (x positive = out). The left side mirrors x.
const ARM := [
	["ShoulderS", Vector3(0.47, -1.25, 0.0), Vector3.RIGHT, Vector3(0.0, 0.95, 0.85)],
	["ElbowS", Vector3(0.51, -1.1, 0.0), Vector3.RIGHT, Vector3(0.0, 1.35, 0.95)],
	["ElbowS", Vector3(0.0, -1.0, -0.555), Vector3.FORWARD, Vector3(0.85, 1.25, 0.0)],
]
const LEG := [
	["KneeS", Vector3(0.0, -1.05, -1.29), Vector3.FORWARD, Vector3(1.05, 1.3, 0.0)],
	["HipS", Vector3(0.0, -1.95, -0.84), Vector3.FORWARD, Vector3(1.2, 0.85, 0.0)],
	["KneeS", Vector3(0.87, -1.15, 0.05), Vector3.RIGHT, Vector3(0.0, 1.35, 1.5)],
]


## Adds the slabs. Returns the added nodes by hit key ("Head", "Core", "Arm L", "Arm R", "Legs").
static func mount(frame: Node3D, loadout: Loadout) -> Dictionary:
	var added := {}
	var used := {}
	for plate in loadout.plates:
		var index: int = used.get(plate.slot, 0)
		used[plate.slot] = index + 1
		if index >= MAX_PLATES:
			continue
		var key := _key(plate.slot)
		var part := _part(loadout, plate.slot)
		var nodes: Array[Node3D] = []
		for place in _places(plate.slot, index):
			var slab := _slab(frame, place, plate.thickness)
			if slab != null:
				nodes.append(slab)
		if part != null:
			PartLook.apply(nodes, part.model_scale, part.armor_tint)
		var list: Array[Node3D] = added.get(key, [] as Array[Node3D])
		list.append_array(nodes)
		added[key] = list
	return added


## Places for one plate: one for most slots, one per leg for the legs.
static func _places(slot: PlateData.Slot, index: int) -> Array:
	match slot:
		PlateData.Slot.HEAD:
			return [HEAD[index]]
		PlateData.Slot.CORE:
			return [CORE[index]]
		PlateData.Slot.ARM_LEFT:
			return [_side(ARM[index], "L")]
		PlateData.Slot.ARM_RIGHT:
			return [_side(ARM[index], "R")]
		_:
			return [_side(LEG[index], "L"), _side(LEG[index], "R")]


## A right-side place for the side "L" or "R" (x mirrored on the left).
static func _side(place: Array, side: String) -> Array:
	var flip := Vector3(-1.0, 1.0, 1.0) if side == "L" else Vector3.ONE
	return [(place[0] as String).replace("S", side), place[1] * flip, place[2] * flip, place[3]]


static func _slab(frame: Node3D, place: Array, thickness: float) -> Node3D:
	var socket := frame.find_child(place[0], true, false) as Node3D
	if socket == null:
		return null
	var normal: Vector3 = place[2]
	var face: Vector3 = place[3]
	var mesh := MeshInstance3D.new()
	mesh.name = "Plate"
	var box := BoxMesh.new()
	box.size = face + normal.abs() * thickness
	mesh.mesh = box
	mesh.material_override = MATERIAL
	socket.add_child(mesh)
	mesh.position = (place[1] as Vector3) + normal * thickness * 0.5
	return mesh


static func _key(slot: PlateData.Slot) -> String:
	return ["Head", "Core", "Arm L", "Arm R", "Legs"][slot]


static func _part(loadout: Loadout, slot: PlateData.Slot) -> PartData:
	return [loadout.head, loadout.core, loadout.arm_left, loadout.arm_right, loadout.legs][slot]
