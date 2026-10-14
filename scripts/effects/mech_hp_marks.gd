class_name MechHpMarks
extends Node
## HP stripes on the mech's own armor (user request 2026-10-14: the HP shows on the body parts, not as
## text). One glowing stripe per HP part, set into the back of the part's largest mesh (the side the
## camera sees), so every rigged model gets them without setup. The stripe shortens with the part HP
## and its color goes from green (full) to orange (half) to red (low). Shown on the player mech only.
## Torso parts that share one mesh (Torso C, L, R) use their X range of it (BoneHitPart.min_x, max_x).

@export var mech: Mech
@export var hitboxes: SkeletalHitboxes
@export var health: MechHealth
## HP fraction to color: 1 = green, 0.5 = orange, 0.1 = red.
@export var colors: Gradient
## Stripe length as a part of the part's width or height, and its limits (meters).
@export var length_share: float = 0.5
@export var min_length: float = 0.5
@export var max_length: float = 1.4
## Stripe width and thickness (meters), and its lift off the armor surface.
@export var width: float = 0.16
@export var thickness: float = 0.05
@export var lift: float = 0.03
## Shortest stripe part at low HP (0 to 1 of the full length), so a red stripe still shows.
@export var min_fill: float = 0.12
## Color of the empty part of the stripe.
@export var empty_color: Color = Color(0.06, 0.07, 0.06)

## Part key -> [fill node, fill material, mark root].
var _marks := {}


func _ready() -> void:
	if colors == null:
		colors = Gradient.new()
		colors.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
		colors.colors = PackedColorArray([Color(0.9, 0.08, 0.05), Color(0.95, 0.12, 0.05),
				Color(1.0, 0.55, 0.05), Color(0.2, 1.0, 0.25)])
	_build.call_deferred()


func _process(_delta: float) -> void:
	var shown := mech.is_in_group(&"player") and not mech.is_wrecked
	for key: String in _marks:
		var mark: Array = _marks[key]
		var root := mark[2] as Node3D
		var fraction := health.get_fraction(key)
		root.visible = shown and fraction > 0.0
		if not root.visible:
			continue
		var fill := mark[0] as Node3D
		fill.scale = Vector3(1.0, 1.0, maxf(fraction, min_fill))
		(mark[1] as StandardMaterial3D).albedo_color = colors.sample(fraction)


## One stripe per HP part: on the back of the part's largest mesh, at its center.
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
			_add_mark(part.key, best, best_box)


func _add_mark(key: String, mesh: MeshInstance3D, box: AABB) -> void:
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
	var length := clampf(size * length_share, min_length, max_length)
	along = (along - normal * along.dot(normal)).normalized()
	var side := normal.cross(along).normalized()
	# Mark space: +Z along the stripe (from its start), +Y out of the armor.
	var start := point + normal * lift - along * length * 0.5
	var place := Transform3D(Basis(side, normal, along), start)

	var bone: int = hitboxes.mesh_bones[mesh]
	var root := Node3D.new()
	root.name = "HpMark_" + key.replace(" ", "")
	hitboxes.get_attachment(bone).add_child(root)
	root.transform = hitboxes.skeleton.get_bone_global_rest(bone).affine_inverse() * place
	var back_material := _material(empty_color)
	root.add_child(_bar(length, back_material, 0.0))
	var fill := Node3D.new()
	root.add_child(fill)
	var fill_material := _material(colors.sample(1.0))
	fill.add_child(_bar(length, fill_material, thickness * 0.4))
	_marks[key] = [fill, fill_material, root]


## A stripe box from z 0 to z length, raised by rise.
func _bar(length: float, material: StandardMaterial3D, rise: float) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(width, thickness, length)
	var bar := MeshInstance3D.new()
	bar.mesh = box
	bar.material_override = material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position = Vector3(0.0, rise, length * 0.5)
	return bar


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
