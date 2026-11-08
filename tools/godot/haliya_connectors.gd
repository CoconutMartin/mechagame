extends RefCounted
## The new Haliya HLY-101 pieces where the SGG-101 skeleton is longer (user decision 2026-11-08, DESIGN "HLY refit decision"):
## the waist between the pelvis and the chest, the neck between the chest and the head, and an ankle block on each foot. Low poly,
## faceted, in Haliya's colors (dark grey armor, tan accents, near black joints), each rigid on one bone. Places come from the refit
## pieces around them (their boxes at the SGG rest), so the pieces close the gaps with some overlap at both ends.
## Used by tools/godot/refit_haliya_parts.gd (Connectors.build). Space: Godot skeleton space at rest (+Z is the mech front).

const Kit := preload("res://tools/godot/haliya_mesh_kit.gd")
const ARMOR := "hly_armor"
const TAN := "hly_tan"
const JOINT := "hly_joint"

## How far (m) a connector reaches into the piece above and below it, so no gap opens when the joint turns.
const TUCK := 0.12
## Waist: half width and half depth (m) of the collar on the pelvis, of the joint column, and of the front plate (top, bottom).
const WAIST_COLLAR_HALF := Vector2(0.34, 0.36)
const WAIST_COLLAR_HEIGHT := 0.20
const WAIST_LINK_HALF := Vector2(0.25, 0.27)
const WAIST_PLATE_HALF_WIDTH_TOP := 0.50
const WAIST_PLATE_HALF_WIDTH_LOW := 0.24
## Waist front plate: its back and front face (z, m) at the top and at the bottom; it slopes back toward the pelvis.
const WAIST_PLATE_Z_TOP := Vector2(0.22, 0.52)
const WAIST_PLATE_Z_LOW := Vector2(0.20, 0.40)
## Waist back plate on the pelvis: half width and its inner and outer face (z, m, toward the back is negative).
const WAIST_BACK_HALF_WIDTH := 0.30
const WAIST_BACK_Z := Vector2(-0.30, -0.70)
## Neck: half width and half depth of the joint column and of the tan collar band, and the band height (m).
const NECK_LINK_HALF := Vector2(0.18, 0.17)
const NECK_BAND_HALF := Vector2(0.25, 0.24)
const NECK_BAND_HEIGHT := 0.13
## Ankle block: inset (m) from the outer faces of the ankle guards, and from the heel and the instep; how much the top narrows.
const ANKLE_INSET := 0.04
const ANKLE_TOP_SCALE := Vector2(0.86, 0.78)
## Ankle block: how far (m) it reaches down into the foot.
const ANKLE_FOOT_TUCK := 0.25


## Part -> Array of pieces ({name, bone, surfaces: [{arrays, material}], bind_names}).
static func build(boxes: Dictionary, _rest: Dictionary, materials: Dictionary) -> Dictionary:
	var core := []
	var legs := []
	_waist(boxes, materials, core, legs)
	_neck(boxes, materials, core)
	for side in ["L", "R"]:
		_ankle(boxes, materials, legs, side)
	return {"core": core, "legs": legs}


static func _piece(name: String, bone: String, material_name: String, rings: Array, materials: Dictionary) -> Dictionary:
	var arrays := Kit.bind_one(Kit.loft(rings), 0)
	return {"name": name, "bone": bone, "surfaces": [{"arrays": arrays, "material": materials.get(material_name)}], "bind_names": [bone]}


## A horizontal slab ring at height y: half width hx, from z_in to z_out, the two corners on the z_out side cut by chamfer.
static func _slab(y: float, cx: float, hx: float, z_in: float, z_out: float, chamfer: float) -> PackedVector3Array:
	var s := signf(z_out - z_in)
	var pts := PackedVector3Array()
	for p: Vector2 in [Vector2(-hx, z_in), Vector2(hx, z_in), Vector2(hx, z_out - s * chamfer), Vector2(hx - chamfer, z_out),
			Vector2(-hx + chamfer, z_out), Vector2(-hx, z_out - s * chamfer)]:
		pts.append(Vector3(cx + p.x, y, p.y))
	return pts


