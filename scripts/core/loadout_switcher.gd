class_name LoadoutSwitcher
extends Node
## Rebuilds the player mech with another loadout at the same place. The garage and PlayerRespawner use rebuild(); no number key
## picks a mech (user 2026-11-06). The debug HUD follows the new mech.

signal mech_changed(new_mech: Mech)

## Mech scene for loadouts without their own mech_scene.
@export var mech_scene: PackedScene
## Loadouts the test tools switch to (tools/godot).
@export var loadouts: Array[Loadout] = []
@export var mech: Mech
@export var hud: Node

## The loadout of the mech now.
var current_loadout: Loadout


func _ready() -> void:
	var builder := loadout_node(mech)
	current_loadout = builder.loadout if builder != null else null
	_mark_player(mech)


## The node that takes the loadout: MechAssembler (part-built mech) or WeaponMount (rigged mech).
static func loadout_node(of_mech: Node) -> Node:
	var node := of_mech.get_node_or_null("MechAssembler")
	return node if node != null else of_mech.get_node_or_null("WeaponMount")


## The player mech: enemies look for it (group "player"), and enemy missiles can lock it.
func _mark_player(player: Mech) -> void:
	player.add_to_group(&"player")
	player.add_to_group(&"lockable")


func switch_to(loadout: Loadout) -> void:
	rebuild(loadout, mech.global_transform)


## Replaces the player mech with a new one built from loadout, at place. The legs part picks the mech scene (its rig);
## else the loadout's own mech scene, else mech_scene. A part-built mech scene gets the loadout in its
## MechAssembler; a rigged mech scene (the new mech) gets it in its WeaponMount (weapons only).
func rebuild(loadout: Loadout, place: Transform3D) -> void:
	var parent := mech.get_parent()
	var index := mech.get_index()
	var scene := loadout.mech_scene if loadout.mech_scene != null else mech_scene
	if loadout.legs != null and not loadout.legs.mech_scene_path.is_empty():
		scene = load(loadout.legs.mech_scene_path) as PackedScene
	var new_mech := scene.instantiate() as Mech
	var builder := loadout_node(new_mech)
	if builder != null:
		builder.set(&"loadout", loadout)
	new_mech.name = mech.name
	mech.name = "OldMech"
	mech.leave_mech_layer()
	mech.queue_free()
	parent.add_child(new_mech)
	parent.move_child(new_mech, index)
	new_mech.global_transform = place
	mech = new_mech
	_mark_player(new_mech)
	current_loadout = loadout
	if hud != null and hud.has_method(&"set_mech"):
		hud.set_mech(new_mech)
	mech_changed.emit(new_mech)
