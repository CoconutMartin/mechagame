class_name MechHpMarks
extends Node
## HP lamps on the mech's own armor (user requests 2026-10-14: the HP shows on the body parts, not as
## text; one square dot per part). Each HP part gets one small square lamp set into the back of its
## largest mesh (the side the camera sees), so every rigged model gets them without setup. A lamp is a
## dark beveled bezel with a glowing square core, a brighter center and a soft glow on the armor around
## it. The color goes from green (full) to orange (half) to red (low). At low HP the lamp pulses, and a
## hit flashes it white. Shown on the player mech only.
## Torso parts that share one mesh (Torso C, L, R) use their X range of it (BoneHitPart.min_x, max_x).

@export var mech: Mech
@export var hitboxes: SkeletalHitboxes
@export var health: MechHealth
## HP fraction to color: 1 = green, 0.5 = orange, 0.1 = red.
@export var colors: Gradient
## Lamp core size and bezel size (meters, square side), and the lamp's lift off the armor surface.
@export var core_size: float = 0.24
@export var bezel_size: float = 0.4
@export var lift: float = 0.04
## Lamp height on its part: 0 = the middle, 0.5 = the top edge (head and groin stay in the middle).
@export var height_share: float = 0.25
## Glow strength of the core (above 1 the screen glow blooms it) and of the halo on the armor.
@export var glow_energy: float = 1.6
@export var halo_size: float = 1.1
@export var halo_alpha: float = 0.45
## Below this HP the lamp pulses (pulses per second).
@export var warning_fraction: float = 0.25
@export var pulse_speed: float = 2.0
## Seconds of white flash when the part takes damage.
@export var hit_flash_time: float = 0.2
@export var bezel_color: Color = Color(0.05, 0.055, 0.06)

## Part key -> {root, core, center, halo, last, flash}.
var _marks := {}
var _time: float = 0.0


func _ready() -> void:
	if colors == null:
		colors = Gradient.new()
		colors.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
		colors.colors = PackedColorArray([Color(0.95, 0.08, 0.05), Color(0.95, 0.12, 0.05),
				Color(1.0, 0.5, 0.05), Color(0.15, 1.0, 0.3)])
	_build.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	var shown := mech.is_in_group(&"player") and not mech.is_wrecked
	for key: String in _marks:
		var mark: Dictionary = _marks[key]
		var root := mark.root as Node3D
		var fraction := health.get_fraction(key)
		root.visible = shown and fraction > 0.0
		if not root.visible:
			continue
		if fraction < mark.last:
			mark.flash = hit_flash_time
		mark.last = fraction
		mark.flash = maxf(mark.flash - delta, 0.0)
		var flash: float = mark.flash / hit_flash_time
		var pulse := 1.0
		if fraction < warning_fraction:
			pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * TAU * pulse_speed))
		var tint := colors.sample(fraction).lerp(Color.WHITE, flash * 0.7)
		var core := mark.core as StandardMaterial3D
		core.emission = tint
		core.emission_energy_multiplier = glow_energy * pulse * (1.0 + flash)
		var center := mark.center as StandardMaterial3D
		center.emission = tint.lerp(Color.WHITE, 0.45)
		center.emission_energy_multiplier = glow_energy * 1.4 * pulse * (1.0 + flash)
		(mark.halo as StandardMaterial3D).albedo_color = Color(tint, halo_alpha * pulse + 0.3 * flash)


## One lamp per HP part, on the back of the part's largest mesh.
func _build() -> void:
	var skeleton := hitboxes.skeleton
	if skeleton == null:
		return
	for part: BoneHitPart in hitboxes.parts.parts:
		var best: MeshInstance3D = null
		var best_box := AABB()
		var best_volume := 0.0
		var cut := AABB(Vector3(part.min_x, -1000.0, -1000.0), Vector3(part.max_x - part.min_x, 2000.0, 2000.0))
		for mesh: MeshInstance3D in hitboxes.mesh_bones:
			if not StringName(skeleton.get_bone_name(hitboxes.mesh_bones[mesh])) in part.bones:
				continue
			var box := (mesh.transform * mesh.get_aabb()).intersection(cut)
			var volume := box.size.x * box.size.y * box.size.z
			if volume > best_volume:
				best = mesh
				best_box = box
				best_volume = volume
		if best != null:
			var up := 0.0 if part.key in ["Head", "Groin"] else height_share
			_add_lamp(part.key, best, best_box, up)


func _add_lamp(key: String, mesh: MeshInstance3D, box: AABB, up: float) -> void:
	# Ray from behind the part (skeleton space: +Z forward) to its back surface, in its upper part.
	var center := box.get_center() + Vector3(0.0, box.size.y * up, 0.0)
	var from := Vector3(center.x, center.y, box.position.z - 2.0)
	var to_mesh := mesh.transform.affine_inverse()
	var faces := mesh.mesh.generate_triangle_mesh()
	var hit := faces.intersect_ray(to_mesh * from, (to_mesh.basis * Vector3.BACK).normalized())
	if hit.is_empty() and up != 0.0:
		_add_lamp(key, mesh, box, 0.0)
		return
	if hit.is_empty():
		return
	var point: Vector3 = mesh.transform * (hit.position as Vector3)
	var normal: Vector3 = (mesh.transform.basis * (hit.normal as Vector3)).normalized()
	if normal.z > 0.0:
		normal = -normal
	# Lamp space: +Y out of the armor, +Z up the part (the square stays upright).
	var along := (Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	var side := normal.cross(along).normalized()
	var place := Transform3D(Basis(side, normal, along), point + normal * lift)

	var bone: int = hitboxes.mesh_bones[mesh]
	var root := Node3D.new()
	root.name = "HpLamp_" + key.replace(" ", "")
	hitboxes.get_attachment(bone).add_child(root)
	root.transform = hitboxes.skeleton.get_bone_global_rest(bone).affine_inverse() * place
	# Bezel: a dark beveled metal frame (a wide base and a smaller raised rim).
	var frame := StandardMaterial3D.new()
	frame.albedo_color = bezel_color
	frame.metallic = 0.85
	frame.roughness = 0.3
	root.add_child(_box(Vector3(bezel_size, 0.04, bezel_size), Vector3(0.0, 0.0, 0.0), frame))
	root.add_child(_box(Vector3(bezel_size * 0.82, 0.07, bezel_size * 0.82), Vector3(0.0, 0.0, 0.0), frame))
	# Soft glow on the armor around the lamp.
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_texture = _halo_texture()
	var plane := PlaneMesh.new()
	plane.size = Vector2(halo_size, halo_size)
	var glow := MeshInstance3D.new()
	glow.mesh = plane
	glow.material_override = halo
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = Vector3(0.0, -0.015, 0.0)
	root.add_child(glow)
	# Core: the glowing square, with a brighter center.
	var core := _glow_material()
	root.add_child(_box(Vector3(core_size, 0.06, core_size), Vector3(0.0, 0.02, 0.0), core))
	var bright := _glow_material()
	root.add_child(_box(Vector3(core_size * 0.45, 0.065, core_size * 0.45), Vector3(0.0, 0.025, 0.0), bright))
	_marks[key] = {"root": root, "core": core, "center": bright, "halo": halo, "last": 1.0, "flash": 0.0}


func _box(size: Vector3, center: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = center
	return node


func _glow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.emission_enabled = true
	material.emission = colors.sample(1.0)
	material.emission_energy_multiplier = glow_energy
	return material


## Soft square glow: bright in the middle, fading to the edges.
func _halo_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
