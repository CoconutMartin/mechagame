class_name PS1TuningMenu
extends PanelContainer
## PS1 look menu in the garage (user requests 2026-10-13): sliders from 1 to 10 for the PS1 skin on the
## mechs, weapons and equipment and for the environment look, a switch for the PS1 look on the
## environment, and "Reset PS1 look" (back to the settings file). Changes show at once and are kept
## (PS1Tuning).

## Rows: [key, label, value at 1, value at 10, exponential]. 10 is the strongest PS1 effect (metal: the
## brightest). snap_grid: 1 = no wobble, 2 to 10 = grid height 960 to 120 (width 4:3).
const ROWS := [
	[&"uv_pixels", "Pixel size", 1024.0, 32.0, true],
	[&"world_pixels_per_meter", "Environment pixel size", 128.0, 4.0, true],
	[&"texels_per_meter", "Detail pixel size", 64.0, 4.0, true],
	[&"detail_strength", "Detail strength (seams, rivets, dirt)", 0.0, 2.0, false],
	[&"metal_brightness", "Metal brightness", 0.3, 1.5, false],
	[&"color_steps", "Color reduction", 64.0, 4.0, true],
	[&"snap_grid", "Wobble (1 = off)", 960.0, 120.0, true],
]

var _sliders := {}
var _values := {}
var _environment: CheckButton


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "PS1 LOOK"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_environment = CheckButton.new()
	_environment.text = "PS1 look on the environment"
	_environment.toggled.connect(func(on: bool) -> void: PS1Tuning.set_environment(get_tree(), on))
	box.add_child(_environment)
	for row: Array in ROWS:
		var head := HBoxContainer.new()
		box.add_child(head)
		var label := Label.new()
		label.text = row[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(label)
		var value := Label.new()
		head.add_child(value)
		var slider := HSlider.new()
		slider.min_value = 1.0
		slider.max_value = 10.0
		slider.step = 0.1
		slider.custom_minimum_size = Vector2(300, 0)
		slider.value_changed.connect(_on_changed.bind(row))
		box.add_child(slider)
		_sliders[row[0]] = slider
		_values[row[0]] = value
	var reset := Button.new()
	reset.text = "Reset PS1 look"
	reset.pressed.connect(_on_reset)
	box.add_child(reset)
	_refresh()


## Setting value for a slider position (1 to 10).
static func to_setting(row: Array, scale: float) -> Variant:
	if row[0] == &"snap_grid":
		if scale < 1.95:
			return Vector2.ZERO
		var height: float = row[2] * pow(row[3] / row[2], (scale - 2.0) / 8.0)
		return Vector2(height * 4.0 / 3.0, height)
	var t := (scale - 1.0) / 9.0
	return row[2] * pow(row[3] / row[2], t) if row[4] else lerpf(row[2], row[3], t)


## Slider position (1 to 10) for a setting value.
static func to_scale(row: Array, value: Variant) -> float:
	if row[0] == &"snap_grid":
		var height := (value as Vector2).y
		if height <= 0.0:
			return 1.0
		return clampf(2.0 + 8.0 * log(height / row[2]) / log(row[3] / row[2]), 2.0, 10.0)
	var v := float(value)
	var t: float = log(v / row[2]) / log(row[3] / row[2]) if row[4] else (v - row[2]) / (row[3] - row[2])
	return clampf(1.0 + 9.0 * t, 1.0, 10.0)


func _on_changed(scale: float, row: Array) -> void:
	PS1Tuning.set_value(get_tree(), row[0], to_setting(row, scale))
	_show(row[0])


func _on_reset() -> void:
	PS1Tuning.reset(get_tree())
	_refresh()


## Sliders to the settings now (no change signals).
func _refresh() -> void:
	var settings := PS1Tuning.settings()
	_environment.set_pressed_no_signal(PS1Tuning.environment_on())
	for row: Array in ROWS:
		(_sliders[row[0]] as HSlider).set_value_no_signal(to_scale(row, settings.get(row[0])))
		_show(row[0])


func _show(key: StringName) -> void:
	var value := (_sliders[key] as HSlider).value
	(_values[key] as Label).text = "off" if key == &"snap_grid" and value < 1.95 else "%.1f" % value
