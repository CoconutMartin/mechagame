extends RefCounted
## The new Haliya HLY-101 pieces where the legs-aligned skeleton is longer than Haliya's own (DESIGN "HLY refit decision"; user
## choice 2026-11-08 "Legs only": the waist and neck pieces of the full refit are gone, Haliya keeps its own waist and neck): an ankle
## block on each foot, which fills the 0.25 m from Haliya's ankle height to SGG's. Low poly, faceted, in Haliya's colors (dark grey
## armor, tan accents), each rigid on the foot bone. Places come from the refit pieces around it (their boxes at the target rest), so
## the block closes the gap with some overlap at both ends.
## Used by tools/godot/refit_haliya_parts.gd (Connectors.build). Space: Godot skeleton space at rest (+Z is the mech front).

const Kit := preload("res://tools/godot/haliya_mesh_kit.gd")
const ARMOR := "hly_armor"
const TAN := "hly_tan"

## How far (m) the ankle block reaches up into the ankle wheel, so no gap opens when the joint turns.
const TUCK := 0.12
## Ankle block: inset (m) from the outer faces of the ankle guards, and from the heel and the instep; how much the top narrows.
const ANKLE_INSET := 0.04
const ANKLE_TOP_SCALE := Vector2(0.86, 0.78)
## Ankle block: how far (m) it reaches down into the foot.
const ANKLE_FOOT_TUCK := 0.25


## Part -> Array of pieces ({name, bone, surfaces: [{arrays, material}], bind_names}).
static func build(boxes: Dictionary, _rest: Dictionary, materials: Dictionary) -> Dictionary:
	var legs := []
	for side in ["L", "R"]:
		_ankle(boxes, materials, legs, side)
	return {"legs": legs}


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
