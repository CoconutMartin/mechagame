extends SceneTree
## Boost Pack test (2026-10-31, user: "during boost, the outlets on the fins should glow and expel wind"). The
## player carries the Boost Pack: it is in the garage catalog with 1 aux slot and a boost bonus; its model has
## Outlet1..4 (wind out of the back) and OutletGlow1..4. Standing: no glow, no wind. Boosting (Shift + W held):
## glow and wind on every outlet, the louver flaps open. After the boost: both stop, the flaps close. Other packs get no outlets. Exits with code 1 on a
## failure. Headless (optional BOOST_SHOT=<png> with a window: a picture while boosting):
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_boost_pack.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const PACK := "res://data/parts/backpacks/backpack_boost.tres"
const OTHER_PACK := "res://data/parts/backpacks/backpack_medium.tres"

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


func _run() -> void:
	var pack := load(PACK) as BackPackPart
	var catalog := load("res://data/garage_catalog.tres") as GarageCatalog
	_check(pack in catalog.back_packs, "the Boost Pack is in the garage catalog")
	_check(pack.aux_slots == 1 and pack.get_mod_stat() == ModData.Stat.BOOST_THRUST, "1 aux slot, boost bonus")
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = pack
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var outlets := mech.get_node_or_null(^"BackPackOutlets") as BackPackOutlets
	_check(outlets != null and outlets._winds.size() == 4, "4 outlets on the Boost Pack")
	if outlets == null:
		_finish()
		return
	for i in 4:
		var outlet := outlets._model.find_child("Outlet%d" % (i + 1), true, false) as Node3D
		var glow := outlets._model.find_child("OutletGlow%d" % (i + 1), true, false) as MeshInstance3D
		# The wind leaves backward (mech +Z is back).
		var back := outlet.global_basis.y.normalized().dot(mech.global_basis.z.normalized())
		_check(back > 0.8, "Outlet%d blows backward (%.2f)" % [i + 1, back])
		_check(glow != null and glow.material_overlay == outlets._glow_material, "OutletGlow%d has the glow" % (i + 1))
	_check(outlets.amount < 0.01 and not outlets._winds[0].emitting, "standing: no glow, no wind")
	var flaps := mech.get_node_or_null(^"BackPackFlaps") as BackPackFlaps
	_check(flaps != null and flaps.get_flaps().size() >= 20, "louver flaps on the outlets (%d)" %
			(flaps.get_flaps().size() if flaps != null else 0))
	if flaps == null:
		_finish()
		return
	var flap := flaps.get_flaps()[0]
	var closed := flap.basis
	_check(flaps.amount < 0.01, "standing: flaps closed")
	var shot := OS.get_environment("BOOST_SHOT")
	if shot != "":
		root.get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_closed.png"))
	Input.action_press("boost")
	Input.action_press("move_forward")
	var boosted := false
	for i in 240:
		await _frames(1)
		if mech.is_boosting and outlets.amount > 0.95:
			boosted = true
			break
	var all_wind := true
	for wind in outlets._winds:
		all_wind = all_wind and wind.emitting
	_check(boosted, "boosting: full glow (%.2f)" % outlets.amount)
	_check(all_wind, "boosting: wind from every outlet")
	await _frames(20)
	var turned := rad_to_deg(closed.y.angle_to(flap.basis.y))
	_check(flaps.amount > 0.99 and absf(turned - flaps.open_angle_deg) < 2.0,
			"boosting: flaps open (%.0f degrees)" % turned)
	if shot != "":
		root.get_viewport().get_texture().get_image().save_png(shot)
	Input.action_release("boost")
	Input.action_release("move_forward")
	await _frames(90)
	_check(outlets.amount < 0.01 and not outlets._winds[0].emitting, "after the boost: glow and wind stop")
	_check(flaps.amount < 0.01 and flap.basis.is_equal_approx(closed), "after the boost: flaps closed")
	# Other packs have no outlets.
	loadout.back_pack = load(OTHER_PACK) as BackPackPart
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(30)
	_check(switcher.mech.get_node_or_null(^"BackPackOutlets") == null
			and switcher.mech.get_node_or_null(^"BackPackFlaps") == null, "the Aux Pack has no outlets or flaps")
	_finish()


func _finish() -> void:
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
