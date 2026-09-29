class_name GarageCamera
extends Camera3D
## Garage view (Phase 5): circles the mech slowly. Drag with the right mouse button to turn it,
## the mouse wheel moves it in and out. It runs while the game is paused.

## Point to look at, above the mech feet, in meters.
@export var look_height: float = 5.5
## Distance from the mech, in meters (start, nearest, farthest).
@export var distance: float = 19.0
@export var min_distance: float = 10.0
@export var max_distance: float = 32.0
## Camera height above the look point, in meters.
@export var height: float = 2.5
## Turn speed with no input, in degrees per second.
@export var auto_turn_deg: float = 8.0
## Turn per pixel of mouse drag, in degrees.
@export var drag_deg_per_pixel: float = 0.3

var target: Node3D
var _yaw: float = 0.0
var _dragging: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts in front of the mech, a little to its left.
func start(new_target: Node3D) -> void:
	target = new_target
	_yaw = target.global_rotation.y + deg_to_rad(200.0)
	make_current()
	_place()


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not _dragging:
		_yaw += deg_to_rad(auto_turn_deg) * delta
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance - 1.5, min_distance)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance + 1.5, max_distance)
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_yaw -= deg_to_rad(motion.relative.x * drag_deg_per_pixel)


func _place() -> void:
	var center := target.global_position + Vector3.UP * look_height
	global_position = center + Vector3(sin(_yaw), 0.0, cos(_yaw)) * distance + Vector3.UP * height
	look_at(center)
