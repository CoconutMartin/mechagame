extends SceneTree
## Checks the Boost Pack data and model nodes (2026-10-31).
##   godot --headless --path . --script res://tools/godot/check_boost_pack.gd

func _init() -> void:
	var fails := 0
	var cat: GarageCatalog = load("res://data/garage_catalog.tres")
	var pack: BackPackPart = null
	for p: BackPackPart in cat.back_packs:
		if p.display_name == "Boost Pack":
			pack = p
	if pack == null:
		print("FAIL Boost Pack not in the garage catalog")
		quit(1)
		return
	var model := pack.scene.instantiate()
	var names := ["Mount", "Aux1", "Lamp", "Thruster1", "Thruster2", "Thruster3", "Thruster4", "Thruster5"]
	for n: String in names:
		var ok := model.find_child(n, true, false) != null
		print(("PASS " if ok else "FAIL ") + n)
		fails += 0 if ok else 1
	var ok_stat := pack.get_mod_stat() == ModData.Stat.BOOST_THRUST and pack.aux_slots == 1
	print(("PASS " if ok_stat else "FAIL ") + "boost bonus and 1 aux slot")
	fails += 0 if ok_stat else 1
	model.free()
	print("RESULT: %d failures" % fails)
	quit(fails)
