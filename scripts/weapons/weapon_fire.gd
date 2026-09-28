class_name WeaponFire
extends Node
## Fires bullets from the weapon muzzle while the fire key is held and the weapon is raised.
## Bullets fly toward the mech aim point (the blue ring), with a small random spread.

signal fired

@export var input: MechInput
@export var weapon_pose: WeaponPose
@export var mech_aim: MechAim
@export var muzzle: Node3D
@export var bullet_scene: PackedScene
## Optional. Shown for a moment at each shot.
@export var muzzle_flash: MuzzleFlash
## Optional. Gets a small shake at each shot.
@export var camera_shake: CameraShake
## The mech that fires. Its body does not stop its own bullets.
@export var shooter: CollisionObject3D
## Shots per second.
@export var fire_rate: float = 2.0
## Random spread cone, in degrees.
@export var spread_deg: float = 0.4
## Bullet speed in m/s.
@export var bullet_speed: float = 400.0
## The weapon fires only when it is raised this much (0 = rest, 1 = aimed).
@export_range(0.0, 1.0) var raise_needed: float = 0.9
@export var shake_trauma: float = 0.04
@export var shake_kick: float = 0.06

var _cooldown: float = 0.0


func _ready() -> void:
	# After WeaponPose (5), so the muzzle is at this frame's place.
	process_physics_priority = 6


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not input.fire_held or weapon_pose.aim_amount < raise_needed:
		return
	if _cooldown > 0.0:
		return
	_cooldown += 1.0 / fire_rate
	_fire()


func _fire() -> void:
	var origin := muzzle.global_position
	var aim_direction := (mech_aim.aim_point - origin).normalized()
	if aim_direction.is_zero_approx():
		aim_direction = -muzzle.global_basis.z
	var direction := _spread(aim_direction)
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.velocity = direction * bullet_speed
	if shooter != null:
		bullet.exclude = [shooter.get_rid()]
	var world := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(bullet)
	bullet.global_position = origin
	bullet.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	if muzzle_flash != null:
		muzzle_flash.flash()
	if camera_shake != null:
		camera_shake.add_shake(shake_trauma, shake_kick)
	fired.emit()


func _spread(direction: Vector3) -> Vector3:
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(direction).normalized()
	var angle := deg_to_rad(spread_deg) * sqrt(randf())
	var turn := randf() * TAU
	var offset := (side * cos(turn) + up * sin(turn)) * tan(angle)
	return (direction + offset).normalized()
