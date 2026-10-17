extends SceneTree
## Weapon drop, pick-up and fists test in the game (user rules 2026-10-17, phase 3). The player mech (Auto Cannon
## in the right hand, an empty left hand) drops and takes weapons with the real input path (Input.action_press
## of use_left_arm / use_right_arm / weapon_hand into MechInput, WeaponHandControl, WeaponController,
## WeaponPickup). It checks: the hand rules table, the fists in empty hands (and their arm look), the Tab drop
## (no shot, no punch), the HUD line, a pick-up (ammo and weapon HP kept, time, lock, camera), the hand choice
## (pressed side), a two-hand rifle (both hands, refused with a dead arm), a knock-down during the reach and
## the lift, the owner rule of a knock-down drop, a face-down knock-down with the automatic pick-up, the
## weapon of a dead mech (free, a new owner), the despawn and the limit of 8 weapons, and an AI mech that
## loses its gun. Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_weapon_hands.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const AUTO_CANNON := "res://data/weapons/auto_cannon.tres"
const HAMMER := "res://data/weapons/hammer.tres"
const SHIELD := "res://data/weapons/small_shield.tres"
const BEAM_RIFLE := "res://data/weapons/beam_rifle.tres"
const SMG_SCENE := "res://scenes/weapons/smg.tscn"
const SMG_DATA := "res://data/weapons/smg.tres"

var _failures: int = 0
var _switcher: LoadoutSwitcher
var _player: Mech
var _weapons: WeaponController
var _health: MechHealth
var _input: MechInput
var _stagger: SkeletalStaggerAnimation
var _melee: SkeletalMeleeAnimation
var _control: WeaponHandControl
var _camera_rig: MechCameraRig
var _level: Node


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
	for action in ["use_left_arm", "use_right_arm", "weapon_hand"]:
		Input.action_release(action)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_rules_table()
	change_scene_to_file(MAP)
	await _frames(30)
	_level = current_scene
	for node in _level.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	_switcher = _level.get_node("LoadoutSwitcher") as LoadoutSwitcher
	await _build(AUTO_CANNON)
	await _fists_and_tab_drop()
	await _pick_up_right()
	await _pick_up_left()
	await _knock_down_in_reach()
	await _knock_down_owner_rule()
	await _build(BEAM_RIFLE)
	await _two_hand_rifle()
	await _build(AUTO_CANNON)
	await _parts_break()
	await _build(HAMMER)
	await _hammer_stays()
	await _build(AUTO_CANNON)
	await _death_during_pickup(WeaponPickup.Phase.REACH)
	await _death_during_pickup(WeaponPickup.Phase.LIFT)
	await _death_drop()
	await _limit_and_despawn()
	await _ai_loses_gun()
	_finish()


# --- helpers ---

## Builds the player mech again with this right hand weapon and an empty left hand.
func _build(right_path: String, left_path: String = "") -> void:
	var loadout := _switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(right_path) as WeaponData
	loadout.weapon_left = load(left_path) as WeaponData if left_path != "" else null
	_switcher.current_loadout = loadout
	_switcher.rebuild(loadout, _switcher.mech.global_transform)
	await _frames(60)
	_grab_player()


func _grab_player() -> void:
	_player = _switcher.mech
	_weapons = _player.get_node("WeaponController") as WeaponController
	_health = _player.health
	_input = _player.input
	_stagger = _player.find_child("StaggerAnimation", true, false) as SkeletalStaggerAnimation
	_melee = _player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	_control = _player.get_node_or_null("WeaponHandControl") as WeaponHandControl
	_camera_rig = _input.camera_rig


func _clear_ground() -> void:
	for node in get_nodes_in_group(GroundWeapons.GROUP):
		node.queue_free()


func _press(action: String) -> void:
	Input.action_press(action)


func _release(action: String) -> void:
	Input.action_release(action)


## Hold the button, then press Tab: that hand drops its weapon. Keeps the button held for `hold` frames
## after Tab goes up, then lets go. Returns true when a melee attack played meanwhile.
func _tab_drop(button: String, hold: int = 3) -> bool:
	var punched := false
	_press(button)
	await _frames(2)
	_press("weapon_hand")
	for i in 3:
		await _frames(1)
		punched = punched or _melee.is_playing
	_release("weapon_hand")
	for i in hold:
		await _frames(1)
		punched = punched or _melee.is_playing
	_release(button)
	await _frames(2)
	return punched


