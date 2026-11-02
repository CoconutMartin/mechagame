class_name SpinPulseShotgunWeapon
extends PulseShotgunWeapon
## Shotgun 3 (user request 2026-11-01): an X electric pulse shot (x_pattern) after a short hold. Press the trigger: the
## pulse leaves on its own after hold_time held (0.2 s); at the shot the X of heads snaps a quarter turn (2026-11-02). One shot
## per press (user rule: "Shotguns need manual shooting every time, no auto fire"): let go and press again for the
## next. Letting go before hold_time fires nothing. data.fire_rate 20 = the 0.05 s wait after a shot.

## Spinner node (on the bore axis; the heads under it).
@export var spinner_path: NodePath
## Seconds the trigger must be held for the shot.
@export var hold_time: float = 0.2
## Head snap (user 2026-11-02: "the head should rotate snap, not spin"): at each shot the X of heads turns
## snap_deg about the bore in snap_time, fast at the start and a hard stop, then holds still.
@export var snap_deg: float = 90.0
@export var snap_time: float = 0.08

## True while a press waits for its shot.
var holding: bool = false
## Seconds since the last snap started (large = still).
var snap_age: float = 100.0
var _snap_from: float = 0.0
var _snap_angle: float = 0.0
var _spinner_rest := Basis.IDENTITY

var _held_for: float = 0.0
var _spinner: Node3D


func _ready() -> void:
	super()
	_spinner = get_node_or_null(spinner_path) as Node3D
	if _spinner != null:
		_spinner_rest = _spinner.basis


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
		_snap_from = _snap_angle
		snap_age = 0.0


func _process(delta: float) -> void:
	super(delta)
	if _spinner == null or snap_age > snap_time:
		return
	snap_age += delta
	var t := clampf(snap_age / maxf(snap_time, 0.001), 0.0, 1.0)
	# Ease out: most of the turn at once, then a hard stop.
	_snap_angle = _snap_from + deg_to_rad(snap_deg) * (1.0 - pow(1.0 - t, 3.0))
	_spinner.basis = _spinner_rest * Basis(Vector3.BACK, _snap_angle)


## The heads' turn about the bore now (radians).
func snap_angle() -> float:
	return _snap_angle
