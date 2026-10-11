class_name SkeletalWeaponMount
extends Node
## Mounts the loadout weapons on a rigged (skeletal) mech. It does the weapon part of MechAssembler:
## weapon and shield scenes go onto the weapon frame of SkeletalArmRig (Torso, ShoulderL/R,
## ElbowL/R). The mech keeps its own body and speeds (the loadout parts are not used).
## Keep this node before the weapon nodes, so the weapons exist before the others start.

@export var loadout: Loadout
## The weapon frame (the Torso node of SkeletalArmRig and its children are the sockets).
@export var frame: Node3D
@export var weapon_controller: WeaponController


func _ready() -> void:
	if loadout != null and weapon_controller != null:
		weapon_controller.mount(loadout, attach)


## Adds a socket-group scene (the shield) to the frame, like MechAssembler.attach().
func attach(scene: PackedScene) -> Array[Node3D]:
	var added: Array[Node3D] = []
	var model := scene.instantiate()
	for group in model.get_children():
		var socket_name := String(group.name).get_slice("_", 0).get_slice(".", 0)
		var socket := frame if frame.name == socket_name else frame.find_child(socket_name, true, false) as Node3D
		if socket == null:
			push_warning("SkeletalWeaponMount: no socket named %s for %s" % [group.name, scene.resource_path])
			continue
		for child in group.get_children():
			group.remove_child(child)
			_clear_owner(child)
			socket.add_child(child)
			if child is Node3D:
				added.append(child)
	model.free()
	return added


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)
