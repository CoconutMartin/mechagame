class_name AimReticle
extends Control
## Draws the camera crosshair (yellow dot) and a ring where the mech really aims (MechAim.aim_point).
## Both sit a little above the screen center (MechAim.screen_offset_up).

@export var mech_aim: MechAim
@export var radius: float = 14.0
@export var tick_length: float = 7.0
@export var color: Color = Color(0.35, 0.95, 1.0, 0.9)
@export var crosshair_color: Color = Color(1.0, 0.9, 0.3, 0.9)
@export var crosshair_size: float = 6.0

var _screen_position: Vector2 = Vector2.ZERO
var _visible_on_screen: bool = false
var _crosshair_position: Vector2 = Vector2.ZERO


func _process(_delta: float) -> void:
	_crosshair_position = mech_aim.get_crosshair_screen_point()
	var camera := get_viewport().get_camera_3d()
	_visible_on_screen = camera != null and not camera.is_position_behind(mech_aim.aim_point)
	if _visible_on_screen:
		_screen_position = camera.unproject_position(mech_aim.aim_point)
	queue_redraw()


func _draw() -> void:
	var half := crosshair_size * 0.5
	draw_rect(Rect2(_crosshair_position - Vector2(half, half), Vector2(crosshair_size, crosshair_size)), crosshair_color)
	if not _visible_on_screen:
		return
	var p := _screen_position
	draw_arc(p, radius, 0.0, TAU, 32, color, 2.0, true)
	draw_line(p + Vector2(radius, 0), p + Vector2(radius + tick_length, 0), color, 2.0)
	draw_line(p - Vector2(radius, 0), p - Vector2(radius + tick_length, 0), color, 2.0)
	draw_line(p + Vector2(0, radius), p + Vector2(0, radius + tick_length), color, 2.0)
	draw_line(p - Vector2(0, radius), p - Vector2(0, radius + tick_length), color, 2.0)
