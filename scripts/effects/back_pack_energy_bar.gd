class_name BackPackEnergyBar
extends Node
## Boost energy light on a back pack (Boost Pack, user request 2026-10-31: "a third bar for the boost energy
## indicator. Full energy = bright light blue light, then color and brightness fade as energy approaches empty").
## The pack model has an EnergyBar mesh; this node colors it each frame from the mech's energy fraction.
## BackPackMount adds this node when the model has an EnergyBar mesh.

## Bar color at full energy (bright light blue).
@export var full_color: Color = Color(0.3, 0.8, 1.0)
## Bar color at empty energy (dim, gray blue).
@export var empty_color: Color = Color(0.1, 0.12, 0.15)
## Shape of the fade (1 = even; above 1 = stays bright longer, then drops faster near empty).
@export var fade_curve: float = 0.6

var mech: Mech
## The shown energy fraction (0 to 1).
var fraction: float = 1.0

var _bar: MeshInstance3D
var _material: StandardMaterial3D


## Adds the energy light for a pack model (null when the model has no EnergyBar mesh).
static func attach(target: Mech, pack_model: Node3D) -> BackPackEnergyBar:
	if target == null or pack_model == null:
		return null
	var bar := pack_model.find_child("EnergyBar", true, false) as MeshInstance3D
	if bar == null:
		return null
	var light := BackPackEnergyBar.new()
	light.name = "BackPackEnergyBar"
	light.mech = target
	light._bar = bar
	target.add_child(light)
	return light


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if not is_instance_valid(_bar):
		return
	fraction = mech.energy.get_fraction() if mech != null and mech.energy != null else 1.0
	var t := pow(clampf(fraction, 0.0, 1.0), fade_curve)
	_material.albedo_color = empty_color.lerp(full_color, t)
	# The bar's own material (unshaded, so the PS1 skin leaves it as it is); set again if something replaced it.
	if _bar.material_override != _material:
		_bar.material_override = _material


## The bar's color now (for tests).
func get_color() -> Color:
	return _material.albedo_color
