class_name GarageStatPanel
extends PanelContainer
## Live stat preview in the garage (Phase 5): each stat of the build being edited, and the change
## from the build the garage opened with (green = better, red = worse).

const GOOD := Color(0.45, 0.95, 0.5)
const BAD := Color(1.0, 0.45, 0.4)
const WARN := Color(1.0, 0.75, 0.3)

## Text size of the stat rows.
@export var font_size: int = 14

var _grid: GridContainer
var _warning: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "STATS"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 0)
	box.add_child(_grid)
	_warning = Label.new()
	_warning.add_theme_color_override("font_color", WARN)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_warning)


## Shows the stats of loadout, with the change from the stats before.
func show_stats(loadout: Loadout, now: MechStats, before: MechStats, before_loadout: Loadout) -> void:
	for child in _grid.get_children():
		child.queue_free()
	# Rows: name, value now, value before, format, true if more is better.
	var rows := [
		["Weight (t)", now.total_weight_t, before.total_weight_t, "%.1f", false],
		["Load capacity (t)", now.load_capacity_t, before.load_capacity_t, "%.1f", true],
		["Load", now.load_ratio * 100.0, before.load_ratio * 100.0, "%.0f%%", false],
		["Walk speed (m/s)", now.walk_speed, before.walk_speed, "%.1f", true],
		["Boost speed (m/s)", now.walk_speed * now.boost_speed_multiplier,
				before.walk_speed * before.boost_speed_multiplier, "%.1f", true],
		["Boost accel (m/s²)", now.boost_acceleration, before.boost_acceleration, "%.1f", true],
		["Boost energy (/s)", now.boost_energy_per_second, before.boost_energy_per_second, "%.0f", false],
		["Torso turn (°/s)", now.torso_turn_speed_deg, before.torso_turn_speed_deg, "%.0f", true],
		["Leg turn (°/s)", now.leg_turn_speed_deg, before.leg_turn_speed_deg, "%.0f", true],
		["Jump (m)", now.jump_height, before.jump_height, "%.1f", true],
		["Energy", now.energy_capacity, before.energy_capacity, "%.0f", true],
		["Recharge (/s)", now.energy_output, before.energy_output, "%.1f", true],
		["Recharge delay (s)", now.recharge_delay, before.recharge_delay, "%.1f", false],
		["Recoil", now.recoil_multiplier * 100.0, before.recoil_multiplier * 100.0, "%.0f%%", false],
		["Lock range (m)", now.lock_range, before.lock_range, "%.0f", true],
		["Max locks", float(now.max_locks), float(before.max_locks), "%.0f", true],
		["Lock speed", now.lock_on_speed * 100.0, before.lock_on_speed * 100.0, "%.0f%%", true],
	]
	for key in ["Head", "Core", "Arm L", "Arm R", "Legs"]:
		rows.append(["%s HP" % key, now.part_hp.get(key, 0.0), before.part_hp.get(key, 0.0), "%.0f", true])
	rows.append(["Booster HP", _booster_hp(loadout), _booster_hp(before_loadout), "%.0f", true])
	for row in rows:
		_add_row(row[0], row[1], row[2], row[3], row[4])
	_warning.text = "OVERLOADED: the mech is heavier than the legs can carry, it is much slower." \
			if now.load_ratio > 1.0 else ""


func _add_row(title: String, now: float, before: float, format: String, more_is_better: bool) -> void:
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", font_size)
	_grid.add_child(name_label)
	var value := Label.new()
	value.text = format % now
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", font_size)
	_grid.add_child(value)
	var change := Label.new()
	var delta := now - before
	if absf(delta) > 0.05:
		change.text = ("+" if delta > 0.0 else "") + (format % delta)
		change.add_theme_color_override("font_color", GOOD if (delta > 0.0) == more_is_better else BAD)
	change.add_theme_font_size_override("font_size", font_size)
	_grid.add_child(change)


static func _booster_hp(loadout: Loadout) -> float:
	return loadout.booster.hp if loadout != null and loadout.booster != null else 0.0
