class_name PlayerRespawner
extends Node
## When the player mech is destroyed (dead), waits respawn_time, then builds it again with full HP at the
## start point (same loadout). The enemies reset too (MechSpawner listens to respawned).

signal respawned

@export var switcher: LoadoutSwitcher
## Seconds from the explosion to the new mech.
@export var respawn_time: float = 3.0

var _start := Transform3D.IDENTITY
var _left: float = 0.0


func _ready() -> void:
	_start = switcher.mech.global_transform
	switcher.mech_changed.connect(_watch)
	_watch(switcher.mech)


func _watch(mech: Mech) -> void:
	if mech.health != null and not mech.health.destroyed.is_connected(_on_destroyed):
		mech.health.destroyed.connect(_on_destroyed)


func _on_destroyed(_cause: String) -> void:
	_left = respawn_time


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		switcher.rebuild(switcher.current_loadout, _start)
		respawned.emit()
