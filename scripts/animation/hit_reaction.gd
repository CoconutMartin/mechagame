class_name HitReaction
extends Node
## Hit reactions (Phase 8b): each hit kicks the body on springs, so it flinches and swings back.
## The part that is hit sets the direction:
##   Head, center torso: the torso leans back.
##   Left side (torso L, arm L, shield, back unit L): the left side is pushed back, the torso turns
##   left and rolls right. Right side: the mirror.
##   Groin, legs: the knees dip, the body rolls toward the hit leg. Booster: the torso leans forward.
## Bigger hits push more (damage / reference_damage, up to max_push). Many hits close together
## (a missile blast hits several parts) add up.
## User request 2026-11-02: hit reactions are 50% smaller, and only a full stagger bar interrupts the
## mech. A normal hit gives the small spring kick above. The big push back and deep knee dip come
## only when MechStability emits staggered (the bar is full), not from the damage sum.
## TorsoPose adds lean_deg, roll_deg and yaw_deg. MechLegSwing adds crouch (knee dip).

@export var mech: Mech
## Optional. The camera shakes on hits (only the player camera shows it).
@export var camera_shake: CameraShake

## Damage that gives a full normal flinch.
@export var reference_damage: float = 150.0
## Largest push of one hit, in full flinches.
@export var max_push: float = 2.5
## Flinch sizes for one full flinch, in degrees (user request 2026-11-02: half of the old 3.5, 4.5, 2.0).
@export var lean_deg_per_hit: float = 1.75
@export var twist_deg_per_hit: float = 2.25
@export var roll_deg_per_hit: float = 1.0
## Knee dip for one full flinch, in degrees of hip bend (knees bend twice as much). Half of the old 4.0
## (user request 2026-11-02).
@export var crouch_deg_per_hit: float = 2.0
## Extra push when the stagger bar is full (MechStability.staggered): lean back and knee dip, in degrees.
@export var stagger_lean_deg: float = 9.0
@export var stagger_crouch_deg: float = 12.0
## Spring speed (swings per second) and damping (lower = more swings).
@export var frequency: float = 2.2
@export_range(0.05, 1.0) var damping: float = 0.4
## Camera shake per damage point (trauma), and its cap. Half of the old 0.0012 and 0.35 (user request
## 2026-11-02).
@export var shake_per_damage: float = 0.0006
@export var max_shake: float = 0.175

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


func _ready() -> void:
	# Before TorsoPose (3) and after the mech moves.
	process_physics_priority = 2
	# Mechs without part HP (no MechHealth) never flinch.
	var health := mech.get_node_or_null(^"MechHealth") as MechHealth
	if health != null:
		health.damaged.connect(_on_damaged)
	_connect_stability.call_deferred()


## SkeletalStaggerAnimation makes the stagger meter after _ready, so the connection waits a frame.
func _connect_stability() -> void:
	var health := mech.get_node_or_null(^"MechHealth") as MechHealth
	if health != null and health.stability != null and not health.stability.staggered.is_connected(_on_staggered):
		health.stability.staggered.connect(_on_staggered)


## The stagger bar is full: the big push back and the deep knee dip.
func _on_staggered(_from: Vector3) -> void:
	if mech.is_wrecked or mech.is_fallen:
		return
	_kick(_lean, -stagger_lean_deg)
	_kick(_crouch, stagger_crouch_deg)


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
	if camera_shake != null:
		var trauma := minf(amount * shake_per_damage, max_shake)
		camera_shake.add_shake(trauma, trauma)


## A kick: a start speed that makes the spring swing out to about this many degrees.
func _kick(spring: AimSpring, degrees: float) -> void:
	spring.velocity += degrees * TAU * frequency


func _physics_process(delta: float) -> void:
	for spring in [_lean, _roll, _yaw, _crouch]:
		(spring as AimSpring).update(0.0, frequency, damping, 45.0, delta)
	lean_deg = _lean.value
	roll_deg = _roll.value
	yaw_deg = _yaw.value
	# The knees only bend (no dip above standing).
	crouch = deg_to_rad(maxf(_crouch.value, 0.0))
