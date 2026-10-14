class_name HpIndicator
extends Node3D
## One HP indicator set into a mech's armor (user design "9 Minimal Dot", 2026-10-14): a small square
## status display with chamfered corners in a dark gunmetal frame, under thin dark glass. Only the
## display changes with the part HP: green (full), orange (half), red (low), dark (destroyed). The
## frame stays the same.
## Local space: the display faces +Z, the armor surface is at z = 0. Put the node on the armor (for
## example on the bone attachment of the armor's bone) and it follows the part. When the part breaks
## off, the indicator goes with its armor mesh (carrier).

## The part HP it shows (MechHealth key).
@export var health: MechHealth
@export var part_key: String = ""
## The armor mesh it sits on: the indicator goes with it when the part falls off.
@export var carrier: MeshInstance3D
## Display size (m, side of the square, without the frame).
@export var size: float = 0.3
## HP fraction to color: 1 = green, 0.5 = orange, 0.1 = red (the crosshair's colors).
@export var colors: Gradient
## Display glow. The map has glow on: above about 1.6 the display shows white.
@export var emission_energy: float = 1.2
## Display color of a destroyed part.
@export var dead_color: Color = Color(0.02, 0.025, 0.02)
## Frame width around the display, height above the armor, and how deep it goes into the armor (m).
@export var frame: float = 0.04
@export var frame_height: float = 0.035
@export var frame_sink: float = 0.06
## Corner cut (0 to 0.5 of the side) and the bevel on the frame's outer top edge (m).
@export var chamfer: float = 0.12
@export var bevel: float = 0.012
## Frame (matte gunmetal), recess and glass colors.
@export var housing_color: Color = Color(0.13, 0.135, 0.13)
@export var recess_color: Color = Color(0.012, 0.014, 0.013)
@export var glass_color: Color = Color(0.03, 0.04, 0.04, 0.3)

var _display: StandardMaterial3D
var _dead := false


func _ready() -> void:
	if colors == null:
		colors = Gradient.new()
		colors.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
		colors.colors = PackedColorArray([Color(0.95, 0.1, 0.05), Color(0.95, 0.12, 0.05),
				Color(1.0, 0.55, 0.05), Color(0.25, 1.0, 0.3)])
	_build()
	_show(1.0)


func _process(_delta: float) -> void:
	if health == null or _dead:
		return
	if not health.is_part_alive(part_key):
		_dead = true
		_show(0.0)
		return
	_show(health.get_fraction(part_key))


func _physics_process(_delta: float) -> void:
	# A destroyed part's mesh falls off (SkeletalPartBreaker takes its skin): go with it.
	if _dead and is_instance_valid(carrier) and carrier.skin == null and get_parent() != carrier:
		reparent(carrier, true)
		set_physics_process(false)


## Display state: 0 = destroyed (dark), else the HP fraction.
func _show(fraction: float) -> void:
	if fraction <= 0.0:
		_display.albedo_color = dead_color
		_display.emission_enabled = false
		return
	var color := colors.sample(fraction)
	_display.albedo_color = color * 0.3
	_display.emission_enabled = true
	_display.emission = color


func _build() -> void:
	var outer := size + frame * 2.0
	var top := frame_height
	var floor_z := 0.004
	var outer_ring := _outline(outer, chamfer)
	var bevel_ring := _outline(outer - bevel * 2.0, chamfer)
	var inner_ring := _outline(size, chamfer)
	var deep_ring := _outline(outer + frame_sink * 2.0, chamfer)

	# Housing: beveled top edge, top face, outer wall flaring into the armor, inner wall of the recess.
	var housing := SurfaceTool.new()
	housing.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(housing, bevel_ring, top, outer_ring, top - bevel, Vector3.BACK, 1.0)
	_band(housing, inner_ring, top, bevel_ring, top, Vector3.BACK, 0.0)
	_band(housing, outer_ring, top - bevel, deep_ring, -frame_sink, Vector3.BACK, 1.0)
	_band(housing, inner_ring, floor_z, inner_ring, top, Vector3.ZERO, -1.0)
	_add(&"HPIndicator_Housing", housing.commit(), _material(housing_color, 0.6, 0.65))

	var recess := SurfaceTool.new()
	recess.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(recess, inner_ring, floor_z)
	_add(&"HPIndicator_Recess", recess.commit(), _material(recess_color, 0.0, 0.9))

	_display = _material(Color.BLACK, 0.0, 0.5)
	_display.emission_energy_multiplier = emission_energy
	var display := SurfaceTool.new()
	display.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(display, _outline(size * 0.82, chamfer), floor_z + 0.006)
	_add(&"HPIndicator_Display", display.commit(), _display)

	var glass_material := _material(glass_color, 0.3, 0.06)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(glass, inner_ring, top - 0.008)
	_add(&"HPIndicator_Glass", glass.commit(), glass_material)


func _add(node_name: StringName, mesh: Mesh, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The skin (PS1SkinLook) leaves these meshes alone.
	node.add_to_group(PS1SkinLook.SKIP_GROUP)
	add_child(node)


## A square with cut corners (side, cut as a share of the side), counterclockwise in XY.
func _outline(side: float, cut: float) -> PackedVector2Array:
	var half := side * 0.5
	var c := side * clampf(cut, 0.0, 0.5)
	return PackedVector2Array([Vector2(half, -half + c), Vector2(half, half - c), Vector2(half - c, half),
			Vector2(-half + c, half), Vector2(-half, half - c), Vector2(-half, -half + c),
			Vector2(-half + c, -half), Vector2(half - c, -half)])


## A band of quads between two outlines (same point count) at two heights. Normals point toward
## up_hint plus outward (side_sign 1), inward (-1) or neither (0).
func _band(tool: SurfaceTool, a: PackedVector2Array, za: float, b: PackedVector2Array, zb: float,
		up_hint: Vector3, side_sign: float) -> void:
	for i in a.size():
		var j := (i + 1) % a.size()
		var p0 := Vector3(a[i].x, a[i].y, za)
		var p1 := Vector3(a[j].x, a[j].y, za)
		var p2 := Vector3(b[j].x, b[j].y, zb)
		var p3 := Vector3(b[i].x, b[i].y, zb)
		var mid := (a[i] + a[j]) * 0.5
		var hint := up_hint + Vector3(mid.x, mid.y, 0.0).normalized() * side_sign
		_tri(tool, p0, p1, p2, hint)
		_tri(tool, p0, p2, p3, hint)


## A flat face over an outline at height z, facing +Z.
func _cap(tool: SurfaceTool, ring: PackedVector2Array, z: float) -> void:
	for i in range(1, ring.size() - 1):
		_tri(tool, Vector3(ring[0].x, ring[0].y, z), Vector3(ring[i].x, ring[i].y, z),
				Vector3(ring[i + 1].x, ring[i + 1].y, z), Vector3.BACK)


## One flat shaded triangle, front face and normal toward hint.
func _tri(tool: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, hint: Vector3) -> void:
	var normal := (p1 - p0).cross(p2 - p0)
	if normal.length() < 0.0000001:
		return
	normal = normal.normalized()
	# Godot front faces wind clockwise as seen from the normal side.
	if normal.dot(hint) > 0.0:
		var swap := p1
		p1 = p2
		p2 = swap
	else:
		normal = -normal
	tool.set_normal(normal)
	tool.add_vertex(p0)
	tool.add_vertex(p1)
	tool.add_vertex(p2)


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material
