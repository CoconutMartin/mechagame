class_name BackPackMount
extends Node
## Puts the back pack model on the torso back (backpacks, user request 2026-10-31: the back pack takes the FCS
## slot). The model rides the torso bone (BoneAttachment3D), its front face (the model origin, "Mount") on the
## torso armor's back face. The pack gets its own HP part and hit box ("Back Pack"); when it is destroyed the
## model goes and the aux equipment stops. Weapon mounts call BackPackMount.mount after the weapons.

## Hit key of the back pack part.
const HIT_KEY := "Back Pack"

## Bone the pack rides.
@export var bone_name: StringName = &"torso"
## Place of the pack's front face center in mech space at the rest pose (m; +Z = back). From
## tools/godot/measure_back.gd: the torso back face is 1.37 to 1.40 m behind the center, 7.0 to 8.5 m high.
@export var mount_offset: Vector3 = Vector3(0.0, 7.7, 1.43)

var mech: Mech
## The model and its bone attachment.
var model: Node3D
var _attach: BoneAttachment3D


## Adds a BackPackMount with the loadout's back pack model to mech (nothing without a pack or a model).
static func mount(target: Mech, loadout: Loadout) -> BackPackMount:
	if target == null or loadout == null or loadout.back_pack == null or loadout.back_pack.scene == null:
		return null
	var skeleton := target.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var holder := BackPackMount.new()
	holder.name = "BackPackMount"
	holder.mech = target
	target.add_child(holder)
	holder._attach_model(skeleton, loadout.back_pack)
	return holder


func _attach_model(skeleton: Skeleton3D, pack: BackPackPart) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	_attach = BoneAttachment3D.new()
	_attach.name = "BackPackAttachment"
	skeleton.add_child(_attach)
	_attach.bone_name = bone_name
	model = pack.scene.instantiate() as Node3D
	model.name = "BackPack"
	_attach.add_child(model)
	# The rest pose places the pack: the bone's rest frame in the world, and the wanted place in the world.
	var bone_rest := skeleton.global_transform * skeleton.get_bone_global_rest(bone)
	var wanted := mech.global_transform * Transform3D(Basis.IDENTITY, mount_offset)
	model.transform = bone_rest.affine_inverse() * wanted
	if mech.health != null:
		var nodes: Array[Node3D] = [model]
		mech.health.attach_weapon_part(HIT_KEY, pack.hp, pack.hp, nodes)
		mech.health.part_destroyed.connect(_on_part_destroyed)


func _on_part_destroyed(key: String) -> void:
	if key != HIT_KEY:
		return
	if is_instance_valid(model):
		model.visible = false
	# The aux equipment goes with the pack.
	var aux := mech.get_node_or_null(^"AuxMount")
	if aux != null:
		aux.process_mode = Node.PROCESS_MODE_DISABLED


func _exit_tree() -> void:
	if is_instance_valid(_attach):
		_attach.queue_free()
