class_name OrbitCamera
extends Camera3D
## Circles slowly around a point and looks at it. For model viewer scenes.
## Hold the left mouse button and drag to turn it by hand; the mouse wheel zooms.

## Point to look at (world space).
@export var target: Vector3 = Vector3(0.0, 6.0, 0.0)
## Distance from the target in meters.
@export var distance: float = 28.0
## Height above the target in meters.
@export var height: float = 4.0
## Turn speed in degrees per second (0 = no auto turn).
@export var turn_speed: float = 12.0
## Degrees turned per pixel of mouse drag.
@export var drag_speed: float = 0.3
## Meters per mouse wheel step.
@export var zoom_step: float = 2.0

var angle: float = 30.0
var dragging: bool = false


func _process(delta: float) -> void:
	if not dragging:
		angle += turn_speed * delta
	var rad := deg_to_rad(angle)
	position = target + Vector3(sin(rad) * distance, height, cos(rad) * distance)
	look_at(target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(5.0, distance - zoom_step)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance += zoom_step
	elif event is InputEventMouseMotion and dragging:
		angle -= (event as InputEventMouseMotion).relative.x * drag_speed
