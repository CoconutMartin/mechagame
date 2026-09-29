class_name GraphicsMenu
extends PanelContainer
## Graphics quality buttons (Phase 5): Low, Medium, High. Uses the GraphicsSettings autoload.

var _buttons: Array[Button] = []
## The GraphicsSettings autoload (looked up by path, so test runs without autoload names work).
var _settings: Node
var _info: Label


func _ready() -> void:
	_settings = get_node("/root/GraphicsSettings")
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "GRAPHICS"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	var group := ButtonGroup.new()
	for i in 3:
		var button := Button.new()
		button.text = _settings.NAMES[i]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(90, 0)
		button.pressed.connect(_settings.set_preset.bind(i))
		row.add_child(button)
		_buttons.append(button)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(300, 0)
	box.add_child(_info)
	_settings.changed.connect(_refresh.unbind(1))
	_refresh()


func _refresh() -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == _settings.preset)
	_info.text = [
		"Low: no global light, reflections, ambient shadows or fog volume. 75% resolution, hard shadows.",
		"Medium: no global light or reflections. Ambient shadows, fog volume, soft shadows.",
		"High: everything on (global light, reflections, ambient shadows, fog volume, soft shadows).",
	][_settings.preset]
