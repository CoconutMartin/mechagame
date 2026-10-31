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
const QUAD_PACK := "res://data/parts/backpacks/backpack_quad.tres"
const POWER_PACK := "res://data/parts/backpacks/backpack_power.tres"

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
	var bar := mech.get_node_or_null(^"BackPackEnergyBar") as BackPackEnergyBar
	_check(bar != null, "the energy bar is on the pack")
	if bar == null:
		_finish()
		return
	await _frames(2)
	var full := bar.get_color()
	_check(full.is_equal_approx(bar.full_color), "full energy: bright light blue")
	var saved := mech.energy.current
	mech.energy.current = mech.energy.capacity * 0.5
	await _frames(1)
	var half := bar.get_color()
	mech.energy.current = 0.0
	await _frames(1)
	var empty := bar.get_color()
	_check(half.get_luminance() < full.get_luminance() and empty.get_luminance() < half.get_luminance()
			and empty.is_equal_approx(bar.empty_color), "the bar dims toward empty (%.2f, %.2f, %.2f)" %
			[full.get_luminance(), half.get_luminance(), empty.get_luminance()])
	# Empty: two blinks (on, off, on, off), then the bar follows the energy again and brightens as it recharges.
	mech.energy.depleted.emit()
	var seen: Array[bool] = []
	var step := bar.blink_period * 0.5
	for i in bar.blink_count * 2:
		await create_timer(step * 0.5).timeout
		seen.append(bar.get_color().is_equal_approx(bar.blink_color))
		await create_timer(step * 0.5).timeout
	_check(seen == [true, false, true, false], "empty: the bar blinks twice %s" % [seen])
	await create_timer(0.2).timeout
	var after := bar.get_color()
	var follows := bar.empty_color.lerp(bar.full_color, pow(bar.fraction, bar.fade_curve))
	_check(not bar.is_blinking() and after.is_equal_approx(follows),
			"after the blinks: the bar follows the energy again (energy %.2f)" % bar.fraction)
	mech.energy.current = mech.energy.capacity * 0.3
	await _frames(1)
	var low := bar.get_color().get_luminance()
	mech.energy.current = mech.energy.capacity * 0.7
	await _frames(1)
	_check(bar.get_color().get_luminance() > low, "recharging: the bar gets brighter")
	mech.energy.current = saved
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
			and switcher.mech.get_node_or_null(^"BackPackFlaps") == null
			and switcher.mech.get_node_or_null(^"BackPackEnergyBar") == null,
			"the Aux Pack has no outlets, flaps or energy bar")
	# The Quad Booster: four nozzle outlets that point backward, glow and wind while boosting, no flaps, no bar.
	var quad := load(QUAD_PACK) as BackPackPart
	_check(quad in catalog.back_packs and quad.get_mod_stat() == ModData.Stat.BOOST_THRUST and quad.aux_slots == 1,
			"the Quad Booster is in the catalog (1 aux slot, boost bonus)")
	loadout.back_pack = quad
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(30)
	mech = switcher.mech
	outlets = mech.get_node_or_null(^"BackPackOutlets") as BackPackOutlets
	_check(outlets != null and outlets._winds.size() == 4, "4 nozzle outlets on the Quad Booster")
	var petals := mech.get_node_or_null(^"BackPackFlaps") as BackPackFlaps
	_check(petals != null and petals.get_flaps().size() == 40, "40 jet nozzle petals (%d)" %
			(petals.get_flaps().size() if petals != null else 0))
	var quad_bar := mech.get_node_or_null(^"BackPackEnergyBar") as BackPackEnergyBar
	_check(quad_bar != null, "the Quad Booster's horizontal bar is the energy bar")
	var petal: Node3D = petals.get_flaps()[0] if petals != null else null
	var petal_closed := petal.basis if petal != null else Basis()
	if outlets != null:
		var all_back := true
		for i in 4:
			var outlet := outlets._model.find_child("Outlet%d" % (i + 1), true, false) as Node3D
			all_back = all_back and outlet.global_basis.y.normalized().dot(mech.global_basis.z.normalized()) > 0.99
		_check(all_back, "the nozzles blow straight backward")
		Input.action_press("boost")
		Input.action_press("move_forward")
		for i in 240:
			await _frames(1)
			if mech.is_boosting and outlets.amount > 0.95:
				break
		_check(outlets.amount > 0.95 and outlets._winds[3].emitting, "Quad Booster boosting: glow and wind")
		if petal != null:
			await _frames(20)
			var opened := rad_to_deg(petal_closed.y.angle_to(petal.basis.y))
			_check(absf(opened - petals.get_open_angle(0)) < 2.0, "boosting: the nozzles open (%.0f degrees)" % opened)
		var quad_shot := OS.get_environment("QUAD_SHOT")
		if quad_shot != "":
			root.get_viewport().get_texture().get_image().save_png(quad_shot)
		Input.action_release("boost")
		Input.action_release("move_forward")
		await _frames(90)
		if petal != null:
			_check(petal.basis.is_equal_approx(petal_closed), "after the boost: the nozzles close")
	# The Power Pack (energy support): energy capacity bonus, its model on the mech, no boost outlets.
	var power := load(POWER_PACK) as BackPackPart
	_check(power in catalog.back_packs and power.get_mod_stat() == ModData.Stat.ENERGY_CAPACITY
			and power.aux_slots == 1, "the Power Pack is in the catalog (1 aux slot, energy bonus)")
	loadout.back_pack = power
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(30)
	var holder := switcher.mech.get_node_or_null(^"BackPackMount") as BackPackMount
	_check(holder != null and is_instance_valid(holder.model)
			and switcher.mech.get_node_or_null(^"BackPackOutlets") == null, "the Power Pack model is on the mech")
	var glow := switcher.mech.get_node_or_null(^"BackPackEnergyBar") as BackPackEnergyBar
	_check(glow != null and glow.get_cables().size() == 6, "6 energy cables on the Power Pack (%d)" %
			(glow.get_cables().size() if glow != null else 0))
	if glow != null:
		var energy := switcher.mech.energy
		energy.current = energy.capacity
		await _frames(1)
		var bright := glow.get_cable_glow()
		energy.current = energy.capacity * 0.3
		await _frames(1)
		var dim := glow.get_cable_glow()
		_check(bright > dim and dim > 0.0 and absf(bright - glow.cable_glow) < 0.2,
				"the cables glow with the energy (%.2f at full, %.2f at 30%%)" % [bright, dim])
		var power_shot := OS.get_environment("POWER_SHOT")
		if power_shot != "":
			for e in [1.0, 0.3]:
				energy.current = energy.capacity * e
				await _frames(2)
				root.get_viewport().get_texture().get_image().save_png(power_shot.replace(".png", "_%d.png" % int(e * 100)))
	_finish()


func _finish() -> void:
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
