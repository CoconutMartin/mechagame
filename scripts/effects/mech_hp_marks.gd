class_name MechHpMarks
extends Node
## HP gauges on the mech's own armor (user requests 2026-10-14: the HP shows on the body parts, not as
## text, in a style like the RIG health spine in Dead Space). One gauge per HP part, set into the back
## of the part's largest mesh (the side the camera sees), so every rigged model gets them without
## setup. A gauge is a row of glowing cells in a dark metal housing with a soft glow on the armor
## around it. Lit cells go out as the part loses HP; the color goes from green (full) to orange (half)
## to red (low). At low HP the last lit cell flickers, and a hit flashes the gauge. The center torso
## gauge is the long spine gauge. Shown on the player mech only.
## Torso parts that share one mesh (Torso C, L, R) use their X range of it (BoneHitPart.min_x, max_x).

@export var mech: Mech
@export var hitboxes: SkeletalHitboxes
@export var health: MechHealth
## HP fraction to color: 1 = green, 0.5 = orange, 0.1 = red.
@export var colors: Gradient
## Gauge length as a part of the part's width or height, and its limits (meters). The center torso
## gauge is the long spine gauge (spine_share of the torso height).
@export var length_share: float = 0.45
@export var spine_share: float = 0.8
@export var min_length: float = 0.6
@export var max_length: float = 2.0
## Gauge width (the lit cells), and its lift off the armor surface (meters).
@export var width: float = 0.13
@export var lift: float = 0.04
## Cell length (meters, about) and gap between cells.
@export var cell_length: float = 0.2
@export var cell_gap: float = 0.05
## Glow strength of a lit cell (above 1 the screen glow blooms it), and of a dark cell.
@export var glow_energy: float = 1.3
@export var dark_energy: float = 0.12
## Below this HP the last lit cell flickers (flashes per second).
@export var warning_fraction: float = 0.25
@export var flicker_speed: float = 4.5
## Seconds of white flash on the gauge when the part takes damage.
@export var hit_flash_time: float = 0.18
## Housing: the dark metal frame around the cells.
@export var housing_color: Color = Color(0.07, 0.08, 0.08)

## Part key -> {root, cells, lit, dark, halo, last, flash}.
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
		var tint := colors.sample(fraction)
		var lit_material := mark.lit as StandardMaterial3D
		lit_material.emission = tint.lerp(Color.WHITE, flash * 0.7)
		lit_material.emission_energy_multiplier = glow_energy * (1.0 + flash)
		(mark.dark as StandardMaterial3D).emission = tint
		(mark.halo as StandardMaterial3D).albedo_color = Color(tint, 0.35 + 0.3 * flash)
		var cells: Array = mark.cells
		var lit := ceili(fraction * cells.size() - 0.001)
		for i in cells.size():
			var on := i < lit
			# The last lit cell flickers at low HP (a warning).
			if on and i == lit - 1 and fraction < warning_fraction:
				on = sin(_time * TAU * flicker_speed) > -0.3
			(cells[i] as MeshInstance3D).material_override = mark.lit if on else mark.dark


## One gauge per HP part: on the back of the part's largest mesh, at its center.
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
			_add_gauge(part.key, best, best_box)


func _add_gauge(key: String, mesh: MeshInstance3D, box: AABB) -> void:
	# Ray from behind the part (skeleton space: +Z forward) to its back surface.
	var center := box.get_center()
	var from := Vector3(center.x, center.y, box.position.z - 2.0)
	var to_mesh := mesh.transform.affine_inverse()
	var faces := mesh.mesh.generate_triangle_mesh()
	var hit := faces.intersect_ray(to_mesh * from, (to_mesh.basis * Vector3.BACK).normalized())
	if hit.is_empty():
		return
	var point: Vector3 = mesh.transform * (hit.position as Vector3)
	var normal: Vector3 = (mesh.transform.basis * (hit.normal as Vector3)).normalized()
	if normal.z > 0.0:
		normal = -normal
	# Along the part's wider side: across for wide parts (shoulders, head), up for tall ones (legs).
	var along := Vector3.RIGHT if box.size.x >= box.size.y * 0.75 else Vector3.UP
	var size := box.size.x if along == Vector3.RIGHT else box.size.y
	var share := spine_share if key == "Torso C" else length_share
	var count := maxi(roundi(clampf(size * share, min_length, max_length) / (cell_length + cell_gap)), 3)
	var length := count * (cell_length + cell_gap) - cell_gap
	along = (along - normal * along.dot(normal)).normalized()
	var side := normal.cross(along).normalized()
	# Gauge space: +Z along the gauge (from its start), +Y out of the armor.
	var start := point + normal * lift - along * length * 0.5
	var place := Transform3D(Basis(side, normal, along), start)

	var bone: int = hitboxes.mesh_bones[mesh]
	var root := Node3D.new()
	root.name = "HpGauge_" + key.replace(" ", "")
	hitboxes.get_attachment(bone).add_child(root)
	root.transform = hitboxes.skeleton.get_bone_global_rest(bone).affine_inverse() * place
	var frame := StandardMaterial3D.new()
	frame.albedo_color = housing_color
	frame.metallic = 0.8
	frame.roughness = 0.35
	root.add_child(_box(Vector3(width + 0.1, 0.05, length + 0.12), Vector3(0.0, 0.0, length * 0.5), frame))
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_texture = _halo_texture()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width * 5.0, length + 0.6)
	var glow := MeshInstance3D.new()
	glow.mesh = plane
	glow.material_override = halo
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = Vector3(0.0, -0.015, length * 0.5)
	root.add_child(glow)
	var lit := _glow_material(glow_energy)
	var dark := _glow_material(dark_energy)
	var cells: Array[MeshInstance3D] = []
	for i in count:
		var z := i * (cell_length + cell_gap) + cell_length * 0.5
		var cell := _box(Vector3(width, 0.04, cell_length), Vector3(0.0, 0.035, z), lit)
		root.add_child(cell)
		cells.append(cell)
	_marks[key] = {"root": root, "cells": cells, "lit": lit, "dark": dark, "halo": halo, "last": 1.0, "flash": 0.0}


func _box(size: Vector3, center: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = center
	return node


func _glow_material(energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.emission_enabled = true
	material.emission = colors.sample(1.0)
	material.emission_energy_multiplier = energy
	return material


## Soft rectangle: bright in the middle, fading to the edges.
func _halo_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_SQUARE
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
