class_name NozzleHeat
extends RefCounted
## Heat of the booster nozzles (user request 2026-11-02: "quad booster boosters should also heat up ... apply this to
## all backpacks with boosters"). The nozzle metal of a back pack model glows from dark to dull red to orange with
## use (boosting, jump jets, a dodge hop) and cools down after. Parts by name: OutletGlow, NozzleThroat, NozzleInner
## and NozzleRing are the hot inner parts; the other Nozzle... parts (bell, lip, petals) and the louver flaps
## (OutletFlap) glow less. Housings, collars and shrouds are armor and stay dark. The glow is a material overlay
## (a mix blend, so it also tints the dark metal; an added blend would turn olive paint yellow-green).

## Heat gained per second at full thrust (1 = white hot).
@export var heat_rate: float = 0.6
## Heat lost per second with no thrust.
@export var cool_rate: float = 0.25
## Glow of the rim parts compared with the inner parts (0 to 1).
@export var rim_share: float = 0.6
## Color and opacity of the overlay from cold (0) to hottest (1): dull red, deep red-orange, orange. Deep colors and
## a low energy: bright emissive colors wash out to yellow in the tonemapper.
@export var ramp: Gradient

## 0 = cold, 1 = hottest.
var heat: float = 0.0

var _inner: StandardMaterial3D
var _rim: StandardMaterial3D
## Meshes that carry an overlay (for tests).
var _meshes: Array[MeshInstance3D] = []


## Finds the nozzle parts of a pack model (an object with no parts when the model has none).
static func attach(pack_model: Node3D, heat_ramp: Gradient = null) -> NozzleHeat:
	var nozzle_heat := NozzleHeat.new()
	nozzle_heat.ramp = heat_ramp
	nozzle_heat._setup(pack_model)
	return nozzle_heat


## A blue heat ramp (the Boost Pack's light blue panel fire, 2026-11-03): dark, deep blue, light blue, white-blue.
static func blue_ramp() -> Gradient:
	var blue := Gradient.new()
	blue.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	blue.colors = PackedColorArray([Color(0.02, 0.06, 0.3, 0.0), Color(0.05, 0.18, 0.7, 0.35),
			Color(0.25, 0.6, 1.2, 0.7), Color(0.7, 0.9, 1.4, 0.9)])
	return blue


func _setup(model: Node3D) -> void:
	if ramp == null:
		ramp = Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
		ramp.colors = PackedColorArray([
			Color(0.35, 0.03, 0.0, 0.0), Color(0.4, 0.04, 0.01, 0.25), Color(0.62, 0.09, 0.02, 0.55),
			Color(0.85, 0.22, 0.04, 0.75), Color(0.95, 0.36, 0.06, 0.88)])
	_inner = _overlay()
	_rim = _overlay()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var part := String(mesh.name)
		if part.begins_with("OutletGlow") or part.begins_with("NozzleThroat") or part.begins_with("NozzleInner") \
				or part.begins_with("NozzleRing"):
			mesh.material_overlay = _inner
		elif part.begins_with("NozzlePetal") or part.begins_with("NozzleLip") or part.begins_with("OutletFlap") \
				or (part.begins_with("Nozzle") and not part.begins_with("NozzleHousing")
				and not part.begins_with("NozzleCollar") and not part.begins_with("NozzleShroud")):
			mesh.material_overlay = _rim
		else:
			continue
		_meshes.append(mesh)
	_apply()


func _overlay() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.4, 0.04, 0.01, 0.0)
	return material


## True when the model has parts that heat up.
func has_parts() -> bool:
	return not _meshes.is_empty()


## thrust: 0 (cooling) to 1 (full thrust) and more in a burst.
func update(delta: float, thrust: float) -> void:
	heat = clampf(heat + (heat_rate * thrust - cool_rate * (1.0 - clampf(thrust, 0.0, 1.0))) * delta, 0.0, 1.0)
	_apply()


## Color of the inner parts' overlay now (for tests).
func get_color() -> Color:
	return _inner.albedo_color


func _apply() -> void:
	var color := ramp.sample(heat)
	_inner.albedo_color = color
	_rim.albedo_color = Color(color, color.a * rim_share)
