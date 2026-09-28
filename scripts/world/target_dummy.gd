class_name TargetDummy
extends StaticBody3D
## A mech-sized target for weapon tests (layers 2 and 4, so weapons hit it). Missiles can lock it
## (group "lockable"). It flashes when hit and shows its HP above it. At 0 HP it explodes, and it
## comes back after respawn_time.

const EXPLOSION := preload("res://scenes/effects/explosion.tscn")

## Lock point height above the base, in meters.
@export var lock_height: float = 5.0
@export var mesh: MeshInstance3D
@export var max_hp: float = 3000.0
## Seconds before a destroyed dummy comes back.
@export var respawn_time: float = 6.0

var hp: float = 0.0

var _flash: float = 0.0
var _material: StandardMaterial3D
var _label: Label3D
var _layer: int = 0
var _respawn_left: float = 0.0


func _ready() -> void:
	add_to_group(&"lockable")
	_layer = collision_layer
	hp = max_hp
	if mesh != null:
		_material = (mesh.get_active_material(0) as StandardMaterial3D).duplicate()
		mesh.material_override = _material
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3.UP * 12.5
	_label.pixel_size = 0.02
	_label.font_size = 64
	_label.outline_size = 12
	_label.no_depth_test = true
	add_child(_label)
	_update_label()


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * lock_height


## Called by weapons when they hit.
func on_hit(damage: float) -> void:
	if hp <= 0.0:
		return
	_flash = 1.0
	hp = maxf(hp - damage, 0.0)
	_update_label()
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	var effect := EXPLOSION.instantiate() as Node3D
	get_parent().add_child(effect)
	effect.global_position = global_position + Vector3.UP * 6.0
	remove_from_group(&"lockable")
	collision_layer = 0
	visible = false
	_respawn_left = respawn_time


func _process(delta: float) -> void:
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			hp = max_hp
			collision_layer = _layer
			visible = true
			add_to_group(&"lockable")
			_update_label()
	if _material == null or _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_material.emission_enabled = _flash > 0.0
	_material.emission = Color(1.0, 0.5, 0.2)
	_material.emission_energy_multiplier = _flash * 3.0


func _update_label() -> void:
	_label.text = "%d / %d" % [roundi(hp), roundi(max_hp)]
	_label.modulate = Color(1.0, 0.3, 0.25) if hp < max_hp * 0.3 else Color.WHITE
