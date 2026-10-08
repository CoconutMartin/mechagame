class_name MechAssembler
extends Node
## Builds the mech from a Loadout when the mech starts.
## 0. MechFrameApplier moves the frame joints to the joint layout of the parts (MechFrame).
## 1. Each part model is a scene (a generated .tscn or a Blender .glb). Its child groups have the
##    names of frame nodes (the sockets, for example Torso, ShoulderL, ElbowL, Lower, HipL, KneeL; a
##    Blender model may add "_part" to the name). The children of each group move to the frame node
##    with the same name, with their local transforms. PartRigging gives imported nodes their roles.
## 2. Part variants get their look (PartLook) and the armor plates are added (PlateMounter).
## 3. StatCalculator computes the final stats and MechStatApplier sets them on the mech.
## Keep this node before Visual and the logic nodes, so the parts exist before the others start.

@export var loadout: Loadout
@export var mech: Mech
## The frame: the skeleton with the socket nodes.
@export var frame: Node3D
## Optional. Mounts the loadout weapons.
@export var weapon_controller: WeaponController

## Nodes each part added to the frame, by hit key (see Loadout.get_part_slots). MechHealth builds
## the hitboxes from them and PartBreaker drops them when the part is destroyed.
var part_nodes: Dictionary = {}


func _ready() -> void:
	if loadout == null:
		return
	MechFrameApplier.apply(mech, frame, loadout)
	for pair in loadout.get_part_slots():
		var key: String = pair[0]
		var part: PartData = pair[1]
		if part.scene != null:
			var added := attach(part.scene)
			PartRigging.rig(added, part.material_library)
			PartLook.apply(added, part.model_scale, part.armor_tint)
			var nodes: Array[Node3D] = part_nodes.get(key, [] as Array[Node3D])
			nodes.append_array(added)
			part_nodes[key] = nodes
	# Armor plates (Phase 5): slabs on the parts. They break and fall with their part.
	var plates := PlateMounter.mount(frame, loadout)
	for key: String in plates:
		var nodes: Array[Node3D] = part_nodes.get(key, [] as Array[Node3D])
		nodes.append_array(plates[key])
		part_nodes[key] = nodes
	if weapon_controller != null:
		weapon_controller.mount(loadout, self)
	var torso_pose := mech.find_child("TorsoPose", true, false) as TorsoPose
	if torso_pose != null and loadout.legs is LegPart:
		torso_pose.walk_lean_deg = (loadout.legs as LegPart).walk_lean_deg
	var stats := StatCalculator.compute(loadout)
	MechStatApplier.apply(stats, mech)


## Adds one part model to the frame. Returns the nodes it added.
func attach(scene: PackedScene) -> Array[Node3D]:
	var added: Array[Node3D] = []
	var model := scene.instantiate()
	for group in model.get_children():
		# A Blender model names its socket empties "Torso_head", "Torso_core"... (object names must be
		# unique there): the socket is the name before the first "_" or ".".
		var socket_name := String(group.name).get_slice("_", 0).get_slice(".", 0)
		var socket := frame.find_child(socket_name, true, false) as Node3D
		if socket == null:
			push_warning("MechAssembler: no socket named %s for %s" % [group.name, scene.resource_path])
			continue
		for child in group.get_children():
			group.remove_child(child)
			_clear_owner(child)
			socket.add_child(child)
			if child is Node3D:
				added.append(child)
	model.free()
	return added


## The moved nodes leave the part scene, so they must not keep it as their owner.
func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)
