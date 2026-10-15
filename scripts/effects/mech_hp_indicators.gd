class_name MechHpIndicators
extends Node
## Puts the HP gauges (HpIndicator) of a rigged mech on its armor, from the layout's spots. Each
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
		if part == null:
			continue
		var picked := _pick_mesh(part, spot)
		if picked[0] != null:
			_place(spot, picked[0], picked[1])


func _part(key: String) -> BoneHitPart:
	for part: BoneHitPart in hitboxes.parts.parts:
		if part.key == key:
			return part
	return null


## The mesh on the spot's bone with the most volume inside the part's X range (one torso mesh holds
## the center and side torsos), and that clipped box. [null, AABB()] when none.
func _pick_mesh(part: BoneHitPart, spot: HpIndicatorSpot) -> Array:
	var skeleton := hitboxes.skeleton
	var cut := AABB(Vector3(part.min_x, -1000.0, -1000.0), Vector3(part.max_x - part.min_x, 2000.0, 2000.0))
	var best: MeshInstance3D = null
	var best_box := AABB()
	var best_volume := 0.0
	for mesh: MeshInstance3D in hitboxes.mesh_bones:
		if skeleton.get_bone_name(hitboxes.mesh_bones[mesh]) != spot.bone:
			continue
		var box := (mesh.transform * mesh.get_aabb()).intersection(cut)
		var volume := box.size.x * box.size.y * box.size.z
		if volume > best_volume:
			best = mesh
			best_box = box
			best_volume = volume
	return [best, best_box]


func _place(spot: HpIndicatorSpot, mesh: MeshInstance3D, box: AABB) -> void:
	var center := box.get_center()
	var aim := Vector3(center.x + spot.offset.x, center.y + spot.offset.y, box.position.z - 2.0)
	var faces := mesh.mesh.generate_triangle_mesh()
	var middle := _back_hit(mesh, faces, aim)
	if middle == Vector3.INF:
		return
	var indicator := HpIndicator.new()
	indicator.rim *= spot.frame_scale
	indicator.bezel *= spot.frame_scale
	indicator.lip *= spot.frame_scale
	indicator.frame_height *= maxf(spot.frame_scale, 0.5)
	indicator.frame_sink *= spot.frame_scale
	indicator.cell_margin = spot.cell_margin
	# Small windows get a smaller corner radius, so they stay square.
	indicator.corner = minf(indicator.corner, minf(spot.length, spot.height) * 0.15)
	var frame_width := indicator.lip + indicator.bezel + indicator.rim
	# Size on the armor (model X, Y): a vertical gauge runs up.
	var extent := Vector2(spot.height, spot.length) if spot.vertical else Vector2(spot.length, spot.height)
	var reach := extent * 0.5 + Vector2.ONE * frame_width
	# The armor face under the gauge (from 4 points around it), so one bevel or seam does not
	# tilt it. Too steep a face uses straight back.
	var hits: Array[Vector3] = []
	for shift: Vector3 in [Vector3.LEFT * reach.x, Vector3.RIGHT * reach.x, Vector3.DOWN * reach.y,
			Vector3.UP * reach.y]:
		var hit := _back_hit(mesh, faces, aim + shift)
		hits.append(hit if hit != Vector3.INF else middle)
	var normal := (hits[1] - hits[0]).cross(hits[3] - hits[2]).normalized()
	if normal.z > 0.0:
		normal = -normal
	if normal == Vector3.ZERO or normal.angle_to(Vector3.FORWARD) > deg_to_rad(max_tilt):
		normal = Vector3.FORWARD
	# Along the part's own X axis, toward the fill end (HpIndicator keeps it level in the game).
	var along := Vector3.LEFT if not spot.fill_to_left else Vector3.RIGHT
	var side := (along - normal * normal.dot(along)).normalized()
	var basis := Basis(side, normal.cross(side), normal)
	var share := _fit(spot, extent, mesh, faces, middle, basis, frame_width) if spot.fit_to_panel else 1.0
	# On the highest armor point under the frame, so no corner sinks in (the frame's sink covers
	# small gaps).
	var top := 0.0
	var frame_reach := extent * share * 0.5 + Vector2.ONE * frame_width
	for hit in _frame_points(middle, basis, frame_reach, mesh, faces):
		top = maxf(top, (hit - middle).dot(normal))
	top -= spot.recess * minf(spot.length, spot.height)
	var place := Transform3D(basis, middle + normal * top)

	indicator.name = "HPIndicator_" + spot.key.replace(" ", "")
	indicator.health = health
	indicator.part_key = spot.key
	indicator.carrier = mesh
	indicator.length = spot.length * share
	indicator.height = spot.height * share
	indicator.cells = spot.cells
	indicator.vertical = spot.vertical
	indicator.continuous = spot.continuous
	indicator.bar_share = spot.bar_share
	indicator.cell_round = spot.cell_round
	var bone: int = hitboxes.mesh_bones[mesh]
	hitboxes.get_attachment(bone).add_child(indicator)
	indicator.transform = hitboxes.skeleton.get_bone_global_rest(bone).affine_inverse() * place
	indicators[spot.key] = indicator


## Share of the spot size (1 down to min_fit) whose frame plus clearance lies on flat armor.
func _fit(spot: HpIndicatorSpot, extent: Vector2, mesh: MeshInstance3D, faces: TriangleMesh, middle: Vector3,
		basis: Basis, frame_width: float) -> float:
	var share := 1.0
	while share > spot.min_fit:
		var reach := extent * share * 0.5 + Vector2.ONE * (frame_width + clearance)
		var flat := true
		for hit in _frame_points(middle, basis, reach, mesh, faces):
			if absf((hit - middle).dot(basis.z)) > flat_tolerance:
				flat = false
				break
		if flat:
			return share
		share -= 0.05
	return spot.min_fit


## Armor points on a 5 x 5 grid under the gauge and its frame (missed rays are left out).
func _frame_points(middle: Vector3, basis: Basis, reach: Vector2, mesh: MeshInstance3D,
		faces: TriangleMesh) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for u in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for v in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var at: Vector3 = middle + basis.x * u * reach.x + basis.y * v * reach.y
			var hit := _surface_hit(mesh, faces, at + basis.z, -basis.z)
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
