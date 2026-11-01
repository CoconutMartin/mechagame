class_name PulseShot
extends Node3D
## The look of an electric pulse shot (Shotgun 2, user request 2026-11-01: "a square electric pulse shot"; Shotgun 3: an
## X, `cross`): a glowing blue square frame (or X) that flies along a direction, grows with the distance (it matches the square pellet pattern),
## flickers like an electric arc, and ends at the first wall it meets or at its range. It does no damage: the pellets
## of the shot do (PulseShotgunWeapon).

## Square side at the muzzle, in meters.
@export var start_size: float = 1.2
## Frame bar thickness, in meters.
@export var bar: float = 0.32
@export var color: Color = Color(0.25, 0.55, 1.0)
## See-through fill inside the frame.
@export var fill_color: Color = Color(0.3, 0.6, 1.0, 0.22)
## Layers that stop the look (1 world, 3 props, 5 buildings; mechs too, 4).
@export_flags_3d_physics var collision_mask: int = 29

var velocity: Vector3 = Vector3.ZERO
## Half angle of the square pellet pattern (degrees): the square grows to match it.
var spread_deg: float = 4.0
var range_m: float = 270.0
var exclude: Array[RID] = []
## True: an X (two crossing bars, Shotgun 3) instead of a square frame. Set before it enters the tree.
var cross: bool = false

var _travelled: float = 0.0
var _frame: Node3D
var _fade: float = -1.0


func _ready() -> void:
	_frame = Node3D.new()
	add_child(_frame)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Solid unshaded blue: added light washed out to white against the bright sky.
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in (2 if cross else 4):
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, bar, bar * 0.5)
		mesh.mesh = box
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frame.add_child(mesh)
	if cross:
		_add_light()
		_layout(start_size)
		return
	var fill := MeshInstance3D.new()
	var quad := QuadMesh.new()
	fill.mesh = quad
	var fill_material := material.duplicate() as StandardMaterial3D
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.albedo_color = fill_color
	fill.material_override = fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.name = "Fill"
	_frame.add_child(fill)
	_add_light()
	_layout(start_size)


func _add_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 14.0
	add_child(light)


func _layout(size: float) -> void:
	if cross:
		# Two bars corner to corner of the square the pellets fill.
		for i in 2:
			var bar_mesh := _frame.get_child(i) as MeshInstance3D
			bar_mesh.position = Vector3.ZERO
			bar_mesh.rotation = Vector3(0, 0, PI * 0.25 if i == 0 else -PI * 0.25)
			bar_mesh.scale = Vector3(size * sqrt(2.0) + bar, 1.0, 1.0)
		return
	var half := size * 0.5
	var places := [Vector3(0, half, 0), Vector3(0, -half, 0), Vector3(half, 0, 0), Vector3(-half, 0, 0)]
	for i in 4:
		var mesh := _frame.get_child(i) as MeshInstance3D
		mesh.position = places[i]
		mesh.rotation = Vector3(0, 0, 0 if i < 2 else PI * 0.5)
		mesh.scale = Vector3(size + bar, 1.0, 1.0)
	var fill := _frame.get_node_or_null(^"Fill") as MeshInstance3D
	if fill != null:
		fill.scale = Vector3(size, size, 1.0)


func _physics_process(delta: float) -> void:
	if _fade >= 0.0:
		_fade += delta
		scale = Vector3.ONE * (1.0 - _fade / 0.12)
		if _fade >= 0.12:
			queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude))
	if not hit.is_empty():
		global_position = hit.position
		_fade = 0.0
		return
	global_position = to
	_travelled += from.distance_to(to)
	if _travelled >= range_m:
		_fade = 0.0
		return
	look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)
	# Grows with the pellet pattern; flickers and turns a little like an electric arc.
	_layout(start_size + 2.0 * _travelled * tan(deg_to_rad(spread_deg)))
	_frame.rotation.z = randf_range(-0.06, 0.06)
	_frame.scale = Vector3.ONE * randf_range(0.94, 1.06)
