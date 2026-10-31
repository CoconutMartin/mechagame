extends SceneTree
## Finite ammo test (user decision 2026-10-31: "finite ammo, the pack is the reserve"). The player mech has no back
## pack, so no canister (BackPackMount.take_canister is false). It checks: the reserve of the data (reserve_ammo =
## reserve_magazines x magazine), a Heavy Rifle that fires 1 + reserve_magazines magazines and then stops (EMPTY, the
## R key starts no reload), a partial reload (R fills the magazine only from the reserve), a missile pod that
## launches 1 + reserve_magazines magazines and then stops, a Pile Bunker (consume) that runs out, and unlimited weapons
## (reserve -1: beam rifle and fists keep their text). Fire rate and reload time are shortened on copies of the data so
## the test is quick. Exits with code 1 on any failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_ammo_reserve.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const RIFLE := "res://data/weapons/heavy_rifle.tres"
const POD_L := "res://data/weapons/missile_pod_l.tres"
const BUNKER := "res://data/weapons/pile_bunker.tres"
const BEAM := "res://data/weapons/beam_rifle.tres"

var _failures: int = 0
var _switcher: LoadoutSwitcher
var _player: Mech
var _weapons: WeaponController
var _shots: int = 0


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


func _finish() -> void:
	for action in ["use_right_arm", "fire_back_left", "reload", "aim"]:
		Input.action_release(action)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


## Builds the player mech again with no back pack.
func _build(right: String, back_left: String = "") -> void:
	for action in ["use_right_arm", "fire_back_left", "reload", "aim"]:
		Input.action_release(action)
	var loadout := _switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(right) as WeaponData
	loadout.weapon_left = null
	loadout.back_left = load(back_left) as WeaponData if back_left != "" else null
	loadout.back_right = null
	loadout.back_pack = null
	_switcher.current_loadout = loadout
	_switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	_player = _switcher.mech
	_weapons = _player.get_node("WeaponController") as WeaponController


func _count_shots(weapon: MechWeapon) -> void:
	_shots = 0
	weapon.fired.connect(func() -> void: _shots += 1)


## Quick copy of the weapon data: the same magazine and reserve, a fast fire rate and reload.
func _speed_up(weapon: MechWeapon, fire_rate: float, reload_time: float) -> void:
	var copy := weapon.data.duplicate() as WeaponData
	copy.fire_rate = fire_rate
	copy.reload_time = reload_time
	weapon.data = copy


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	for node in current_scene.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	_switcher = current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	await _rifle()
	await _pod()
	await _bunker()
	await _unlimited()
	_finish()


func _rifle() -> void:
	await _build(RIFLE)
	var gun := _weapons.right_weapon
	var data := gun.data
	_check(data.reserve_magazines == 5 and data.magazine == 12, "Heavy Rifle data: magazine %d, reserve magazines %d" % [data.magazine, data.reserve_magazines])
	_check(gun.reserve_ammo == data.reserve_magazines * data.magazine, "reserve_ammo is %d rounds" % gun.reserve_ammo)
	_check(not BackPackMount.take_canister(_player), "no back pack: no canister")
	_check(gun.get_status_text() == "12 / 12  [60]", "HUD text: '%s'" % gun.get_status_text())
	_speed_up(gun, 20.0, 0.2)
	_count_shots(gun)
	Input.action_press("aim")
	Input.action_press("use_right_arm")
	var frames := 0
	while frames < 1500 and not (_shots > 0 and gun.is_empty()):
		await _frames(1)
		frames += 1
	var total := data.magazine * (1 + data.reserve_magazines)
	await _frames(120)
	_check(_shots == total, "the rifle fired %d shots, then stopped (want %d)" % [_shots, total])
	_check(gun.ammo == 0 and gun.reserve_ammo == 0 and gun.reload_left <= 0.0, "ammo %d, reserve %d, no reload" % [gun.ammo, gun.reserve_ammo])
	_check(gun.is_empty() and gun.get_status_text() == "EMPTY", "HUD text: '%s'" % gun.get_status_text())
	Input.action_release("use_right_arm")
	Input.action_press("reload")
	await _frames(3)
	Input.action_release("reload")
	await _frames(10)
	_check(gun.reload_left <= 0.0 and gun.ammo == 0, "the R key starts no reload when empty")
	# Partial reload: a few rounds in the reserve fill only what is left.
	gun.reserve_ammo = 5
	gun.ammo = 4
	Input.action_press("reload")
	await _frames(3)
	Input.action_release("reload")
	_check(gun.reload_left > 0.0, "the R key starts a reload when the reserve has rounds")
	await _frames(40)
	_check(gun.ammo == 9 and gun.reserve_ammo == 0, "partial reload: ammo %d (want 9), reserve %d (want 0)" % [gun.ammo, gun.reserve_ammo])
	_check(gun.get_status_text() == "9 / 12  [0]", "HUD text: '%s'" % gun.get_status_text())
	# The reserve stays with the weapon when a new hand takes it (rebind).
	gun.reserve_ammo = 17
	gun.rebind(_weapons)
	_check(gun.reserve_ammo == 17, "rebind keeps the reserve (%d)" % gun.reserve_ammo)


