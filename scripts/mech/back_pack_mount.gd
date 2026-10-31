class_name BackPackMount
extends Node
## Puts the back pack model on the torso back (backpacks, user request 2026-10-31: the back pack takes the FCS
## slot). The model rides the torso bone (BoneAttachment3D), its front face (the model origin, "Mount") on the
## torso armor's back face. The pack gets its own HP part and hit box ("Back Pack"); when it is destroyed the
## model goes and the aux equipment stops. Weapon mounts call BackPackMount.mount after the weapons.
## An ammo pack (BackPackPart.ammo_canisters, user request 2026-10-31: "the canisters are removed 1 by 1 as they are
## used") holds canisters (model nodes Canister1..N); a weapon with no reserve left takes one with take_canister,
## and the empty canister slides out of the pack backward and drops to the ground.

## Hit key of the back pack part.
const HIT_KEY := "Back Pack"

## Bone the pack rides.
@export var bone_name: StringName = &"torso"
## Place of the pack's front face center in mech space at the rest pose (m; +Z = back). From
## tools/godot/measure_back.gd: the torso back face is 1.37 to 1.40 m behind the center, 7.0 to 8.5 m high.
@export var mount_offset: Vector3 = Vector3(0.0, 7.7, 1.43)
## Speed of a used canister leaving the pack, backward (m/s), and how long it lies on the ground (s).
@export var canister_eject_speed: float = 3.0
@export var canister_life: float = 6.0
## Upward speed of a used canister as it leaves (m/s): an upright canister pops out over the ones behind it.
@export var canister_eject_up: float = 2.0
## Collision mask of a dropped canister (the ground and buildings).
@export_flags_3d_physics var canister_mask: int = 1

var mech: Mech
## The pack data.
var pack: BackPackPart
## The model and its bone attachment.
var model: Node3D
var _attach: BoneAttachment3D
## Canisters still in the pack, in the order they are used.
var _canisters: Array[Node3D] = []
var _destroyed: bool = false


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


func _attach_model(skeleton: Skeleton3D, pack_data: BackPackPart) -> void:
	pack = pack_data
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	_attach = BoneAttachment3D.new()
	_attach.name = "BackPackAttachment"
	skeleton.add_child(_attach)
	_attach.bone_name = bone_name
	model = pack_data.scene.instantiate() as Node3D
	model.name = "BackPack"
	_attach.add_child(model)
	# The rest pose places the pack: the bone's rest frame in the world, and the wanted place in the world.
	var bone_rest := skeleton.global_transform * skeleton.get_bone_global_rest(bone)
	var wanted := mech.global_transform * Transform3D(Basis.IDENTITY, mount_offset)
	model.transform = bone_rest.affine_inverse() * wanted
	for i in pack_data.ammo_canisters:
		var canister := model.find_child("Canister%d" % (i + 1), true, false) as Node3D
		if canister != null:
			_canisters.append(canister)
	if mech.health != null:
		var nodes: Array[Node3D] = [model]
		mech.health.attach_weapon_part(HIT_KEY, pack_data.hp, pack_data.hp, nodes)
		mech.health.part_destroyed.connect(_on_part_destroyed)


func _on_part_destroyed(key: String) -> void:
	if key != HIT_KEY:
		return
	_destroyed = true
	_canisters.clear()
	if is_instance_valid(model):
		model.visible = false
	# The aux equipment goes with the pack.
	var aux := mech.get_node_or_null(^"AuxMount")
	if aux != null:
		aux.process_mode = Node.PROCESS_MODE_DISABLED


## Takes one ammo canister from mech's pack for a weapon of this data (false: no ammo pack, none left, the pack is
## destroyed, or its canisters do not fit this weapon, BackPackPart.canister_kinds).
static func take_canister(target: Node, weapon: WeaponData = null) -> bool:
	var holder := target.get_node_or_null(^"BackPackMount") as BackPackMount if target != null else null
	return holder != null and holder.pack.canister_fits(weapon) and holder._take_canister()


## Canisters still in the pack (0 without an ammo pack).
static func canisters_left(target: Node) -> int:
	var holder := target.get_node_or_null(^"BackPackMount") as BackPackMount if target != null else null
	return holder._canisters.size() if holder != null else 0


func _take_canister() -> bool:
	if _destroyed or _canisters.is_empty():
		return false
	_drop(_canisters.pop_front())
	return true


## The used canister leaves the pack backward as a falling body and goes after canister_life seconds.
func _drop(canister: Node3D) -> void:
	if not is_instance_valid(canister):
		return
	var body := RigidBody3D.new()
	body.name = "DroppedCanister"
	body.collision_layer = 0
	body.collision_mask = canister_mask
	body.mass = 0.5
	mech.get_parent().add_child(body)
	body.global_transform = canister.global_transform
	canister.reparent(body, true)
	canister.transform = Transform3D.IDENTITY
	# A box as big as the canister's meshes.
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in canister.find_children("*", "MeshInstance3D", true, false):
		var aabb := (canister.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size.max(Vector3.ONE * 0.1)
	shape.shape = box_shape
	shape.position = box.get_center()
	body.add_child(shape)
	body.linear_velocity = mech.velocity + mech.global_basis.z * canister_eject_speed + Vector3.UP * canister_eject_up
	body.angular_velocity = mech.global_basis.x * randf_range(-1.5, 1.5)
	get_tree().create_timer(canister_life).timeout.connect(body.queue_free)


func _exit_tree() -> void:
	if is_instance_valid(_attach):
		_attach.queue_free()
