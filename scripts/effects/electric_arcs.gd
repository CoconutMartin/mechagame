class_name ElectricArcs
extends MeshInstance3D
## Draws jagged lightning ribbons in world space (pulse pellet trails, the arcs between pellets, hit forks).
## Each refresh: clear_arcs(), add_bolt() as often as needed, then commit(). The ribbons face the camera.

const SHADER := preload("res://shaders/electric_arc.gdshader")

static var _material: ShaderMaterial

var _mesh := ImmediateMesh.new()
var _verts := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## The camera position a node is seen from (falls back to the node itself + 10 m up).
static func view_position(node: Node3D) -> Vector3:
	var camera := node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	return camera.global_position if camera != null else node.global_position + Vector3.UP * 10.0


func _init() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	global_transform = Transform3D.IDENTITY


func clear_arcs() -> void:
	_verts.clear()
	_uvs.clear()
	_colors.clear()


## One jagged bolt from a to b. amplitude = the largest side offset (m); width = ribbon width (m). With branch_chance,
## short side branches leave from points along the bolt. alpha_a and alpha_b fade it along its length.
func add_bolt(a: Vector3, b: Vector3, width: float, amplitude: float, segments: int, color: Color,
		branch_chance: float = 0.0, alpha_a: float = 1.0, alpha_b: float = 1.0) -> void:
	var view := ElectricArcs.view_position(self)
	var points := _jagged(a, b, maxi(segments, 1), amplitude, view)
	_add_ribbon(points, view, width, color, alpha_a, alpha_b)
	if branch_chance <= 0.0:
		return
	var length := a.distance_to(b)
	for i in range(1, points.size() - 1):
		if randf() >= branch_chance:
			continue
		var along := (b - a).normalized()
		var out := along.cross(view - points[i]).normalized() * (1.0 if randf() < 0.5 else -1.0)
		var tip := points[i] + (along * randf_range(0.2, 0.6) + out).normalized() * length * randf_range(0.15, 0.3)
		var t := float(i) / float(points.size() - 1)
		var alpha := lerpf(alpha_a, alpha_b, t)
		_add_ribbon(_jagged(points[i], tip, 3, amplitude * 0.5, view), view, width * 0.6, color, alpha, 0.0)


func commit() -> void:
	_mesh.clear_surfaces()
	if _verts.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ElectricArcs.shared_material())
	for i in _verts.size():
		_mesh.surface_set_color(_colors[i])
		_mesh.surface_set_uv(_uvs[i])
		_mesh.surface_add_vertex(_verts[i])
	_mesh.surface_end()


func _jagged(a: Vector3, b: Vector3, segments: int, amplitude: float, view: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array([a])
	var along := b - a
	var dir := along.normalized()
	var side := dir.cross(view - a)
	if side.length_squared() < 0.0001:
		side = dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	side = side.normalized()
	var depth := dir.cross(side)
	var offset := Vector2.ZERO
	for i in range(1, segments):
		var t := float(i) / float(segments)
		offset = offset * 0.35 + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.75
		points.append(a + along * t + (side * offset.x + depth * offset.y * 0.5) * amplitude * sin(t * PI))
	points.append(b)
	return points


func _add_ribbon(points: PackedVector3Array, view: Vector3, width: float, color: Color, alpha_a: float,
		alpha_b: float) -> void:
	var count := points.size()
	if count < 2:
		return
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in count:
		var tangent := points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]
		var side := tangent.cross(view - points[i])
		side = side.normalized() * width * 0.5 if side.length_squared() > 0.0000001 else Vector3.ZERO
		left.append(points[i] - side)
		right.append(points[i] + side)
	for i in count - 1:
		var c0 := Color(color, color.a * lerpf(alpha_a, alpha_b, float(i) / float(count - 1)))
		var c1 := Color(color, color.a * lerpf(alpha_a, alpha_b, float(i + 1) / float(count - 1)))
		_quad(left[i], right[i], right[i + 1], left[i + 1], c0, c1)


func _quad(l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3, c0: Color, c1: Color) -> void:
	_verts.append_array([l0, r0, r1, l0, r1, l1])
	_uvs.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)])
	_colors.append_array([c0, c0, c1, c0, c1, c1])
