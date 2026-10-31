extends SceneTree
## Ammo Pack test (2026-10-31, user: "the canisters are removed 1 by 1 from the backpack as they are used"). The
## player carries the Ammo Pack. take_canister must give 6 canisters, one by one (top row first), then refuse;
## each used canister must leave the pack (no longer under the pack model), fall below its start height and be
## gone after canister_life. A destroyed pack gives no canister. Exits with code 1 on a failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_ammo_pack.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const PACK := "res://data/parts/backpacks/backpack_ammo.tres"

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
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = load(PACK) as BackPackPart
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var holder := mech.get_node_or_null(^"BackPackMount") as BackPackMount
	_check(holder != null and is_instance_valid(holder.model), "the pack model is on the mech")
	if holder == null:
		_finish()
		return
	_check(BackPackMount.canisters_left(mech) == 6, "6 canisters at the start (%d)" % BackPackMount.canisters_left(mech))
	var order := []
	var dropped: Array = []
	for i in 6:
		var next := holder._canisters[0] if not holder._canisters.is_empty() else null
		order.append(String(next.name) if next != null else "-")
		var start_y := next.global_position.y if next != null else 0.0
		var ok := BackPackMount.take_canister(mech)
		_check(ok and BackPackMount.canisters_left(mech) == 5 - i, "canister %d taken, %d left" % [i + 1,
				BackPackMount.canisters_left(mech)])
		if next != null:
			dropped.append(next)
			await _frames(60)
			_check(not holder.model.is_ancestor_of(next) and next.global_position.y < start_y - 1.0,
					"%s left the pack and fell (%.1f m to %.1f m)" % [next.name, start_y, next.global_position.y])
	print("order: ", order)
	_check(order == ["Canister1", "Canister2", "Canister3", "Canister4", "Canister5", "Canister6"],
			"top row first, left before right")
	_check(not BackPackMount.take_canister(mech), "no 7th canister")
	await _frames(int(holder.canister_life * 60.0) + 30)
	var gone := true
	for n in dropped.size():
		gone = gone and not is_instance_valid(dropped[n])
	_check(gone, "dropped canisters are gone after %.0f s" % holder.canister_life)
	# A destroyed pack gives none.
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	mech = switcher.mech
	mech.health.break_part(BackPackMount.HIT_KEY)
	await _frames(2)
	_check(not BackPackMount.take_canister(mech), "a destroyed pack gives no canister")
	_finish()


func _finish() -> void:
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
