class_name GarageCamera
extends Camera3D
## Garage view (Phase 5): stands still in front of the mech. Drag with the right mouse button to turn it,
## the mouse wheel moves it in and out. The arrow keys too (user request 2026-10-13): left and right
## turn it, up and down move it in and out (not while a list is open: the list uses the arrows then).
## It runs while the game is paused.

## Point to look at, above the mech feet, in meters.
@export var look_height: float = 5.5
## Distance from the mech, in meters (start, nearest, farthest).
@export var distance: float = 19.0
@export var min_distance: float = 10.0
@export var max_distance: float = 32.0
## Camera height above the look point, in meters.
@export var height: float = 2.5
## Turn speed with no input, in degrees per second (0 = still, user request).
@export var auto_turn_deg: float = 0.0
## Turn per pixel of mouse drag, in degrees.
@export var drag_deg_per_pixel: float = 0.3
## Arrow keys: turn speed (degrees per second) and move speed in and out (meters per second).
@export var key_turn_deg: float = 90.0
@export var key_zoom_speed: float = 12.0

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
	if current and not _list_open():
		_yaw += deg_to_rad(key_turn_deg) * Input.get_axis(&"aim_left", &"aim_right") * delta
		distance = clampf(distance + key_zoom_speed * Input.get_axis(&"aim_up", &"aim_down") * delta,
				min_distance, max_distance)
	_place()


## Arrow keys turn the camera: the menu buttons do not take them (no focus moves).
func _input(event: InputEvent) -> void:
	if not current or _list_open():
		return
	for action: StringName in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		if event.is_action(action):
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()
			return


## True while a drop-down list (a popup window) is open.
func _list_open() -> bool:
	return not get_viewport().get_embedded_subwindows().is_empty()


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
