class_name HitReaction
extends Node
## Hit reactions (Phase 8b): each hit kicks the body on springs, so it flinches and swings back.
## The part that is hit sets the direction:
##   Head, center torso: the torso leans back.
##   Left side (torso L, arm L, shield, back unit L): the left side is pushed back, the torso turns
##   left and rolls right. Right side: the mirror.
##   Groin, legs: the knees dip, the body rolls toward the hit leg. Booster: the torso leans forward.
## Bigger hits push more (damage / reference_damage, up to max_push). Many hits close together
## (a missile blast hits several parts) add up; past stagger_damage in stagger_window seconds the
## mech staggers: a much bigger push back and a deep knee dip.
## TorsoPose adds lean_deg, roll_deg and yaw_deg. MechLegSwing adds crouch (knee dip).

@export var mech: Mech
## Optional. The camera shakes on hits (only the player camera shows it).
@export var camera_shake: CameraShake

## Damage that gives a full normal flinch.
@export var reference_damage: float = 150.0
## Largest push of one hit, in full flinches.
@export var max_push: float = 2.5
## Flinch sizes for one full flinch, in degrees.
@export var lean_deg_per_hit: float = 3.5
@export var twist_deg_per_hit: float = 4.5
@export var roll_deg_per_hit: float = 2.0
## Knee dip for one full flinch, in degrees of hip bend (knees bend twice as much).
@export var crouch_deg_per_hit: float = 4.0
## Stagger: total damage within stagger_window seconds, and the extra push.
@export var stagger_damage: float = 450.0
@export var stagger_window: float = 0.35
@export var stagger_lean_deg: float = 9.0
@export var stagger_crouch_deg: float = 12.0
## Spring speed (swings per second) and damping (lower = more swings).
@export var frequency: float = 2.2
@export_range(0.05, 1.0) var damping: float = 0.4
## Camera shake per damage point (trauma), and its cap.
@export var shake_per_damage: float = 0.0012
@export var max_shake: float = 0.35

## Degrees. Lean: positive = forward. Roll: positive = head to the left. Yaw: positive = turn left.
var lean_deg: float = 0.0
var roll_deg: float = 0.0
var yaw_deg: float = 0.0
## Knee dip in radians of hip bend.
var crouch: float = 0.0

var _lean := AimSpring.new(0.0)
var _roll := AimSpring.new(0.0)
var _yaw := AimSpring.new(0.0)
var _crouch := AimSpring.new(0.0)
var _recent: float = 0.0
var _staggered: bool = false


func _ready() -> void:
	# Before TorsoPose (3) and after the mech moves.
	process_physics_priority = 2
	# Mechs without part HP (no MechHealth) never flinch.
	var health := mech.get_node_or_null(^"MechHealth") as MechHealth
	if health != null:
		health.damaged.connect(_on_damaged)


func _on_damaged(key: String, amount: float) -> void:
	if mech.is_wrecked or mech.is_fallen or amount <= 0.0:
		return
	var push := minf(amount / reference_damage, max_push)
	# Direction of the push for this part: [lean, yaw, roll, crouch] in full flinches.
	var direction := Vector4(-1.0, 0.0, 0.0, 0.2)
	match key:
		"Torso L", "Arm L", "Shield", "Back L":
			direction = Vector4(-0.3, 1.0, -0.6, 0.1)
		"Torso R", "Arm R", "Back R":
			direction = Vector4(-0.3, -1.0, 0.6, 0.1)
		"Groin":
			direction = Vector4(0.3, 0.0, 0.0, 1.0)
		"Leg L":
			direction = Vector4(0.2, 0.3, 0.8, 1.0)
		"Leg R":
			direction = Vector4(0.2, -0.3, -0.8, 1.0)
		"Booster":
			direction = Vector4(1.0, 0.0, 0.0, 0.3)
	_kick(_lean, direction.x * lean_deg_per_hit * push)
	_kick(_yaw, direction.y * twist_deg_per_hit * push)
	_kick(_roll, direction.z * roll_deg_per_hit * push)
	_kick(_crouch, direction.w * crouch_deg_per_hit * push)
	_recent += amount
	if _recent >= stagger_damage and not _staggered:
		_staggered = true
		_kick(_lean, -stagger_lean_deg)
		_kick(_crouch, stagger_crouch_deg)
	if camera_shake != null:
		var trauma := minf(amount * shake_per_damage, max_shake)
		camera_shake.add_shake(trauma, trauma)


## A kick: a start speed that makes the spring swing out to about this many degrees.
func _kick(spring: AimSpring, degrees: float) -> void:
	spring.velocity += degrees * TAU * frequency


func _physics_process(delta: float) -> void:
	_recent = maxf(_recent - stagger_damage / stagger_window * delta, 0.0)
	if _recent <= 0.0:
		_staggered = false
	for spring in [_lean, _roll, _yaw, _crouch]:
		(spring as AimSpring).update(0.0, frequency, damping, 45.0, delta)
	lean_deg = _lean.value
	roll_deg = _roll.value
	yaw_deg = _yaw.value
	# The knees only bend (no dip above standing).
	crouch = deg_to_rad(maxf(_crouch.value, 0.0))
