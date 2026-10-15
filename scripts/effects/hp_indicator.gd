class_name HpIndicator
extends Node3D
## One HP indicator set into a mech's armor (user design "9 Minimal Dot", approved 2026-10-15): a
## small square window with a thin light metal rim, a dark gunmetal bezel, a thin light inner lip
## and a dark recess under thin glass. The display color shows the part HP: green (full), orange
## (half), red (low), dark (destroyed). The housing never changes. It can also show cells or a bar
## that gets shorter (cells, continuous), which the current layout does not use.
## Local space: the gauge runs along +X (up when vertical), the window faces +Z, the armor surface
## is at z = 0. It stays level with the ground (turns about its face normal only) and follows the
## part. When the part breaks off, the indicator goes with its armor mesh (carrier).

## The part HP it shows (MechHealth key).
@export var health: MechHealth
@export var part_key: String = ""
## The armor mesh it sits on: the gauge goes with it when the part falls off.
@export var carrier: MeshInstance3D
## Window length and height (m), without the bezel.
@export var length: float = 0.68
@export var height: float = 0.12
## Number of cells.
@export var cells: int = 3
## True: the gauge runs up (it fills from the bottom).
@export var vertical: bool = false
## True: one bar whose length shows the HP (cells is not used).
@export var continuous: bool = false
## Cell thickness across the gauge (0 to 1 of the space inside the margins).
@export_range(0.1, 1.0) var bar_share: float = 1.0
## Cell corner radius (m). Half the cell thickness or more makes a pill.
@export var cell_round: float = 0.006
## Shortest continuous bar (0 to 1 of the full length), so a red bar still shows.
@export var min_fill: float = 0.08
## HP fraction to color: 1 to 0.67 = green, 0.5 = orange, 0.1 = red.
@export var colors: Gradient
## Glow of the lit cells, and of the front lit cell. The map has glow on: above about 1.6 a cell
## shows white.
@export var cell_glow: float = 0.6
@export var front_glow: float = 1.1
## Gaps (m): between cells, and between the cells and the window edge.
@export var cell_gap: float = 0.026
@export var cell_margin: float = 0.022
## Housing (m): bezel width, light rim width, light inner lip width, height above the armor, depth
## into the armor, corner radius.
@export var bezel: float = 0.026
@export var rim: float = 0.01
@export var lip: float = 0.008
@export var frame_height: float = 0.03
@export var frame_sink: float = 0.06
@export var corner: float = 0.03
## Colors: dark bezel, light metal rim and lip, window, unlit cell, glass.
@export var bezel_color: Color = Color(0.07, 0.075, 0.075)
@export var rim_color: Color = Color(0.42, 0.43, 0.42)
@export var window_color: Color = Color(0.01, 0.012, 0.012)
@export var unlit_color: Color = Color(0.32, 0.33, 0.33)
@export var glass_color: Color = Color(0.03, 0.04, 0.04, 0.25)

var _cell_materials: Array[StandardMaterial3D] = []
var _fill: Node3D
var _pivot: Node3D
var _dead := false


func _ready() -> void:
	if colors == null:
		colors = Gradient.new()
		# Green while 2 or 3 cells are lit (the reference shows 2 green cells).
		colors.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 0.67, 1.0])
		colors.colors = PackedColorArray([Color(0.95, 0.1, 0.05), Color(0.95, 0.12, 0.05),
				Color(1.0, 0.55, 0.05), Color(0.2, 1.0, 0.2), Color(0.2, 1.0, 0.2)])
	_build()
	show_fraction(1.0)


func _process(_delta: float) -> void:
	if _dead:
		return
	_level()
	if health == null:
		return
	if not health.is_part_alive(part_key):
		_dead = true
		show_fraction(0.0)
		return
	show_fraction(health.get_fraction(part_key))


func _physics_process(_delta: float) -> void:
	# A destroyed part's mesh falls off (SkeletalPartBreaker takes its skin): go with it.
	if _dead and is_instance_valid(carrier) and carrier.skin == null and get_parent() != carrier:
		reparent(carrier, true)
		set_physics_process(false)


## Cells for an HP fraction: 0 = destroyed (all dark).
func show_fraction(fraction: float) -> void:
	var lit := ceili(clampf(fraction, 0.0, 1.0) * _cell_materials.size() - 0.001)
	if _fill != null:
		_fill.scale.x = maxf(clampf(fraction, 0.0, 1.0), min_fill)
	var color := colors.sample(fraction)
	for i in _cell_materials.size():
		var material := _cell_materials[i]
		if i < lit:
			var glow := front_glow if i == lit - 1 else cell_glow
			material.albedo_color = color * 0.3
			material.emission_enabled = true
			# The front cell of a cell gauge is a little yellower (like the reference); one bar is plain.
			var front := i == lit - 1 and _cell_materials.size() > 1
			material.emission = color.lerp(Color(0.8, 1.0, 0.3), 0.3) if front else color
			material.emission_energy_multiplier = glow
		else:
			material.albedo_color = unlit_color
			material.emission_enabled = false