func _pod() -> void:
	await _build(RIFLE, POD_L)
	var pod := _weapons.back_left as MissilePodWeapon
	var data := pod.data
	_check(pod.reserve_ammo == data.reserve_magazines * data.magazine, "Missile Pod: %d missiles in the reserve" % pod.reserve_ammo)
	_speed_up(pod, 20.0, 0.4)
	_count_shots(pod)
	var missiles: Array[int] = [0]
	node_added.connect(func(node: Node) -> void:
		if node is Missile:
			missiles[0] += 1)
	var frames := 0
	while frames < 3000:
		if pod.ammo > 0 and pod._queue.is_empty():
			Input.action_press("fire_back_left")
			await _frames(8)
			Input.action_release("fire_back_left")
			await _frames(8)
			frames += 16
		else:
			await _frames(1)
			frames += 1
		if pod.is_empty() and pod._queue.is_empty() and frames > 60 and missiles[0] > 0:
			break
	await _frames(60)
	var total := data.magazine * (1 + data.reserve_magazines)
	_check(missiles[0] == total, "the pod launched %d missiles, then stopped (want %d)" % [missiles[0], total])
	_check(pod.ammo == 0 and pod.reserve_ammo == 0, "pod ammo %d, reserve %d" % [pod.ammo, pod.reserve_ammo])
	_check(pod.get_status_text().begins_with("EMPTY"), "pod HUD text: '%s'" % pod.get_status_text())


func _bunker() -> void:
	await _build(BUNKER)
	var bunker := _weapons.right_weapon
	var data := bunker.data
	_check(bunker.reserve_ammo == data.reserve_magazines * data.magazine, "Pile Bunker: %d stakes in the reserve" % bunker.reserve_ammo)
	_speed_up(bunker, 20.0, 0.2)
	for i in data.magazine * (1 + data.reserve_magazines):
		_check(bunker.can_use() or i > 0, "bunker ready at the start")
		bunker.consume()
		await _frames(20)
	_check(bunker.ammo == 0 and bunker.reserve_ammo == 0 and bunker.reload_left <= 0.0, "bunker ammo %d, reserve %d after %d shots" % [bunker.ammo, bunker.reserve_ammo, data.magazine * (1 + data.reserve_magazines)])
	_check(not bunker.can_use(), "the empty bunker cannot be used")
	_check(bunker.get_status_text().begins_with("EMPTY"), "bunker HUD text: '%s'" % bunker.get_status_text())


func _unlimited() -> void:
	await _build(BEAM)
	var beam := _weapons.right_weapon
	_check(beam.reserve_ammo < 0 and not beam.is_empty(), "Beam Rifle: unlimited, never empty")
	_check(not beam.get_status_text().contains("EMPTY"), "Beam Rifle HUD text: '%s'" % beam.get_status_text())
	var fist := _weapons.right_fist
	_check(fist == null or not fist.is_empty(), "the fist is never empty")
