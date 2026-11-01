class_name SpinPulseShotgunWeapon
extends PulseShotgunWeapon
## Shotgun 3 (user request 2026-11-01): an X electric pulse shot (x_pattern) after a short hold. Press the trigger: the
## X of heads spins up; after hold_time held (0.2 s) the pulse leaves on its own; the heads then slow down. One shot
## per press (user rule: "Shotguns need manual shooting every time, no auto fire"): let go and press again for the
## next. Letting go before hold_time fires nothing. data.fire_rate 20 = the 0.05 s wait after a shot.

## Spinner node (on the bore axis; the heads under it).
@export var spinner_path: NodePath
## Seconds the trigger must be held for the shot.
@export var hold_time: float = 0.2
## Top spin speed (degrees per second), seconds to reach it, and seconds to stop from it.
@export var spin_max_deg: float = 1080.0
@export var spin_up_time: float = 0.15
@export var spin_down_time: float = 1.2

## True while a press waits for its shot.
var holding: bool = false
## Spin speed now, in degrees per second.
var spin_speed: float = 0.0

var _held_for: float = 0.0
var _spinner: Node3D


func _ready() -> void:
	super()
	_spinner = get_node_or_null(spinner_path) as Node3D


## True while the trigger waits for its shot (WeaponController keeps it the active weapon).
func is_busy() -> bool:
	return holding


func _update(delta: float) -> void:
	var lost := controller.mech.is_fallen or controller.mech.is_wrecked or not controller.holds(self)
	if lost or not trigger_held:
		holding = false
		_held_for = 0.0
		needs_release = false
		return
	if needs_release:
		return
	if trigger_pressed():
		holding = true
		_held_for = 0.0
	if not holding:
		return
	_held_for += delta
	if _held_for >= hold_time and can_use() and controller.weapon_pose.aim_amount >= 0.9:
		holding = false
		needs_release = true
		_fire()


func _process(delta: float) -> void:
	super(delta)
	if holding:
		spin_speed = move_toward(spin_speed, spin_max_deg, spin_max_deg / maxf(spin_up_time, 0.01) * delta)
	else:
		spin_speed = move_toward(spin_speed, 0.0, spin_max_deg / maxf(spin_down_time, 0.01) * delta)
	if _spinner != null and spin_speed > 0.0:
		_spinner.rotate_object_local(Vector3.BACK, deg_to_rad(spin_speed * delta))
