class_name LoadoutSwitcher
extends Node
## Test tool (until the garage in Phase 5): keys 1 to 4 rebuild the player mech with another
## loadout at the same place. The debug HUD follows the new mech.

@export var mech_scene: PackedScene
## Loadouts for keys 1, 2, 3, 4.
@export var loadouts: Array[Loadout] = []
@export var mech: Mech
@export var hud: Node


func _unhandled_input(event: InputEvent) -> void:
	for i in loadouts.size():
		if event.is_action_pressed("loadout_%d" % (i + 1)):
			switch_to(loadouts[i])


func switch_to(loadout: Loadout) -> void:
	var parent := mech.get_parent()
	var place := mech.global_transform
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
	if hud != null and hud.has_method(&"set_mech"):
		hud.set_mech(new_mech)
