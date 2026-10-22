class_name GarageCamera
extends Camera3D
## Garage view (Phase 5): stands still in front of the mech. Drag with the right mouse button to turn it
## all the way around and up and down (free look, user request 2026-10-22), drag with the middle mouse
## button to move the look point, the mouse wheel moves it in and out (close up to min_distance). The arrow keys too (user request 2026-10-13): left and right
## turn it, up and down move it in and out (not while a list is open: the list uses the arrows then).
## It runs while the game is paused.

## Point to look at, above the mech feet, in meters.
@export var look_height: float = 5.5
## Distance from the mech, in meters (start, nearest, farthest).
@export var distance: float = 19.0
@export var min_distance: float = 2.0
@export var max_distance: float = 80.0
## Up and down turn limit, in degrees (90 = straight down or up; a little less keeps look_at stable).
@export var max_pitch_deg: float = 88.0
## Look point move per pixel of middle mouse drag, as a part of the distance.
@export var pan_per_pixel: float = 0.002
## Start camera height above the look point, in meters (sets the start pitch).
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
var _pitch: float = 0.0
var _dragging: bool = false
var _panning: bool = false
## Look point offset from the mech, set by the middle mouse drag.
var _pan: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts in front of the mech, a little to its left.
func start(new_target: Node3D) -> void:
	target = new_target
	_yaw = target.global_rotation.y + deg_to_rad(200.0)
	_pitch = atan2(height, distance)
	_pan = Vector3.ZERO
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
		elif button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Steps shrink close up, so the last meters stay easy to set.
			distance = maxf(distance - maxf(distance * 0.1, 0.3), min_distance)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance + maxf(distance * 0.1, 0.3), max_distance)
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_yaw -= deg_to_rad(motion.relative.x * drag_deg_per_pixel)
		var limit := deg_to_rad(max_pitch_deg)
		_pitch = clampf(_pitch + deg_to_rad(motion.relative.y * drag_deg_per_pixel), -limit, limit)
	elif motion != null and _panning:
		var step := distance * pan_per_pixel
		_pan += (-global_basis.x * motion.relative.x + global_basis.y * motion.relative.y) * step


func _place() -> void:
	var center := target.global_position + Vector3.UP * look_height + _pan
	var flat := Vector3(sin(_yaw), 0.0, cos(_yaw)) * cos(_pitch)
	global_position = center + (flat + Vector3.UP * sin(_pitch)) * distance
	look_at(center)