## Turns the gauge about its face normal so it stays level with the ground. It keeps its fill
## direction.
func _level() -> void:
	var normal := global_basis.z.normalized()
	var side := Vector3.UP.cross(normal)
	if side.length() < 0.1:
		return
	side = side.normalized()
	# A level gauge keeps its fill direction. A vertical one keeps its +Y up (it fills up).
	if not vertical and side.dot(global_basis.x) < 0.0:
		side = -side
	global_basis = Basis(side, normal.cross(side), normal)


func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	if vertical:
		_pivot.rotation.z = PI * 0.5
	add_child(_pivot)
	var top := frame_height
	var floor_z := 0.004
	var window := _outline(length, height, corner)
	var lip_ring := _outline(length + lip * 2.0, height + lip * 2.0, corner + lip)
	var bezel_ring := _outline(length + (lip + bezel) * 2.0, height + (lip + bezel) * 2.0, corner + lip + bezel)
	var full := lip + bezel + rim
	var rim_ring := _outline(length + full * 2.0, height + full * 2.0, corner + full)
	var deep := full + frame_sink
	var deep_ring := _outline(length + deep * 2.0, height + deep * 2.0, corner + deep)

	# Light rim: a bevel from the bezel's edge down to the armor, then into the armor.
	var rim_tool := _tool()
	_band(rim_tool, bezel_ring, top, rim_ring, top - rim, Vector3.BACK, 1.0)
	_band(rim_tool, rim_ring, top - rim, deep_ring, -frame_sink, Vector3.BACK, 1.0)
	_add(&"HPIndicator_Rim", rim_tool.commit(), _material(rim_color, 0.7, 0.35))
	# Dark bezel: the flat top face.
	var bezel_tool := _tool()
	_band(bezel_tool, lip_ring, top, bezel_ring, top, Vector3.BACK, 0.0)
	_add(&"HPIndicator_Housing", bezel_tool.commit(), _material(bezel_color, 0.6, 0.6))
	# Light inner lip: a bevel into the window, then the window wall.
	var lip_tool := _tool()
	_band(lip_tool, window, top - lip, lip_ring, top, Vector3.BACK, -1.0)
	_band(lip_tool, window, floor_z, window, top - lip, Vector3.ZERO, -1.0)
	_add(&"HPIndicator_Lip", lip_tool.commit(), _material(rim_color * 0.8, 0.7, 0.35))
	# Window floor.
	var recess := _tool()
	_cap(recess, window, floor_z)
	_add(&"HPIndicator_Recess", recess.commit(), _material(window_color, 0.0, 0.9))
	# Cells, from the inner end (-X) to the outer end (+X).
	var inner_length := length - cell_margin * 2.0
	var count := 1 if continuous else cells
	var cell_length := (inner_length - cell_gap * (count - 1)) / count
	var cell_height := (height - cell_margin * 2.0) * bar_share
	if continuous:
		# One bar from the inner end, in a node that scales with the HP.
		_fill = Node3D.new()
		_fill.name = "Fill"
		_fill.position.x = -inner_length * 0.5
		_pivot.add_child(_fill)
	for i in count:
		var x := cell_length * 0.5 if continuous else -inner_length * 0.5 + cell_length * 0.5 + i * (cell_length + cell_gap)
		var cell := _tool()
		var ring := _outline(cell_length, cell_height, cell_round)
		for j in ring.size():
			ring[j].x += x
		_cap(cell, ring, floor_z + 0.005)
		var material := _material(unlit_color, 0.0, 0.3)
		_cell_materials.append(material)
		_add(StringName("HPIndicator_Display_%d" % (i + 1)), cell.commit(), material, _fill)
	# Glass over the window.
	var glass_material := _material(glass_color, 0.3, 0.05)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var glass := _tool()
	_cap(glass, window, top - lip - 0.004)
	_add(&"HPIndicator_Glass", glass.commit(), glass_material)


func _tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


func _add(node_name: StringName, mesh: Mesh, material: Material, parent: Node3D = null) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The skin (PS1SkinLook) leaves these meshes alone.
	node.add_to_group(PS1SkinLook.SKIP_GROUP)
	(parent if parent != null else _pivot).add_child(node)


## A rectangle with round corners (2 steps per corner), counterclockwise in XY. Every outline has
## the same point count, so bands can join any two.
func _outline(size_x: float, size_y: float, radius: float) -> PackedVector2Array:
	var hx := size_x * 0.5
	var hy := size_y * 0.5
	var r := clampf(radius, 0.0, minf(hx, hy))
	var points := PackedVector2Array()
	var centers := [Vector2(hx - r, hy - r), Vector2(-hx + r, hy - r), Vector2(-hx + r, -hy + r),
			Vector2(hx - r, -hy + r)]
	for k in 4:
		for step in 3:
			var angle := (k + step / 2.0) * PI * 0.5
			points.append((centers[k] as Vector2) + Vector2.from_angle(angle) * r)
	return points


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
		var edge := a[j] - a[i]
		var out := Vector2(edge.y, -edge.x).normalized() if edge.length() > 0.0001 else (a[i] + a[j]).normalized()
		var hint := up_hint + Vector3(out.x, out.y, 0.0) * side_sign
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