## Hold Tab, then press the button: the weapon within reach is taken. Returns the frames the pick-up needs.
func _tab_pick(button: String) -> int:
	_press("weapon_hand")
	await _frames(3)
	_press(button)
	await _frames(2)
	_release(button)
	_release("weapon_hand")
	var frames := 0
	while _weapons.pickup.phase != WeaponPickup.Phase.IDLE and frames < 400:
		await _frames(1)
		frames += 1
	await _frames(3)
	return frames


func _bullets() -> int:
	return _level.find_children("*", "Bullet", true, false).size()


func _drop_of(weapon: MechWeapon) -> WeaponDrop:
	for node in get_nodes_in_group(GroundWeapons.GROUP):
		if (node as WeaponDrop).weapon == weapon:
			return node as WeaponDrop
	return null


func _is_fist(weapon: MechWeapon) -> bool:
	return weapon != null and weapon is MeleeWeapon and weapon.data.kind == WeaponData.Kind.FIST


## Waits until the mech stands again (no stagger, no fall, no pick-up).
func _calm(limit: int = 900) -> void:
	var guard := 0
	while (_stagger.is_staggered() or _stagger.is_down or _player.is_fallen or _weapons.pickup.phase != WeaponPickup.Phase.IDLE) \
			and guard < limit:
		await _frames(1)
		guard += 1
	await _frames(20)


func _knock_down(from_behind: bool) -> void:
	var hitbox := (_health.hitboxes["Torso C"] as Array)[0] as PartHitbox
	var from := _player.global_position + _player.global_basis.z * (100.0 if from_behind else -100.0)
	# The direction of the last hit decides the fall (face down from behind): MechHealth keeps it.
	_health.last_hit_from = from
	MechStability.hit_body(hitbox, 45.0, 0, 0.0, from)


# --- the tests ---

func _rules_table() -> void:
	var one := WeaponData.new()
	one.display_name = "Auto Cannon"
	var two := WeaponData.new()
	two.display_name = "Beam Rifle"
	two.two_handed = true
	var H := WeaponHandRules.Hands
	# [data, pressed right, right free, left free, left allowed, expected]
	var table := [
		[one, true, true, true, true, H.RIGHT],
		[one, false, true, true, true, H.LEFT],
		[one, true, false, true, true, H.LEFT],
		[one, false, true, false, true, H.RIGHT],
		[one, false, true, true, false, H.RIGHT],
		[one, true, false, true, false, H.NONE],
		[one, true, false, false, true, H.NONE],
		[two, true, true, true, true, H.BOTH],
		[two, false, true, true, true, H.BOTH],
		[two, true, true, false, true, H.NONE],
		[two, true, false, true, true, H.NONE],
	]
	var wrong := 0
	for row: Array in table:
		var got := WeaponHandRules.choose(row[0], row[1], row[2], row[3], row[4])
		if got != row[5]:
			wrong += 1
			print("     rules row %s -> %d (wanted %d)" % [row.slice(1, 5), got, row[5]])
	_check(wrong == 0, "hand rules table: %d rows, %d wrong" % [table.size(), wrong])
	_check(WeaponHandRules.prompt(one, H.RIGHT) == "Tab + LMB/RMB: pick up Auto Cannon", "prompt: pick up")
	_check(WeaponHandRules.prompt(two, H.NONE) == "Beam Rifle: needs both hands free", "prompt: both hands")
	_check(WeaponHandRules.prompt(one, H.NONE) == "Auto Cannon: no free hand", "prompt: no free hand")


