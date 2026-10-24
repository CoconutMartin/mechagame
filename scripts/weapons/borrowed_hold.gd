class_name BorrowedHold
extends RefCounted
## A two-hand weapon held with another weapon's arm and hand places (user request 2026-10-24: the Beam Sniper
## with 2 shoulder Auto Cannons is held like the Beam Rifle, so the cannons, which turn with the upper arms,
## stay upright). The weapon shifts in its own space by `shift` (the source's right grip socket minus its own),
## so its own right grip socket lands on the source's; its other hand markers and sockets move to the source's
## places minus the shift. The right socket keeps its own turn and radius (it is on this weapon's grip mesh).
## WeaponController uses rest_transform for the rest pose and WeaponPose.aim_shift for the aim pose.

## Hand markers and sockets copied from the source (made on the weapon when it has none).
const MARKERS: PackedStringArray = ["GripRight", "GripRightRest", "GripRightAim", "GripLeft", "GripLeftRest",
		"GripLeftAim", "GripLeftAimLow", "GripSocketLeft", "GripSocketLeftAim", "GripSocketLeftAimLow"]
const RIGHT_SOCKET := "GripSocketRight"

## Weapon-space shift of the weapon (source right socket minus own right socket).
var shift: Vector3 = Vector3.ZERO
## The rest pose (torso space, before the arm's hold offset).
var rest_transform: Transform3D = Transform3D.IDENTITY
## The aim anchor (torso space, before the arm's hold offset).
var aim_anchor: Vector3 = Vector3.ZERO


## Moves the weapon's hand markers to the source's places and returns the hold, or null when a socket is missing.
static func apply(weapon: Node3D, source: WeaponData) -> BorrowedHold:
	if weapon == null or source == null or source.scene == null:
		return null
	var model := source.scene.instantiate() as Node3D
	var source_socket := model.get_node_or_null(RIGHT_SOCKET) as Node3D
	var own_socket := weapon.get_node_or_null(RIGHT_SOCKET) as Node3D
	if source_socket == null or own_socket == null:
		model.free()
		return null
	var hold := BorrowedHold.new()
	hold.shift = source_socket.position - own_socket.position
	for marker_name in MARKERS:
		var from := model.get_node_or_null(NodePath(marker_name)) as Node3D
		if from == null:
			continue
		var to := weapon.get_node_or_null(NodePath(marker_name)) as Node3D
		if to == null:
			to = Marker3D.new()
			to.name = marker_name
			weapon.add_child(to)
		to.transform = Transform3D(from.basis, from.position - hold.shift)
		for key in from.get_meta_list():
			to.set_meta(key, from.get_meta(key))
	hold.rest_transform = source.rest_transform.translated_local(hold.shift)
	hold.aim_anchor = source.aim_anchor
	model.free()
	return hold