static func _waist(boxes: Dictionary, materials: Dictionary, core: Array, legs: Array) -> void:
	var pelvis: AABB = boxes["Core_pelvis_block"]
	var chest: AABB = boxes["Core_waist"]
	var front_top: AABB = boxes["Core_chest_lower"]
	var back_top: AABB = boxes["Core_waist_back"]
	var back_low: AABB = boxes["Core_pelvis_back"]
	var cx := pelvis.get_center().x
	var cz := pelvis.get_center().z
	var low := pelvis.end.y
	var high := chest.position.y
	# Collar on the pelvis block (pelvis bone): the waist turns inside it.
	var c0 := Vector3(cx, low - TUCK, cz)
	var collar := [Kit.octagon(c0, WAIST_COLLAR_HALF.x, WAIST_COLLAR_HALF.y, 0.4),
		Kit.octagon(c0 + Vector3(0, TUCK + WAIST_COLLAR_HEIGHT * 0.6, 0), WAIST_COLLAR_HALF.x, WAIST_COLLAR_HALF.y, 0.4),
		Kit.octagon(c0 + Vector3(0, TUCK + WAIST_COLLAR_HEIGHT, 0), WAIST_COLLAR_HALF.x - 0.05, WAIST_COLLAR_HALF.y - 0.05, 0.45)]
	legs.append(_piece("Legs_waist_collar", "pelvis", ARMOR, collar, materials))
	# Back plate on the pelvis: from the rear pelvis plate up behind the waist, under the chest's back plate.
	var back := [_slab(back_low.end.y - TUCK, cx, WAIST_BACK_HALF_WIDTH, WAIST_BACK_Z.x, WAIST_BACK_Z.y - 0.10, 0.08),
		_slab(back_top.position.y + TUCK, cx, WAIST_BACK_HALF_WIDTH - 0.03, WAIST_BACK_Z.x, WAIST_BACK_Z.y, 0.08)]
	legs.append(_piece("Legs_waist_back", "pelvis", ARMOR, back, materials))
	# Joint column on the torso: from inside the collar to inside the chest's waist block.
	var l0 := Vector3(cx, low + WAIST_COLLAR_HEIGHT - TUCK, cz)
	var link := [Kit.octagon(l0, WAIST_LINK_HALF.x, WAIST_LINK_HALF.y, 0.4),
		Kit.octagon(Vector3(cx, high + TUCK, cz), WAIST_LINK_HALF.x, WAIST_LINK_HALF.y, 0.4)]
	core.append(_piece("Core_waist_link", "torso", JOINT, link, materials))
	# Front plate on the torso, under the tan chest plate: narrow at the bottom, sloping back to the pelvis.
	var p_low := low + WAIST_COLLAR_HEIGHT * 0.5
	var p_high := front_top.position.y + 0.06
	var plate := [_slab(p_low, cx, WAIST_PLATE_HALF_WIDTH_LOW, WAIST_PLATE_Z_LOW.x, WAIST_PLATE_Z_LOW.y, 0.06),
		_slab(lerpf(p_low, p_high, 0.55), cx, lerpf(WAIST_PLATE_HALF_WIDTH_LOW, WAIST_PLATE_HALF_WIDTH_TOP, 0.7), WAIST_PLATE_Z_TOP.x, WAIST_PLATE_Z_TOP.y - 0.03, 0.09),
		_slab(p_high, cx, WAIST_PLATE_HALF_WIDTH_TOP, WAIST_PLATE_Z_TOP.x, WAIST_PLATE_Z_TOP.y, 0.09)]
	core.append(_piece("Core_waist_plate", "torso", ARMOR, plate, materials))
	# Tan rib down the middle of the front plate.
	var rib := [_slab(p_low + 0.06, cx, 0.06, WAIST_PLATE_Z_LOW.y - 0.06, WAIST_PLATE_Z_LOW.y + 0.04, 0.03),
		_slab(p_high - 0.04, cx, 0.08, WAIST_PLATE_Z_TOP.y - 0.06, WAIST_PLATE_Z_TOP.y + 0.05, 0.03)]
	core.append(_piece("Core_waist_rib", "torso", TAN, rib, materials))


