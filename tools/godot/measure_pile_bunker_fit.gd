extends SceneTree
## Pile Bunker fit probe (2026-10-26, new model): holds the Pile Bunker (SIDE=R or L), standing, and prints in the
## Mount space: the fist, the wrist pin and the elbow, the nose and the model's bracket axis. Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_pile_bunker_fit.gd

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var side := OS.get_environment("SIDE") if OS.has_environment("SIDE") else "R"
	var data := load("res://data/weapons/pile_bunker.tres") as WeaponData
	loadout.weapon_right = data if side == "R" else null
	loadout.weapon_left = data if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(120)
	var weapons := switcher.mech.find_child("WeaponController", true, false) as WeaponController
	var bunker := (weapons.right_weapon if side == "R" else weapons.left_weapon) as PileBunkerWeapon
	var mount := bunker.get_model()
	var inv := mount.global_transform.affine_inverse()
	var control := switcher.mech.find_child("MechHandControl", true, false) as MechHandControl
	var hand := control._sides[side].hand as MechHand
	print("%s fist (hand origin) in Mount space: %s" % [side, inv * hand.global_position])
	print("%s forearm joint origin in Mount space: %s" % [side, inv * mount.get_parent().global_position])
	print("%s nose in Mount space: %s" % [side, inv * bunker._nose.global_position])
	var axis := mount.find_child("Mount", true, false) as Node3D
	if axis:
		print("%s model bracket axis in Mount space: %s" % [side, inv * axis.global_position])
	# Meshes of the body that come within 0.25 m of the hand.
	var near := 0
	for mesh: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		if box.grow(0.25).has_point(hand.global_position):
			near += 1
			print("  near the fist: %s" % mesh.name)
	print("%s meshes near the fist: %d" % [side, near])
	quit()
