class_name MechHpIndicators
extends Node
## Puts the HP indicators (HpIndicator) of a rigged mech on its armor, from the layout's spots. Each
## indicator goes on the back face of its armor mesh (the side the camera sees), conforms to that
## face, and sits on the bone attachment of the mesh's bone, so it follows the animation.
## Placement is found once at the rest pose by rays at the mesh.

@export var hitboxes: SkeletalHitboxes
@export var health: MechHealth
@export var layout: HpIndicatorLayout
## Steepest armor face an indicator follows (degrees from straight back). Steeper faces get an
## indicator that faces straight back.
@export var max_tilt: float = 40.0
## Most the armor under the frame may rise or fall from flat for the indicator to fit (m).
@export var flat_tolerance: float = 0.02
## Clearance from bevels and edges around the frame (m).
@export var clearance: float = 0.04

## The indicators by part key.
var indicators: Dictionary = {}


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	if hitboxes.skeleton == null or layout == null:
		return
	for spot in layout.spots:
		var part := _part(spot.key)
		var mesh := _pick_mesh(part, spot) if part != null else null
		if mesh != null:
			_place(spot, mesh)


func _part(key: String) -> BoneHitPart:
	for part: BoneHitPart in hitboxes.parts.parts:
		if part.key == key:
			return part
	return null


## The largest mesh of the part on the spot's bone (inside the part's X range).
func _pick_mesh(part: BoneHitPart, spot: HpIndicatorSpot) -> MeshInstance3D:
	var skeleton := hitboxes.skeleton
	var best: MeshInstance3D = null
	var best_volume := 0.0
	for mesh: MeshInstance3D in hitboxes.part_meshes.get(part.key, []):
		if skeleton.get_bone_name(hitboxes.mesh_bones[mesh]) != spot.bone:
			continue
		var box := mesh.transform * mesh.get_aabb()
		var volume := box.size.x * box.size.y * box.size.z
		if volume > best_volume:
			best = mesh
			best_volume = volume
	return best


func _place(spot: HpIndicatorSpot, mesh: MeshInstance3D) -> void:
	var box := mesh.transform * mesh.get_aabb()
	var center := box.get_center()
	var aim := Vector3(center.x + spot.offset.x, center.y + spot.offset.y, box.position.z - 2.0)
	var faces := mesh.mesh.generate_triangle_mesh()
	var middle := _back_hit(mesh, faces, aim)
	if middle == Vector3.INF:
		return
	var indicator := HpIndicator.new()
	var reach := spot.size * 0.5 + indicator.frame
	# The armor face under the indicator (from 4 points around it), so one bevel or seam does not
	# tilt it. Too steep a face uses straight back.
	var hits: Array[Vector3] = []
	for shift: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP]:
		var hit := _back_hit(mesh, faces, aim + shift * reach)
		hits.append(hit if hit != Vector3.INF else middle)
	var normal := (hits[1] - hits[0]).cross(hits[3] - hits[2]).normalized()
	if normal.z > 0.0:
		normal = -normal
	if normal == Vector3.ZERO or normal.angle_to(Vector3.FORWARD) > deg_to_rad(max_tilt):
		normal = Vector3.FORWARD
	# In-plane axes from the part's own axes (model X), turned by the spot's roll.
	var side := (Vector3.RIGHT - normal * normal.dot(Vector3.RIGHT)).normalized()
	side = side.rotated(normal, deg_to_rad(spot.roll_degrees))
	var basis := Basis(side, normal.cross(side), normal)
	var scale_share := _fit(spot, mesh, faces, middle, basis, indicator.frame) if spot.fit_to_panel else 1.0
	var size := spot.size * scale_share
	# On the highest armor point under the frame, so no corner sinks in (the frame's sink covers
	# small gaps).
	var top := 0.0
	for hit in _frame_points(middle, basis, size * 0.5 + indicator.frame, mesh, faces, normal):
		top = maxf(top, (hit - middle).dot(normal))
	var place := Transform3D(basis, middle + normal * top)

	indicator.name = "HPIndicator_" + spot.key.replace(" ", "")
	indicator.health = health
	indicator.part_key = spot.key
	indicator.carrier = mesh
	indicator.size = size
	var bone: int = hitboxes.mesh_bones[mesh]
	hitboxes.get_attachment(bone).add_child(indicator)
	indicator.transform = hitboxes.skeleton.get_bone_global_rest(bone).affine_inverse() * place
	indicators[spot.key] = indicator


## Share of the spot size (1 down to min_fit) whose frame plus clearance lies on flat armor.
func _fit(spot: HpIndicatorSpot, mesh: MeshInstance3D, faces: TriangleMesh, middle: Vector3,
		basis: Basis, frame_width: float) -> float:
	var share := 1.0
	while share > spot.min_fit:
		var reach := spot.size * share * 0.5 + frame_width + clearance
		var flat := true
		for hit in _frame_points(middle, basis, reach, mesh, faces, basis.z):
			if absf((hit - middle).dot(basis.z)) > flat_tolerance:
				flat = false
				break
		if flat:
			return share
		share -= 0.05
	return spot.min_fit


## Armor points under the frame's corners and edge middles (missed rays are left out).
func _frame_points(middle: Vector3, basis: Basis, reach: float, mesh: MeshInstance3D,
		faces: TriangleMesh, normal: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for u in [-1.0, 0.0, 1.0]:
		for v in [-1.0, 0.0, 1.0]:
			if u == 0.0 and v == 0.0:
				continue
			var at: Vector3 = middle + (basis.x * u + basis.y * v) * reach
			var hit := _surface_hit(mesh, faces, at + normal * 1.0, -normal)
			if hit != Vector3.INF:
				points.append(hit)
	return points


## Where a ray from behind (skeleton space: +Z forward) at this point meets the mesh's back,
## or Vector3.INF on a miss.
func _back_hit(mesh: MeshInstance3D, faces: TriangleMesh, from: Vector3) -> Vector3:
	return _surface_hit(mesh, faces, from, Vector3.BACK)


func _surface_hit(mesh: MeshInstance3D, faces: TriangleMesh, from: Vector3, direction: Vector3) -> Vector3:
	var to_mesh := mesh.transform.affine_inverse()
	var hit := faces.intersect_ray(to_mesh * from, (to_mesh.basis * direction).normalized())
	if hit.is_empty():
		return Vector3.INF
	return mesh.transform * (hit.position as Vector3)