func _fists_and_tab_drop() -> void:
	_check(_control != null, "the player mech has a WeaponHandControl")
	_check(_weapons.right_weapon is ForearmGunWeapon, "right hand holds the Auto Cannon")
	_check(_is_fist(_weapons.left_weapon), "empty left hand holds a fist")
	_check(not _health.hp.has("Weapon L") and not _health.hitboxes.has("Weapon L"), "the left fist has no Weapon L part")
	_check(_health.hp.has("Weapon R"), "the Auto Cannon has its Weapon R part")
	_check(_weapons.arm_ik_left.target == _weapons.free_left_hand, "left fist at rest: arm at the relaxed hang")
	# LMB punches with the left fist; the arm is free for the clip meanwhile.
	await _frames(30)
	_press("use_left_arm")
	var played := false
	var free_arm := false
	for i in 20:
		await _frames(1)
		if _melee.is_playing:
			played = true
			free_arm = free_arm or _weapons.arm_ik_left.target == null
	_release("use_left_arm")
	_check(played, "LMB: the empty left hand punches")
	_check(free_arm, "during the punch the left arm IK lets go (the clip drives the arm)")
	await _frames(120)
	_check(_weapons.arm_ik_left.target == _weapons.free_left_hand, "after the punch the arm goes back to the relaxed hang")
	# Tab then a button, Tab up first: no punch.
	_press("weapon_hand")
	await _frames(3)
	_press("use_left_arm")
	await _frames(2)
	_release("weapon_hand")
	var punched := false
	for i in 20:
		await _frames(1)
		punched = punched or _melee.is_playing
	_release("use_left_arm")
	_check(not punched, "Tab, LMB, then Tab up first: no punch")
	await _frames(60)
	# Tab drop of the right hand weapon.
	var gun := _weapons.right_weapon
	var bullets_before := _bullets()
	var drop_punch := await _tab_drop("use_right_arm", 20)
	_check(_bullets() == bullets_before, "RMB held then Tab: no shot")
	_check(not drop_punch, "RMB held, Tab, Tab up first: no punch")
	_check(_is_fist(_weapons.right_weapon), "after the Tab drop the right hand holds a fist")
	_check(not _health.hp.has("Weapon R") and not _health.hitboxes.has("Weapon R"), "Weapon R part and hitboxes are gone")
	var drop := _drop_of(gun)
	_check(drop != null and drop.is_in_group(GroundWeapons.GROUP), "the weapon is a drop in the ground group")
	_check(gun.process_mode == Node.PROCESS_MODE_DISABLED, "the weapon on the ground is disabled")
	_check(drop != null and drop.owner_weapons == null, "a Tab drop has no owner")
	_check(_weapons.arm_ik_right.target == _weapons.free_right_hand, "right fist at rest: arm at the relaxed hang")
	await _frames(80)
	_check(drop != null and drop.is_landed, "the dropped weapon has landed")
	var flat := drop.get_grip_position(&"GripRight") - _player.global_position
	flat.y = 0.0
	_check(flat.length() < 3.0, "it lies inside the 3 m pick-up radius (%.2f m)" % flat.length())
	_check(_control.get_prompt() == "Tab + LMB/RMB: pick up Auto Cannon", "HUD line: '%s'" % _control.get_prompt())


func _pick_up_right() -> void:
	var gun := _find_ground_weapon()
	gun.ammo = 3
	gun.part_hp = 150.0
	var heading := _player.rotation.y
	var camera_before := _camera_rig.rotation.y
	_press("weapon_hand")
	await _frames(3)
	_press("use_right_arm")
	await _frames(2)
	_release("use_right_arm")
	_release("weapon_hand")
	await _frames(3)
	_check(_weapons.pickup.is_manual() and _player.is_fallen, "pick-up runs: manual, the mech is locked (is_fallen)")
	var shots_before := _bullets()
	# The mouse buttons do nothing meanwhile.
	_press("use_left_arm")
	_press("use_right_arm")
	var frames := 0
	var camera_moved := 0.0
	var punched := false
	var turned := 0.0
	while _weapons.pickup.phase != WeaponPickup.Phase.IDLE and frames < 400:
		await _frames(1)
		frames += 1
		punched = punched or _melee.is_playing
		turned = maxf(turned, absf(wrapf(_player.rotation.y - heading, -PI, PI)))
		camera_moved = maxf(camera_moved, absf(wrapf(_camera_rig.rotation.y - camera_before, -PI, PI)))
	var shots_after := _bullets()
	_release("use_left_arm")
	_release("use_right_arm")
	await _frames(3)
	_check(frames < 90, "the pick-up needs %d frames (%.2f s, limit 1.5 s)" % [frames, frames / 60.0])
	_check(shots_after == shots_before and not punched, "no shot and no punch during the pick-up")
	_check(_weapons.right_weapon == gun and _weapons.holds(gun), "the Auto Cannon is in the right hand")
	_check(gun.ammo == 3, "ammo kept: %d" % gun.ammo)
	_check(is_equal_approx(_health.hp.get("Weapon R", -1.0), 150.0), "weapon HP kept: %s" % _health.hp.get("Weapon R", -1.0))
	var boxes: Array = _health.hitboxes.get("Weapon R", [])
	_check(not boxes.is_empty() and is_instance_valid(boxes[0]), "Weapon R hitboxes are back")
	_check(gun.process_mode != Node.PROCESS_MODE_DISABLED, "the weapon works again")
	_check(not _player.is_fallen, "the mech is free after the pick-up")
	_check(turned > 0.3, "the body turned toward the weapon (up to %.0f deg)" % rad_to_deg(turned))
	_check(absf(wrapf(_player.rotation.y - _input.aim_yaw, -PI, PI)) < 0.05, "and it faces the aim again at the end")
	_check(camera_moved < 0.05, "the camera stayed where the player aims (moved %.3f rad)" % camera_moved)
	_check(_weapons.right_fist != null and _weapons.right_weapon != _weapons.right_fist, "the right fist is off")
	_check(_drop_of(gun) == null, "the drop is gone")
	# It fires again.
	await _frames(90)
	_press("use_right_arm")
	await _frames(90)
	_release("use_right_arm")
	_check(gun.ammo < 3 or gun.reload_left > 0.0, "the Auto Cannon fires after the pick-up (ammo %d)" % gun.ammo)


