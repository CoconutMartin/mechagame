class_name MechAssembler
extends Node
## Builds the mech from a Loadout when the mech starts.
## 1. Each part model is a scene. Its child groups have the names of frame nodes (the sockets,
##    for example Torso, ShoulderL, ElbowL, Lower, HipL, KneeL). The children of each group move
##    to the frame node with the same name, with their local transforms.
## 2. StatCalculator computes the final stats and MechStatApplier sets them on the mech.
## Keep this node before Visual and the logic nodes, so the parts exist before the others start.

@export var loadout: Loadout
@export var mech: Mech
## The frame: the skeleton with the socket nodes.
@export var frame: Node3D
## Optional. Mounts the loadout weapons.
@export var weapon_controller: WeaponController


func _ready() -> void:
	if loadout == null:
		return
	for part in loadout.get_parts():
		if part.scene != null and not part is WeaponData:
			attach(part.scene)
	if weapon_controller != null:
		weapon_controller.mount(loadout, self)
	var stats := StatCalculator.compute(loadout)
	MechStatApplier.apply(stats, mech)


## Adds one part model to the frame.
func attach(scene: PackedScene) -> void:
	var model := scene.instantiate()
	for group in model.get_children():
		var socket := frame.find_child(group.name, true, false) as Node3D
		if socket == null:
			push_warning("MechAssembler: no socket named %s for %s" % [group.name, scene.resource_path])
			continue
		for child in group.get_children():
			group.remove_child(child)
			_clear_owner(child)
			socket.add_child(child)
	model.free()


## The moved nodes leave the part scene, so they must not keep it as their owner.
func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)
