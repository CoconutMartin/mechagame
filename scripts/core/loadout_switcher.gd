class_name LoadoutSwitcher
extends Node
## Test tool (until the garage in Phase 5): keys 1 to 4 rebuild the player mech with another
## loadout at the same place. The debug HUD follows the new mech. PlayerRespawner uses rebuild().

signal mech_changed(new_mech: Mech)

@export var mech_scene: PackedScene
## Loadouts for keys 1, 2, 3, 4.
@export var loadouts: Array[Loadout] = []
@export var mech: Mech
@export var hud: Node

## The loadout of the mech now.
var current_loadout: Loadout


func _ready() -> void:
	var assembler := mech.get_node_or_null("MechAssembler") as MechAssembler
	current_loadout = assembler.loadout if assembler != null else null
	_mark_player(mech)


## The player mech: enemies look for it (group "player"), and enemy missiles can lock it.
func _mark_player(player: Mech) -> void:
	player.add_to_group(&"player")
	player.add_to_group(&"lockable")


func _unhandled_input(event: InputEvent) -> void:
	for i in loadouts.size():
		if event.is_action_pressed("loadout_%d" % (i + 1)):
			switch_to(loadouts[i])


func switch_to(loadout: Loadout) -> void:
	rebuild(loadout, mech.global_transform)


## Replaces the player mech with a new one built from loadout, at place. A loadout with its own mech
## scene (a skeletal mech) uses that scene; the others are built from parts by MechAssembler.
func rebuild(loadout: Loadout, place: Transform3D) -> void:
	var parent := mech.get_parent()
	var index := mech.get_index()
	var scene := loadout.mech_scene if loadout.mech_scene != null else mech_scene
	var new_mech := scene.instantiate() as Mech
	var assembler := new_mech.get_node_or_null("MechAssembler") as MechAssembler
	if assembler != null:
		assembler.loadout = loadout
	new_mech.name = mech.name
	mech.name = "OldMech"
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
