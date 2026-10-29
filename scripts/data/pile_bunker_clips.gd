class_name PileBunkerClips
extends Resource
## The Pile Bunker punch clips by number (user request 2026-10-29: "bind each animation to a number 1 - 5", for more
## Pile Bunker weapons): slot n (1 to 5) is entry n - 1. A Pile Bunker picks one with PileBunkerWeapon.clip_number;
## Shift + 1 to 5 switches the player's Pile Bunker clip in play (tests). An empty slot (null) plays the coded punch.

## Names for the HUD, one per slot.
@export var names: PackedStringArray = []
## Right hand clips, one per slot.
@export var right: Array[MeleeAttack] = []
## Left hand clips (mirrored), one per slot.
@export var left: Array[MeleeAttack] = []


## The clip of slot number (1 to 5) for a hand, or null.
func get_clip(number: int, is_left: bool) -> MeleeAttack:
	var list := left if is_left else right
	var index := number - 1
	return list[index] if index >= 0 and index < list.size() else null


## The name of slot number, or "".
func get_clip_name(number: int) -> String:
	var index := number - 1
	return names[index] if index >= 0 and index < names.size() else ""