static func _neck(boxes: Dictionary, materials: Dictionary, core: Array) -> void:
	var seat: AABB = boxes["Core_neck_seat"]
	var neck: AABB = boxes["Head_neck"]
	var cx := neck.get_center().x
	var cz := neck.get_center().z
	var low := seat.end.y
	var link := [Kit.octagon(Vector3(cx, low - TUCK, cz), NECK_LINK_HALF.x, NECK_LINK_HALF.y, 0.4),
		Kit.octagon(Vector3(cx, neck.position.y + TUCK * 1.5, cz), NECK_LINK_HALF.x, NECK_LINK_HALF.y, 0.4)]
	core.append(_piece("Core_neck_link", "torso", JOINT, link, materials))
	var b0 := Vector3(cx, low - 0.02, cz)
	var band := [Kit.octagon(b0, NECK_BAND_HALF.x, NECK_BAND_HALF.y, 0.4),
		Kit.octagon(b0 + Vector3(0, NECK_BAND_HEIGHT * 0.6, 0), NECK_BAND_HALF.x, NECK_BAND_HALF.y, 0.4),
		Kit.octagon(b0 + Vector3(0, NECK_BAND_HEIGHT, 0), NECK_BAND_HALF.x - 0.04, NECK_BAND_HALF.y - 0.04, 0.45)]
	core.append(_piece("Core_neck_band", "torso", TAN, band, materials))


static func _ankle(boxes: Dictionary, materials: Dictionary, legs: Array, side: String) -> void:
	var guard_in: AABB = boxes["Legs_ankle_guard_in_" + side]
	var guard: AABB = boxes["Legs_ankle_guard_" + side]
	var wheel: AABB = boxes["Legs_ankle_" + side]
	var heel_tan: AABB = boxes["Legs_heel_tan_" + side]
	var instep: AABB = boxes["Legs_instep_" + side]
	var x0 := minf(guard_in.position.x, guard.position.x) + ANKLE_INSET
	var x1 := maxf(guard_in.end.x, guard.end.x) - ANKLE_INSET
	var z0 := heel_tan.position.z + ANKLE_INSET
	var z1 := instep.position.z + ANKLE_INSET
	var centre := Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
	var hx := (x1 - x0) * 0.5
	var hz := (z1 - z0) * 0.5
	var y0 := heel_tan.end.y - ANKLE_FOOT_TUCK
	var y1 := wheel.position.y + TUCK
	var y_mid := lerpf(y0, y1, 0.55)
	var block := [Kit.octagon(centre + Vector3(0, y0, 0), hx, hz, 0.35),
		Kit.octagon(centre + Vector3(0, y_mid, 0), hx, hz, 0.35),
		Kit.octagon(centre + Vector3(0, y1, 0), hx * ANKLE_TOP_SCALE.x, hz * ANKLE_TOP_SCALE.y, 0.45)]
	legs.append(_piece("Legs_ankle_block_" + side, "foot_" + side, ARMOR, block, materials))
	# Tan plate on the front face, sloping back with the block's top.
	var front_mid := centre.z + hz
	var front_top := centre.z + hz * ANKLE_TOP_SCALE.y
	var plate := [_slab(y_mid - 0.10, centre.x, hx * 0.42, front_mid - 0.10, front_mid + 0.05, 0.03),
		_slab(y1 - 0.03, centre.x, hx * 0.34, front_top - 0.10, front_top + 0.05, 0.03)]
	legs.append(_piece("Legs_ankle_tan_" + side, "foot_" + side, TAN, plate, materials))