func _find_ground_weapon() -> MechWeapon:
	for node in get_nodes_in_group(GroundWeapons.GROUP):
		return (node as WeaponDrop).weapon
	return null


func _pick_up_left() -> void:
	await _frames(240)
	var gun := _weapons.right_weapon
	await _tab_drop("use_right_arm")
	await _frames(80)
	# LMB takes it into the left hand (the pressed side).
	await _tab_pick("use_left_arm")
	_check(_weapons.left_weapon == gun, "LMB: the weapon went into the LEFT hand")
	_check(gun.controller == _weapons.left_view and _weapons.left_view != null, "its controller is the left view")
	_check(_is_fist(_weapons.right_weapon), "the right hand keeps its fist")
	_check(_health.hp.has("Weapon L") and not _health.hp.has("Weapon R"), "the part is Weapon L now")
	_check(_weapons.arm_ik_left.target == gun.get_node("GripLeft"), "the left arm reaches for the weapon grip")
	# Drop with LMB held then Tab: the left hand lets go.
	await _frames(60)
	await _tab_drop("use_left_arm")
	_check(_is_fist(_weapons.left_weapon) and _drop_of(gun) != null, "LMB + Tab drops the left weapon, the left hand has a fist")
	await _frames(80)
	await _tab_pick("use_right_arm")
	_check(_weapons.right_weapon == gun and gun.controller == _weapons, "RMB: back into the right hand, controller is the main one")
	await _frames(240)


func _knock_down_in_reach() -> void:
	var gun := _weapons.right_weapon
	await _tab_drop("use_right_arm")
	await _frames(80)
	# Knock-down during the reach.
	_press("weapon_hand")
	await _frames(3)
	_press("use_right_arm")
	await _frames(2)
	_release("use_right_arm")
	_release("weapon_hand")
	await _frames(12)
	_check(_weapons.pickup.phase == WeaponPickup.Phase.REACH, "knock-down test: the reach runs")
	_knock_down(false)
	await _frames(10)
	var drop := _drop_of(gun)
	_check(drop != null and not is_instance_valid(drop.reserved_by), "knock-down in the reach: the weapon stays on the ground, free")
	await _calm()
	_check(_is_fist(_weapons.right_weapon) and not _weapons.is_picking(), "after the get-up the right hand has its fist (no stuck reach)")
	_check(not _player.is_fallen, "and the mech is free")
	_stand_near(drop)
	await _frames(20)
	# Knock-down during the lift: the weapon is in the hand.
	_press("weapon_hand")
	await _frames(3)
	_press("use_right_arm")
	await _frames(2)
	_release("use_right_arm")
	_release("weapon_hand")
	var guard := 0
	while _weapons.pickup.phase != WeaponPickup.Phase.LIFT and guard < 200:
		await _frames(1)
		guard += 1
	await _frames(5)
	_check(_weapons.pickup.phase == WeaponPickup.Phase.LIFT, "knock-down test: the lift runs")
	_knock_down(false)
	await _frames(10)
	_check(_weapons.right_weapon == gun and gun.process_mode != Node.PROCESS_MODE_DISABLED, "knock-down in the lift: the weapon is in the hand and works")
	_check(_health.hp.has("Weapon R"), "and its part is back")
	await _calm()
	_check(not _player.is_fallen and _weapons.right_weapon == gun, "after the get-up the mech holds the weapon")


