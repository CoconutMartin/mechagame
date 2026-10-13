class_name PS1TuningMenu
extends PanelContainer
## PS1 look sliders in the garage (user request 2026-10-13): pixel size, detail, metal brightness,
## color depth and wobble of the PS1 skin on the mechs, weapons and equipment. Changes show at once and
## are kept (PS1Tuning); "Reset PS1 look" goes back to the settings file.

## Rows: [key, label, min, max, step]. snap_grid is one slider (its height; the width is 4:3; 0 = off).
const ROWS := [
	[&"uv_pixels", "Pixel detail (bigger = finer)", 32.0, 1024.0, 16.0],
	[&"texels_per_meter", "Detail pixels per meter", 4.0, 64.0, 1.0],
	[&"detail_strength", "Detail strength (seams, rivets, dirt)", 0.0, 2.0, 0.05],
	[&"metal_brightness", "Metal brightness", 0.3, 1.5, 0.05],
	[&"color_steps", "Color steps (smaller = fewer colors)", 4.0, 64.0, 1.0],
	[&"snap_grid", "Wobble grid (smaller = more wobble, 0 = off)", 0.0, 960.0, 10.0],
]

var _sliders := {}
var _values := {}


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "PS1 LOOK"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
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
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.custom_minimum_size = Vector2(300, 0)
		slider.value_changed.connect(_on_changed.bind(row[0]))
		box.add_child(slider)
		_sliders[row[0]] = slider
		_values[row[0]] = value
	var reset := Button.new()
	reset.text = "Reset PS1 look"
	reset.pressed.connect(_on_reset)
	box.add_child(reset)
	_refresh()


func _on_changed(value: float, key: StringName) -> void:
	var setting: Variant = value
	if key == &"snap_grid":
		setting = Vector2(value * 4.0 / 3.0, value)
	PS1Tuning.set_value(get_tree(), key, setting)
	_show(key)


func _on_reset() -> void:
	PS1Tuning.reset(get_tree())
	_refresh()


## Sliders to the settings now (no change signals).
func _refresh() -> void:
	var settings := PS1Tuning.settings()
	for key: StringName in _sliders:
		var value: Variant = settings.get(key)
		(_sliders[key] as HSlider).set_value_no_signal((value as Vector2).y if key == &"snap_grid" else float(value))
		_show(key)


func _show(key: StringName) -> void:
	var value := (_sliders[key] as HSlider).value
	(_values[key] as Label).text = "off" if key == &"snap_grid" and value <= 0.0 else ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
