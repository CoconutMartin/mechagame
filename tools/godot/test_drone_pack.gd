extends SceneTree
## Drone Pack test (2026-10-31, user picture: "the circle thing on the side should be detachable, we'll make it to
## an attack drone"). The Drone Pack is in the garage catalog (1 aux slot, no bonus). Its model has Drone1 and
## Drone2: each one a single node that holds every mesh of its disc (so the game can take the drone off), a
## DroneDock1..2 empty at the same place, and Aux1. No boost outlets. At rest the drone discs do not overlap the
## mech's other meshes (DRONE_LIST=1 prints the meshes near them). Exits with code 1 on a failure.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_drone_pack.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const PACK := "res://data/parts/backpacks/backpack_drone.tres"
## The disc shape for the clearance check (m; the model: radius 0.52, thickness 0.34, less 3 cm).
const DISC_RADIUS := 0.49
const DISC_HALF_THICKNESS := 0.14

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


## World box of every mesh under node.
func _box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var aabb := mesh.global_transform * mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	return box


func _run() -> void:
	var pack := load(PACK) as BackPackPart
	var catalog := load("res://data/garage_catalog.tres") as GarageCatalog
	_check(pack in catalog.back_packs, "the Drone Pack is in the garage catalog")
	_check(pack.aux_slots == 1 and pack.get_mod_stat() == -1, "1 aux slot, no bonus")
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = pack
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var holder := mech.get_node_or_null(^"BackPackMount") as BackPackMount
	_check(holder != null and holder.model != null, "the pack is on the mech")
	if holder == null or holder.model == null:
		_finish()
		return
	var model := holder.model
	_check(model.find_child("Aux1", true, false) != null, "Aux1 hardpoint")
	_check(mech.get_node_or_null(^"BackPackOutlets") == null, "no boost outlets")
	var pack_meshes := model.find_children("*", "MeshInstance3D", true, false)
	for i in 2:
		var drone := model.find_child("Drone%d" % (i + 1), true, false) as Node3D
		var dock := model.find_child("DroneDock%d" % (i + 1), true, false) as Node3D
		_check(drone != null and dock != null, "Drone%d and DroneDock%d in the model" % [i + 1, i + 1])
		if drone == null or dock == null:
			continue
		var meshes := drone.find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() >= 15, "Drone%d holds its disc meshes (%d)" % [i + 1, meshes.size()])
		_check(drone.global_position.distance_to(dock.global_position) < 0.01, "Drone%d sits on its dock" % (i + 1))
		var side := (drone.global_position - mech.global_position).dot(mech.global_basis.x)
		_check(absf(side) > 0.8 and signf(side) == (-1.0 if i == 0 else 1.0),
				"Drone%d is on the %s side (%.2f m)" % [i + 1, "left" if i == 0 else "right", side])
		# No other mech mesh inside the disc's box (shrunk 5 cm).
		var box := _box(drone).grow(-0.05)
		var hits: Array[String] = []
		for mesh: MeshInstance3D in mech.find_children("*", "MeshInstance3D", true, false):
			if mesh in pack_meshes or not mesh.is_visible_in_tree():
				continue
			if not box.intersects(mesh.global_transform * mesh.get_aabb()) or mesh.mesh == null:
				continue
			# A box overlap is not enough (the torso box is big, the disc is round): count the mesh points inside
			# the disc (in the drone's frame: the axis is X).
			var inside := 0
			var to_drone := drone.global_transform.affine_inverse() * mesh.global_transform
			for p: Vector3 in mesh.mesh.get_faces():
				var q := to_drone * p
				if absf(q.x) < DISC_HALF_THICKNESS and Vector2(q.y, q.z).length() < DISC_RADIUS:
					inside += 1
			if inside > 0:
				hits.append("%s (%d points)" % [mesh.name, inside])
		if OS.get_environment("DRONE_LIST") == "1":
			print("Drone%d box %s near: %s" % [i + 1, box, hits])
		_check(hits.is_empty(), "Drone%d clears the mech at rest %s" % [i + 1, hits])
	_finish()


func _finish() -> void:
	print("drone pack test: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