## Puts the mech 2 m behind a weapon on the ground (a knock-down moves the mech away from it).
func _stand_near(drop: WeaponDrop) -> void:
	var spot := drop.get_grip_position(&"GripRight") + _player.global_basis * Vector3(0.0, 0.0, 2.0)
	spot.y = _player.global_position.y
	_player.global_position = spot
	_player.velocity = Vector3.ZERO


func _knock_down_owner_rule() -> void:
	# Face down: the hands let go, only this mech takes the weapon back; the automatic pick-up follows.
	var gun := _weapons.right_weapon
	gun.ammo = 5
	_knock_down(true)
	await _frames(30)
	var drop := _drop_of(gun)
	_check(drop != null and drop.owner_weapons == _weapons, "face-down knock-down: the drop belongs to the mech")
	_check(drop != null and not _health.hp.has("Weapon R"), "and the weapon takes no damage on the ground (no Weapon R part)")
	var stand_in := WeaponController.new()
	_check(drop != null and not drop.is_pickable_by(stand_in), "another mech cannot take it")
	stand_in.free()
	await _frames(150)
	_check(drop != null and drop.is_landed and drop.is_pickable_by(_weapons), "the owner can take it")
	await _calm(1500)
	_check(_weapons.right_weapon == gun and not _player.is_fallen, "automatic pick-up after the get-up: the weapon is back")
	_check(gun.ammo == 5 and _health.hp.has("Weapon R"), "ammo kept (%d) and the part is back" % gun.ammo)
	_check(_weapons.right_fist == null or _weapons.right_weapon != _weapons.right_fist, "no fist in the hand that holds the weapon")


func _two_hand_rifle() -> void:
	var rifle := _weapons.right_weapon
	_check(rifle is BeamRifleWeapon and _weapons.two_handed_left_grip(), "Beam Rifle test: the rifle is in both hands")
	_check(_weapons.left_weapon == null, "no left fist beside a two-hand rifle")
	# Either button drops it: LMB.
	await _tab_drop("use_left_arm")
	_check(_is_fist(_weapons.right_weapon) and _is_fist(_weapons.left_weapon), "LMB + Tab drops the rifle: both hands have fists")
	_check(_drop_of(rifle) != null, "the rifle lies on the ground")
	await _frames(100)
	_check(_control.get_prompt() == "Tab + LMB/RMB: pick up Beam Rifle", "HUD line: '%s'" % _control.get_prompt())
	var frames := await _tab_pick("use_right_arm")
	_check(_weapons.right_weapon == rifle and _weapons.left_weapon == null, "the rifle is back in both hands (%d frames)" % frames)
	var left_target := _weapons.arm_ik_left.target
	_check(left_target != null and (left_target == _weapons.weapon_pose.left_grip_target or left_target.get_parent() == rifle),
			"the left arm holds the forestock")
	_check(_health.hp.has("Weapon R"), "the rifle part is back")
	await _frames(120)
	# Face down knock-down with the rifle (both arms alive): it drops and comes back into both hands.
	_knock_down(true)
	await _frames(30)
	_check(_drop_of(rifle) != null and _drop_of(rifle).owner_weapons == _weapons and not _health.hp.has("Weapon R"),
			"knock-down: the rifle is a drop of the mech, with no part")
	await _calm(1500)
	_check(_weapons.right_weapon == rifle and not _weapons.one_hand_hold and not _player.is_fallen, "the rifle is back in both hands after the get-up")
	_check(_weapons.weapon_pose.left_grip_target != null and _health.hp.has("Weapon R"), "with its left grip and its part")
	await _frames(240)
	# The left arm dies while the rifle lies on the ground: the rifle comes back, held in one hand.
	_knock_down(true)
	await _frames(30)
	_health.break_part("Arm L")
	await _calm(1500)
	_check(not _weapons.is_arm_alive(false) and _weapons.left_fist == null, "left arm destroyed: no left fist")
	_check(_weapons.right_weapon == rifle and _weapons.one_hand_hold and not _player.is_fallen, "the rifle is back, held in one hand")
	_check(_health.hp.has("Weapon R"), "with its part")
	# Tab drop of the one-hand rifle, then it cannot be taken with one free hand.
	await _tab_drop("use_right_arm")
	await _frames(100)
	_check(_is_fist(_weapons.right_weapon) and _weapons.left_weapon == null, "the rifle dropped from one hand: right fist, no left fist")
	_check(_control.get_prompt() == "Beam Rifle: needs both hands free", "HUD line with a dead arm: '%s'" % _control.get_prompt())
	var frames2 := await _tab_pick("use_right_arm")
	_check(frames2 < 3 and _weapons.right_weapon != rifle and not _player.is_fallen, "the rifle is refused with a dead left arm")


