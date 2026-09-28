class_name DebugDamage
extends Node
## Test keys (until enemies shoot back in Phase 4b): damage the player's own parts.
## F1 head, F2 core, F3 left arm, F4 right arm, F5 legs, F6 shield, F7 back units.
## Each press takes damage_fraction of the part's max HP. F8 destroys the core.

@export var switcher: LoadoutSwitcher
@export_range(0.0, 1.0) var damage_fraction: float = 0.3

const KEYS := {KEY_F1: ["Head"], KEY_F2: ["Core"], KEY_F3: ["Arm L"], KEY_F4: ["Arm R"],
		KEY_F5: ["Legs"], KEY_F6: ["Shield"], KEY_F7: ["Back L", "Back R"]}


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var health := switcher.mech.health
	if health == null:
		return
	if key_event.keycode == KEY_F8:
		health.damage("Core", health.hp.get("Core", 0.0))
		return
	for part_key: String in KEYS.get(key_event.keycode, []):
		health.damage(part_key, health.max_hp.get(part_key, 0.0) * damage_fraction)
