class_name AimReticle
extends Control
## Draws the camera crosshair (yellow dot) and a ring where the mech torso aims (blue ring).
## Both sit above the screen center (MechAim.screen_offset_up).
## The ring is placed from the torso angle, not from a 3D hit point, so camera shake,
## body bob, and the physics frame rate do not make it jitter. MechAim aims the shots at what the
## camera sees under the ring (MechAim.get_ring_screen_point).
## Hit marker (small red X): where a shot from the right weapon muzzle really hits. The muzzle is
## lower than the camera, so a wall or a car in front of the muzzle can block a shot that the ring
## shows as clear.

@export var mech_aim: MechAim
## Optional. Gives the missile locks for the lock boxes.
var weapons: WeaponController
@export var lock_color: Color = Color(1.0, 0.35, 0.25, 0.95)
@export var locking_color: Color = Color(1.0, 0.8, 0.3, 0.8)
@export var radius: float = 14.0
@export var tick_length: float = 7.0
@export var color: Color = Color(0.35, 0.95, 1.0, 0.9)
@export var crosshair_color: Color = Color(1.0, 0.9, 0.3, 0.9)
@export var crosshair_size: float = 6.0
## Color of the hit marker.
@export var hit_color: Color = Color(1.0, 0.3, 0.2, 0.95)
## Half size of the hit marker X, in pixels.
@export var hit_size: float = 5.0

var _screen_position: Vector2 = Vector2.ZERO
var _visible_on_screen: bool = false
var _crosshair_position: Vector2 = Vector2.ZERO
var _hit_position: Vector2 = Vector2.ZERO
var _hit_visible: bool = false


func _process(_delta: float) -> void:
	_crosshair_position = mech_aim.get_crosshair_screen_point()
	var camera := get_viewport().get_camera_3d()
	_visible_on_screen = camera != null
	if _visible_on_screen:
		_visible_on_screen = absf(mech_aim.get_ring_gap()) < deg_to_rad(80.0)
		_screen_position = mech_aim.get_ring_screen_point()
	_update_hit(camera)
	queue_redraw()


## Casts a ray from the right weapon muzzle through the aim point (the path of the shot).
func _update_hit(camera: Camera3D) -> void:
	_hit_visible = false
	if camera == null or weapons == null or not is_instance_valid(weapons.right_weapon):
		return
	var muzzle := weapons.right_weapon.get_muzzle()
	if muzzle == null:
		return
	var mech := mech_aim.mech
	var origin := muzzle.global_position
	var direction := (mech_aim.aim_point - origin).normalized()
	if direction.is_zero_approx():
		return
	var to := origin + direction * mech_aim.max_range
	var query := PhysicsRayQueryParameters3D.create(origin, to, mech_aim.collision_mask, mech.get_hit_exclude())
	var hit := mech.get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit.position if hit else to
	if camera.is_position_behind(point):
		return
	_hit_position = camera.unproject_position(point)
	_hit_visible = true


func _draw() -> void:
	var rig := mech_aim.camera_rig
	if rig != null and rig.front_view_amount > 0.0:
		return  # Front view: no crosshair.
	_draw_locks()
	var half := crosshair_size * 0.5
	draw_rect(Rect2(_crosshair_position - Vector2(half, half), Vector2(crosshair_size, crosshair_size)), crosshair_color)
	if _hit_visible:
		var h := hit_size
		draw_line(_hit_position + Vector2(-h, -h), _hit_position + Vector2(h, h), hit_color, 2.0, true)
		draw_line(_hit_position + Vector2(-h, h), _hit_position + Vector2(h, -h), hit_color, 2.0, true)
	if not _visible_on_screen:
		return
	var p := _screen_position
	draw_arc(p, radius, 0.0, TAU, 32, color, 2.0, true)
	draw_line(p + Vector2(radius, 0), p + Vector2(radius + tick_length, 0), color, 2.0)
	draw_line(p - Vector2(radius, 0), p - Vector2(radius + tick_length, 0), color, 2.0)
	draw_line(p + Vector2(0, radius), p + Vector2(0, radius + tick_length), color, 2.0)
	draw_line(p - Vector2(0, radius), p - Vector2(0, radius + tick_length), color, 2.0)


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
