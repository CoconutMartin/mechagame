class_name DroneStatus
extends Label
## Attack drone line at the bottom right of the screen, over the pulse scan line: "T DRONES 6/6" (drones on the
## pack / total), the drone mod (RECALL or SWARM), "LOCKED" while T holds a lock, "0/6" when none are left. Hidden
## without a drone pack. DebugHud makes it and gives it the mech.

## Distance from the bottom and right screen edges, in pixels (over the scan line).
@export var margin: float = 24.0
@export var line_up_px: float = 30.0
@export var font_px: int = 20
@export var ready_color: Color = Color(0.4, 1.0, 0.5)
@export var lock_color: Color = Color(1.0, 0.35, 0.25)
@export var wait_color: Color = Color(0.6, 0.6, 0.6)

var mech: Mech


func _ready() -> void:
	name = "DroneStatus"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -320.0
	offset_right = -margin
	offset_top = -margin - line_up_px - float(font_px) * 1.5
	offset_bottom = -margin - line_up_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override(&"font_size", font_px)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	add_theme_constant_override(&"outline_size", 6)
	visible = false


func _process(_delta: float) -> void:
	var launcher := DroneLauncher.find(mech) if mech != null and is_instance_valid(mech) else null
	if launcher == null:
		visible = false
		return
	visible = true
	var left := launcher.docked_count()
	var line := "%sDRONES %d/%d" % ["T " if left > 0 else "", left, launcher.total]
	var mod := launcher.get_mod()
	if mod != null:
		line += "  " + ("RECALL" if mod.kind == DroneModData.Kind.RECALL else "SWARM")
	var tint := ready_color if left > 0 else wait_color
	if launcher.held and launcher.locked != null:
		line += "  LOCKED"
		tint = lock_color
	if line != text:
		text = line
	add_theme_color_override(&"font_color", tint)
