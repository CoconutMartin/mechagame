class_name WeaponHandRules
extends RefCounted
## Which hand takes a weapon from the ground, and what the HUD says about it (user rules 2026-10-17). Pure
## functions, no nodes, so a test can check the whole table.
##   The pressed side gets a one-hand weapon if that hand is free; otherwise the other free hand takes it.
##   The left hand takes only what WeaponController.can_hold_left allows (left_allowed).
##   A two-hand weapon needs both hands free.

enum Hands { NONE, RIGHT, LEFT, BOTH }


## pressed_right: the mouse button of the pick-up (RMB = right). right_free, left_free: the hand holds only
## its fist and its arm is alive (WeaponController.is_hand_free). left_allowed: the left hand can hold
## this weapon (WeaponController.can_hold_left).
static func choose(data: WeaponData, pressed_right: bool, right_free: bool, left_free: bool, left_allowed: bool) -> Hands:
	if data == null:
		return Hands.NONE
	if data.two_handed:
		return Hands.BOTH if right_free and left_free else Hands.NONE
	var left_ok := left_free and left_allowed
	if pressed_right:
		if right_free:
			return Hands.RIGHT
		return Hands.LEFT if left_ok else Hands.NONE
	if left_ok:
		return Hands.LEFT
	return Hands.RIGHT if right_free else Hands.NONE


## The HUD line for a weapon within reach: how to take it, or why the mech cannot.
static func prompt(data: WeaponData, choice: Hands) -> String:
	if data == null:
		return ""
	if choice != Hands.NONE:
		return "Tab + LMB/RMB: pick up %s" % data.display_name
	if data.two_handed:
		return "%s: needs both hands free" % data.display_name
	return "%s: no free hand" % data.display_name
