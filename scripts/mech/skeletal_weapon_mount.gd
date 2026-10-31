class_name SkeletalWeaponMount
extends Node
## Mounts the loadout weapons on a rigged (skeletal) mech. It does the weapon part of MechAssembler:
## weapon and shield scenes go onto the weapon frame of SkeletalArmRig (Torso, ShoulderL/R,
## ElbowL/R). The mech keeps its own body and speeds. The loadout parts (with mods) give
## the part HP: mech.stats is set here, before MechHealth starts (keep this node before it).
## Keep this node before the weapon nodes, so the weapons exist before the others start.

@export var loadout: Loadout
## The weapon frame (the Torso node of SkeletalArmRig and its children are the sockets).
@export var frame: Node3D
@export var weapon_controller: WeaponController
## Shoulder mounts (left, right): back weapons (Q, E) sit on top of the shoulders, their lowest point
## on the mount (user rule 2026-10-11: the top of the shoulder is the mount of every shoulder weapon).
@export var shoulder_mounts: Array[Node3D] = []


func _ready() -> void:
	var mech := get_parent() as Mech
	if loadout != null and loadout.head != null and mech != null:
		mech.stats = StatCalculator.compute(loadout)
	if loadout != null and weapon_controller != null:
		weapon_controller.mount(loadout, attach)
		_to_shoulders()
	if mech != null:
		AuxMount.mount.call_deferred(mech, loadout)
		BackPackMount.mount.call_deferred(mech, loadout)


func _to_shoulders() -> void:
	var backs := [weapon_controller.back_left, weapon_controller.back_right]
	for i in mini(backs.size(), shoulder_mounts.size()):
		var weapon := backs[i] as Node3D
		if weapon == null or shoulder_mounts[i] == null:
			continue
		weapon.reparent(shoulder_mounts[i], false)
		weapon.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -_lowest_point(weapon), 0.0))


## Lowest mesh point of a node, in its own space.
static func _lowest_point(root: Node3D) -> float:
	var lowest := INF
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue  # effects (muzzle flash)
		var box := (root.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return 0.0 if lowest == INF else lowest


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