## A broken shield, a broken right weapon and a broken arm: the hand gets a fist, or none when the arm is gone.
func _parts_break() -> void:
	await _build(AUTO_CANNON, SHIELD)
	_check(_weapons.left_weapon == null and _weapons.left_fist != null and not _weapons.is_hand_free(false),
			"left shield: no left fist while the shield holds")
	_health.break_part("Shield")
	await _frames(10)
	_check(_is_fist(_weapons.left_weapon) and _weapons.is_hand_free(false), "the shield broke: the left hand is a fist")
	_press("use_left_arm")
	var punched := false
	for i in 20:
		await _frames(1)
		punched = punched or _melee.is_playing
	_release("use_left_arm")
	_check(punched, "and LMB punches with it")
	_health.break_part("Weapon R")
	await _frames(10)
	_check(_is_fist(_weapons.right_weapon), "Weapon R broke: the right hand is a fist")
	_health.break_part("Arm R")
	await _frames(10)
	_check(_weapons.right_weapon == null and _weapons.right_fist == null, "Arm R broke: no right fist, no right weapon")
	_health.break_part("Arm L")
	await _frames(10)
	_check(_weapons.left_weapon == null and _weapons.left_fist == null, "Arm L broke: no left fist")
	await _frames(30)


## The War Hammer stays as it was: both arms are the hammer's, no fists, Tab drops nothing.
func _hammer_stays() -> void:
	_check(_weapons.right_data.kind == WeaponData.Kind.HAMMER and _weapons.left_weapon == null, "hammer: no left fist")
	var before := _weapons.right_weapon
	_clear_ground()
	await _frames(2)
	await _tab_drop("use_right_arm")
	_check(_weapons.right_weapon == before and get_nodes_in_group(GroundWeapons.GROUP).is_empty(), "Tab does not drop the War Hammer")
	await _frames(60)
	_press("use_right_arm")
	var swung := false
	for i in 20:
		await _frames(1)
		swung = swung or _melee.is_playing
	_release("use_right_arm")
	_check(swung, "RMB swings the hammer")


## The mech dies while it reaches for a weapon (REACH) or lifts it (LIFT): the weapon ends up free on the ground.
func _death_during_pickup(phase: WeaponPickup.Phase) -> void:
	var gun := _weapons.right_weapon
	_clear_ground()
	await _frames(2)
	await _tab_drop("use_right_arm")
	await _frames(80)
	_press("weapon_hand")
	await _frames(3)
	_press("use_right_arm")
	await _frames(2)
	_release("use_right_arm")
	_release("weapon_hand")
	var guard := 0
	while _weapons.pickup.phase != phase and guard < 200:
		await _frames(1)
		guard += 1
	await _frames(3)
	var name := "reach" if phase == WeaponPickup.Phase.REACH else "lift"
	_check(_weapons.pickup.phase == phase, "death test (%s): the pick-up is in that phase" % name)
	var old_player := _player
	_health.damage("Head", 1.0e9)
	await _frames(60)
	var drop := _drop_of(gun)
	_check(drop != null and drop.owner_weapons == null and not is_instance_valid(drop.reserved_by),
			"death in the %s: the weapon is a free drop, nobody has it reserved" % name)
	guard = 0
	while _switcher.mech == old_player and guard < 1200:
		await _frames(1)
		guard += 1
	await _frames(40)
	_grab_player()
	_check(is_instance_valid(drop) and is_instance_valid(gun), "and it survives the wreck")


