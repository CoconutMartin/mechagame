class_name AimReticle
extends Control
## Draws a ring where the mech really aims (MechAim.aim_point).
## The center dot is the camera crosshair. The ring moves away from it when the body lags or shakes.

@export var mech_aim: MechAim
@export var radius: float = 14.0
@export var tick_length: float = 7.0
@export var color: Color = Color(0.35, 0.95, 1.0, 0.9)

var _screen_position: Vector2 = Vector2.ZERO
var _visible_on_screen: bool = false


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_visible_on_screen = camera != null and not camera.is_position_behind(mech_aim.aim_point)
	if _visible_on_screen:
		_screen_position = camera.unproject_position(mech_aim.aim_point)
	queue_redraw()


func _draw() -> void:
	if not _visible_on_screen:
		return
	var p := _screen_position
	draw_arc(p, radius, 0.0, TAU, 32, color, 2.0, true)
	draw_line(p + Vector2(radius, 0), p + Vector2(radius + tick_length, 0), color, 2.0)
	draw_line(p - Vector2(radius, 0), p - Vector2(radius + tick_length, 0), color, 2.0)
	draw_line(p + Vector2(0, radius), p + Vector2(0, radius + tick_length), color, 2.0)
	draw_line(p - Vector2(0, radius), p - Vector2(0, radius + tick_length), color, 2.0)
