class_name WeaponPickupPrompt
extends Label
## The line at the bottom of the screen about the weapon on the ground within reach (user rule 2026-10-17):
## "Tab + LMB/RMB: pick up Auto Cannon", or why the mech cannot take it ("Beam Rifle: needs both hands
## free", "Auto Cannon: no free hand"). Empty and hidden when no weapon is near. Always on (the debug text
## switch does not hide it). DebugHud makes it and gives it the mech.

## Distance of the line from the bottom edge of the screen, in pixels.
@export var bottom_margin: float = 96.0
@export var font_px: int = 22

var mech: Mech

var _control: WeaponHandControl


func _ready() -> void:
	name = "WeaponPickupPrompt"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	anchor_left = 0.0
	anchor_right = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -bottom_margin
	offset_bottom = -bottom_margin + float(font_px) * 1.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override(&"font_size", font_px)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	add_theme_constant_override(&"outline_size", 6)
	visible = false


func _process(_delta: float) -> void:
	if mech == null or not is_instance_valid(mech):
		visible = false
		return
	if _control == null or not is_instance_valid(_control):
		# The hand control is added to the mech a moment after it is built.
		_control = mech.get_node_or_null("WeaponHandControl") as WeaponHandControl
	var line := _control.get_prompt() if _control != null else ""
	if line != text:
		text = line
	visible = line != ""
