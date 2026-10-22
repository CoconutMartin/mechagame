class_name PulseScanStatus
extends Label
## Pulse scan line at the bottom right of the screen: "X SCAN 4/4" when ready, "X SCAN 3/4  18 s" while
## it cools down, "SCAN 0/4" when used up. Hidden when the mech has no pulse scan. Always on (the debug
## text switch does not hide it). DebugHud makes it and gives it the mech.

## Distance from the bottom and right screen edges, in pixels.
@export var margin: float = 24.0
@export var font_px: int = 20
@export var ready_color: Color = Color(0.4, 1.0, 0.5)
@export var wait_color: Color = Color(0.6, 0.6, 0.6)

var mech: Mech

var _scanner: PulseScanner


func _ready() -> void:
	name = "PulseScanStatus"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -320.0
	offset_right = -margin
	offset_top = -margin - float(font_px) * 1.5
	offset_bottom = -margin
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override(&"font_size", font_px)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	add_theme_constant_override(&"outline_size", 6)
	visible = false


func _process(_delta: float) -> void:
	if mech == null or not is_instance_valid(mech):
		visible = false
		return
	if _scanner == null or not is_instance_valid(_scanner):
		# The back pack devices are added a moment after the mech is built.
		_scanner = AuxMount.find_device(mech, PulseScanner) as PulseScanner
		if _scanner == null:
			visible = false
			return
	visible = true
	var count := "%d/%d" % [_scanner.uses_left, _scanner.data.uses]
	var line := "X SCAN " + count
	if _scanner.uses_left <= 0:
		line = "SCAN " + count
	elif _scanner.cooldown_left > 0.0:
		line += "  %d s" % ceili(_scanner.cooldown_left)
	if line != text:
		text = line
	add_theme_color_override(&"font_color", ready_color if _scanner.is_ready() else wait_color)