func _death_drop() -> void:
	var gun := _weapons.right_weapon
	gun.ammo = 4
	_clear_ground()
	await _frames(2)
	var old_player := _player
	_health.damage("Head", 1.0e9)
	await _frames(60)
	var drop := _drop_of(gun)
	_check(drop != null and drop.owner_weapons == null, "a dead mech's weapon is a free drop")
	# The respawner frees the wreck; the drop stays.
	var guard := 0
	while _switcher.mech == old_player and guard < 1200:
		await _frames(1)
		guard += 1
	await _frames(40)
	_check(not is_instance_valid(old_player) or old_player.is_queued_for_deletion(), "the wreck is gone")
	_check(is_instance_valid(drop) and is_instance_valid(gun), "the dead mech's weapon survives the wreck")
	_grab_player()
	await _frames(40)
	# A new mech takes it: rebinds the weapon.
	_stand_near(drop)
	await _frames(40)
	# The new mech has its own Auto Cannon in the right hand: RMB cannot use that hand, so the free left hand takes it.
	await _tab_pick("use_right_arm")
	_check(_weapons.left_weapon == gun and gun.controller == _weapons.left_view, "a new mech takes it into its free left hand and the weapon talks to it")
	_check(gun.ammo == 4, "ammo kept across mechs (%d)" % gun.ammo)
	_check(_health.hp.has("Weapon L") and _health.hp["Weapon L"] == gun.data.hp, "the weapon has full HP on the new mech (never damaged)")


func _limit_and_despawn() -> void:
	_clear_ground()
	await _frames(2)
	var far := _player.global_position + Vector3(200.0, 0.0, 0.0)
	var drops: Array[WeaponDrop] = []
	for i in 9:
		drops.append(_make_drop(far + Vector3(0.0, 0.0, 4.0 * i)))
		await _frames(1)
	await _frames(5)
	_check(get_nodes_in_group(GroundWeapons.GROUP).size() == 8, "9 weapons dropped: 8 stay (%d)" % get_nodes_in_group(GroundWeapons.GROUP).size())
	_check(not is_instance_valid(drops[0]) or drops[0].is_queued_for_deletion(), "the oldest free weapon went")
	_check(is_instance_valid(drops[8]), "the newest stays")
	# Despawn: free, no mech within 30 m.
	for drop in drops:
		if is_instance_valid(drop):
			drop.despawn_time = 0.4
			drop.fade_time = 0.2
	var near := _make_drop(_player.global_position + Vector3(0.0, 0.0, -10.0))
	near.despawn_time = 0.4
	near.fade_time = 0.2
	var owned := _make_drop(_player.global_position + Vector3(10.0, 0.0, 0.0))
	owned.despawn_time = 0.4
	owned.fade_time = 0.2
	owned.owner_weapons = _weapons
	await _frames(200)
	var far_left := 0
	for drop in drops:
		if is_instance_valid(drop) and not drop.is_queued_for_deletion():
			far_left += 1
	_check(far_left == 0, "free weapons far from every mech despawn (%d left)" % far_left)
	_check(is_instance_valid(near), "a free weapon within 30 m of a mech stays")
	_check(is_instance_valid(owned), "a weapon with an owner stays")
	_clear_ground()
	await _frames(2)


func _make_drop(spot: Vector3) -> WeaponDrop:
	var weapon := (load(SMG_SCENE) as PackedScene).instantiate() as MechWeapon
	_level.add_child(weapon)
	weapon.global_position = spot + Vector3.UP * 3.0
	weapon.setup(load(SMG_DATA) as WeaponData, _weapons)
	return WeaponDrop.create(weapon, _level, spot, Vector3.FORWARD, false, 8)


func _ai_loses_gun() -> void:
	var spawner: MechSpawner = null
	for node in get_nodes_in_group(&"mech_spawner"):
		if (node as MechSpawner).pilot == MechSpawner.Pilot.AI:
			spawner = node as MechSpawner
	_check(spawner != null, "the map has an AI spawner")
	if spawner == null:
		return
	spawner.set_active(true)
	await _frames(60)
	var ai := spawner.mech
	var ai_weapons := ai.get_node("WeaponController") as WeaponController
	ai.global_position = _player.global_position + _player.global_basis * Vector3(0.0, 0.0, -25.0)
	await _frames(120)
	_check(ai_weapons.right_weapon != null, "the AI mech holds its weapon")
	ai.health.break_part("Weapon R")
	await _frames(10)
	_check(_is_fist(ai_weapons.right_weapon), "the AI mech lost its weapon: a fist in the hand")
	await _frames(300)
	_check(is_instance_valid(ai) and not ai.is_wrecked, "the AI mech keeps working 300 frames after losing its gun")
	ai.health.damage("Head", 1.0e9)
	await _frames(120)
	_check(true, "the AI mech died without errors")
