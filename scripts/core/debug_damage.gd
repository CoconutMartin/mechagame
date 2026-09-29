class_name DebugDamage
extends Node
## Test keys (until enemies shoot back in Phase 4b): damage the player's own parts.
## F1 head, F2 center torso, F3 left torso, F4 right torso, F5 left arm, F6 right arm, F7 groin,
## F8 left leg, F9 right leg, F10 shield, F11 back units.
## Each press takes damage_fraction of the part's max HP. Hold Shift to destroy the part at once.

@export var switcher: LoadoutSwitcher
@export_range(0.0, 1.0) var damage_fraction: float = 0.3

const KEYS := {KEY_F1: ["Head"], KEY_F2: ["Torso C"], KEY_F3: ["Torso L"], KEY_F4: ["Torso R"],
		KEY_F5: ["Arm L"], KEY_F6: ["Arm R"], KEY_F7: ["Groin"], KEY_F8: ["Leg L"], KEY_F9: ["Leg R"],
		KEY_F10: ["Shield"], KEY_F11: ["Back L", "Back R"]}


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var health := switcher.mech.health
	if health == null:
		return
	for part_key: String in KEYS.get(key_event.keycode, []):
		var amount: float = health.max_hp.get(part_key, 0.0) * damage_fraction
		if key_event.shift_pressed:
			amount = health.hp.get(part_key, 0.0)
		health.damage(part_key, amount)
