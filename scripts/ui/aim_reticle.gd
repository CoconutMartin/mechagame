class_name AimReticle
extends Control
## Draws the crosshair where the mech torso aims (user request 2026-10-14): two brackets "[ ]" with
## the distance to the target above the right one. The brackets show the target's average part HP:
## green (full), orange (half), red (low); white when the target has no HP (ground, buildings).
## The ring and the (hidden) crosshair sit above the screen center (MechAim.screen_offset_up).
## The ring is placed from the torso angle, not from a 3D hit point, so camera shake,
## body bob, and the physics frame rate do not make it jitter. MechAim aims the shots at what the
## camera sees under the ring (MechAim.get_ring_screen_point).

@export var mech_aim: MechAim
## Optional. Gives the missile locks for the lock boxes.
var weapons: WeaponController
@export var lock_color: Color = Color(1.0, 0.35, 0.25, 0.95)
@export var locking_color: Color = Color(1.0, 0.8, 0.3, 0.8)
## Bracket box half size as a part of the screen width and height, bracket tick length (part of the
## half width) and line width (pixels).
@export var half_size: Vector2 = Vector2(0.065, 0.066)
@export var tick_share: float = 0.22
@export var line_width: float = 3.0
## Color with no HP target, and the HP fraction to color (1 = green, 0.5 = orange, 0.1 = red).
@export var color: Color = Color(0.9, 0.95, 0.95, 0.9)
@export var status_colors: Gradient
@export var distance_font_size: int = 16
@export var crosshair_color: Color = Color(1.0, 0.9, 0.3, 0.9)
@export var crosshair_size: float = 6.0
## Draw the camera crosshair (yellow dot). Hidden since 4c (user request).
@export var show_crosshair: bool = false
## Out of effective range (user choice 2026-10-16): when the target is farther than the longest
## effective range of the hand weapons, the brackets fade to this opacity and the distance shows
## out_of_range_text.
@export_range(0.0, 1.0) var out_of_range_alpha: float = 0.35
@export var out_of_range_text: String = "FAR"

var _screen_position: Vector2 = Vector2.ZERO
var _visible_on_screen: bool = false
var _crosshair_position: Vector2 = Vector2.ZERO
var _distance: float = -1.0
var _status: float = -1.0
var _out_of_range: bool = false


func _ready() -> void:
	if status_colors == null:
		status_colors = Gradient.new()
		status_colors.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
		status_colors.colors = PackedColorArray([Color(0.95, 0.1, 0.05), Color(0.95, 0.12, 0.05),
				Color(1.0, 0.55, 0.05), Color(0.25, 1.0, 0.3)])


func _process(_delta: float) -> void:
	_crosshair_position = mech_aim.get_crosshair_screen_point()
	var camera := get_viewport().get_camera_3d()
	_visible_on_screen = camera != null
	if _visible_on_screen:
		_visible_on_screen = absf(mech_aim.get_ring_gap()) < deg_to_rad(80.0)
		_screen_position = mech_aim.get_ring_screen_point()
	# The target can be freed between frames (debris, a destroyed part).
	var target: Object = mech_aim.target if is_instance_valid(mech_aim.target) else null
	_distance = mech_aim.aim_origin.global_position.distance_to(mech_aim.target_point) if target != null else -1.0
	_status = _target_status(target)
	var effective := get_effective_range()
	_out_of_range = _distance >= 0.0 and effective > 0.0 and _distance > effective
	queue_redraw()


## Longest effective range of the hand weapons (meters), or 0 when none has a falloff.
func get_effective_range() -> float:
	if weapons == null:
		return 0.0
	var best := 0.0
	for data: WeaponData in [weapons.right_data, weapons.left_data]:
		if data != null and data.effective_range_m > 0.0:
			best = maxf(best, data.effective_range_m)
	return best


## Average part HP (0 to 1) of what the crosshair is on, or -1 for a thing with no HP.
func _target_status(target: Object) -> float:
	if target == null:
		return -1.0
	var health: MechHealth = null
	if target is PartHitbox:
		health = (target as PartHitbox).health
	elif target is Mech:
		health = (target as Mech).health
	elif target is TargetDummy:
		var dummy := target as TargetDummy
		return clampf(dummy.hp / maxf(dummy.max_hp, 1.0), 0.0, 1.0)
	if health == null or health.max_hp.is_empty():
		return -1.0
	var total := 0.0
	for key: String in health.max_hp:
		total += health.get_fraction(key)
	return total / health.max_hp.size()


func _draw() -> void:
	var rig := mech_aim.camera_rig
	if rig != null and rig.free_camera_amount > 0.0:
		return  # Free camera: no crosshair.
	_draw_locks()
	if show_crosshair:
		var half := crosshair_size * 0.5
		draw_rect(Rect2(_crosshair_position - Vector2(half, half), Vector2(crosshair_size, crosshair_size)), crosshair_color)
	if not _visible_on_screen:
		return
	var p := _screen_position
	var tint := status_colors.sample(_status) if _status >= 0.0 else color
	var text_tint := tint
	if _out_of_range:
		tint.a *= out_of_range_alpha
	var view := get_viewport_rect().size
	var half := Vector2(view.x * half_size.x, view.y * half_size.y)
	var tick := half.x * tick_share
	for sx in [-1.0, 1.0]:
		var top := p + Vector2(sx * half.x, -half.y)
		var bottom := p + Vector2(sx * half.x, half.y)
		draw_line(top, bottom, tint, line_width)
		draw_line(top, top - Vector2(sx * tick, 0.0), tint, line_width)
		draw_line(bottom, bottom - Vector2(sx * tick, 0.0), tint, line_width)
	var text := "%d m" % roundi(_distance) if _distance >= 0.0 else "--- m"
	if _out_of_range:
		text += " " + out_of_range_text
	var font := get_theme_default_font()
	var place := p + Vector2(half.x - tick, -half.y - 6.0)
	draw_string_outline(font, place, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, distance_font_size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, place, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, distance_font_size, text_tint)


## Missile lock-on: the lock box around the mech aim, brackets on locked targets, and a closing
## bracket on the target being locked.
func _draw_locks() -> void:
	if weapons == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for pod in weapons.get_lock_pods():
		if not pod.is_lock_mode():
			continue
		# Lock box: its half size in pixels from the lock angle.
		var focal := get_viewport_rect().size.y * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
		var half := tan(deg_to_rad(pod.data.lock_box_deg)) * focal
		_draw_corners(_screen_position, half, Color(lock_color, 0.6), 2.0)
		for target in pod.locks:
			_draw_target(camera, target, 26.0, lock_color, 3.0)
		if pod.locking != null:
			var closing := lerpf(70.0, 26.0, pod.lock_progress)
			_draw_target(camera, pod.locking, closing, locking_color, 2.0)


func _draw_target(camera: Camera3D, target: Node3D, half: float, tint: Color, width: float) -> void:
	if not is_instance_valid(target):
		return
	var point: Vector3 = target.get_lock_point() if target.has_method(&"get_lock_point") else target.global_position
	if camera.is_position_behind(point):
		return
	_draw_corners(camera.unproject_position(point), half, tint, width)


## Four corner brackets of a square.
func _draw_corners(center: Vector2, half: float, tint: Color, width: float) -> void:
	var arm := half * 0.4
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := center + Vector2(sx * half, sy * half)
			draw_line(corner, corner - Vector2(sx * arm, 0.0), tint, width)
			draw_line(corner, corner - Vector2(0.0, sy * arm), tint, width)
