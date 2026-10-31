extends SceneTree
## Shield Bunker block test (2026-10-31, user: "it should also block like a shield"). The player holds the Shield
## Bunker (Pile Bunker 5) in one hand. Shots come from the outer side of that arm (straight and 45 degrees from the
## front) at points along the forearm; each shot must hit the Shield Bunker's hit box ("Weapon R" or "Weapon L")
## first, not the arm or the body. The upper arm and the shoulder are not covered (a forearm shield at rest). The same shots with the first Pile Bunker show the difference.
## Exits with code 1 on a failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_shield_bunker_block.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const SHIELD := "res://data/weapons/pile_bunker_5.tres"
const PLAIN := "res://data/weapons/pile_bunker.tres"
## Least share of the shots that must hit the shield.
const MIN_SHARE := 0.9

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in current_scene.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	for side in ["R", "L"]:
		for file in [SHIELD, PLAIN]:
			await _case(switcher, side, file)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _case(switcher: LoadoutSwitcher, side: String, file: String) -> void:
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(file) if side == "R" else null
	loadout.weapon_left = load(file) if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(90)
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var bones := ["forearm_" + side, "hand_" + side]
	var points: Array[Vector3] = []
	for i in bones.size() - 1:
		var a := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bones[i])).origin
		var b := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bones[i + 1])).origin
		for t in [0.1, 0.3, 0.5, 0.7, 0.9]:
			points.append(a.lerp(b, t))
	var basis := player.global_basis
	var out := basis.x * (1.0 if side == "R" else -1.0)
	var forward := -basis.z
	var space := player.get_world_3d().direct_space_state
	var keys := {}
	var blocked := 0
	var shots := 0
	for from_dir in [out, (out + forward).normalized()]:
		for p in points:
			var query := PhysicsRayQueryParameters3D.create(p + from_dir * 30.0, p, PartHitbox.LAYER)
			var hit := space.intersect_ray(query)
			shots += 1
			var key := (hit.collider as PartHitbox).part_key if not hit.is_empty() and hit.collider is PartHitbox else "-"
			keys[key] = int(keys.get(key, 0)) + 1
			if OS.has_environment("TRACE"):
				print("  %s dir %s p %s -> %s at %s" % [side, from_dir.snappedf(0.01), (p - player.global_position).snappedf(0.01), key, (hit.position - player.global_position).snappedf(0.01) if not hit.is_empty() else null])
			if key == "Weapon " + side:
				blocked += 1
	var share := float(blocked) / shots
	var name := (load(file) as WeaponData).display_name
	if file == SHIELD:
		var ok := share >= MIN_SHARE
		print(("ok   " if ok else "FAIL ") + "%s %s: %d of %d shots on the shield %s" % [name, side, blocked, shots, keys])
		if not ok:
			_failures += 1
	else:
		print("info %s %s: %d of %d shots on the weapon %s" % [name, side, blocked, shots, keys])
