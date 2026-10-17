class_name WeaponHandControl
extends Node
## Turns the weapon hand key (Tab) into drops and pick-ups for the player's mech (user rules 2026-10-17):
##   Hold LMB or RMB, then press Tab: that hand drops its weapon (a two-hand rifle: either button drops it).
##   Hold Tab, then press LMB or RMB: the weapon within pickup_radius is taken (WeaponPickup.begin_manual).
## MechInput reads the keys (drop_*_pressed, pick_*_pressed). WeaponController makes this node.
## An AI mech has the node too; its MechInput is off, so nothing happens.

## Flat distance (m) from the mech to the right grip of a weapon on the ground that can be picked up.
@export var pickup_radius: float = 3.0
@export var mech: Mech
@export var weapons: WeaponController
@export var input: MechInput

var _prompt: String = ""
var _melee: SkeletalMeleeAnimation


func _ready() -> void:
	# After MechInput (-10), before WeaponController (1): a drop is seen by the weapons in the same frame.
	process_physics_priority = 0


## The HUD line about the weapon within reach ("" = none).
func get_prompt() -> String:
	return _prompt


func _physics_process(_delta: float) -> void:
	_prompt = ""
	if input == null or weapons == null or mech == null or not input.can_process():
		return
	_handle_drops()
	_handle_picks()
	_update_prompt()


func _handle_drops() -> void:
	if input.drop_left_pressed:
		if weapons.can_tab_drop(false):
			weapons.drop_hand(false)
		elif weapons.two_handed_left_grip() and weapons.can_tab_drop(true):
			weapons.drop_hand(true)
	if input.drop_right_pressed and weapons.can_tab_drop(true):
		weapons.drop_hand(true)


func _handle_picks() -> void:
	if not (input.pick_left_pressed or input.pick_right_pressed):
		return
	var drop := GroundWeapons.nearest(get_tree(), mech.global_position, pickup_radius, weapons)
	if drop == null or not _may_pick():
		return
	var choice := _choose(drop.weapon.data, input.pick_right_pressed)
	match choice:
		WeaponHandRules.Hands.RIGHT:
			weapons.pickup.begin_manual(drop, true, false)
		WeaponHandRules.Hands.LEFT:
			weapons.pickup.begin_manual(drop, false, false)
		WeaponHandRules.Hands.BOTH:
			weapons.pickup.begin_manual(drop, true, true)


func _choose(data: WeaponData, pressed_right: bool) -> WeaponHandRules.Hands:
	return WeaponHandRules.choose(data, pressed_right, weapons.is_hand_free(true), weapons.is_hand_free(false),
			WeaponController.can_hold_left(data, weapons.right_data))


## True when the mech can start a pick-up: on the ground and free (no dodge, kneel, jump charge, melee attack,
## stun, knock-down or pick-up).
func _may_pick() -> bool:
	if weapons.pickup == null or weapons.pickup.phase != WeaponPickup.Phase.IDLE:
		return false
	if mech.is_fallen or mech.is_wrecked or not mech.is_on_floor():
		return false
	if mech.dodge != null and mech.dodge.is_busy():
		return false
	if mech.kneel != null and mech.kneel.is_kneeling:
		return false
	if mech.jump_charge != null and mech.jump_charge.is_charging:
		return false
	if _melee == null or not is_instance_valid(_melee):
		_melee = mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	return _melee == null or not _melee.is_playing


func _update_prompt() -> void:
	if mech.is_fallen or mech.is_wrecked:
		return
	var drop := GroundWeapons.nearest(get_tree(), mech.global_position, pickup_radius, weapons)
	if drop == null:
		return
	var data := drop.weapon.data
	_prompt = WeaponHandRules.prompt(data, _choose(data, true))
