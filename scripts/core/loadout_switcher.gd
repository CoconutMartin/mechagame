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
	current_loadout = (mech.get_node("MechAssembler") as MechAssembler).loadout
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


## Replaces the player mech with a new one built from loadout, at place.
func rebuild(loadout: Loadout, place: Transform3D) -> void:
	var parent := mech.get_parent()
	var index := mech.get_index()
	var new_mech := mech_scene.instantiate() as Mech
	(new_mech.get_node("MechAssembler") as MechAssembler).loadout = loadout
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
