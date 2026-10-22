class_name ShieldPose
extends Node
## Moves the left arm with the shield. Follows MechShield.amount (LMB, user request 2026-10-22): the left hand
## IK target goes between a rest marker (the arm at the side, the shield held beside the body) and a raised
## marker (the guard), and the elbow direction blends with it. The guard: the shield stands in front of the
## left side of the chest, upright and facing forward, and the hand holds it from behind. `guard` is the place
## of the shield in torso space; ShieldMount puts the shield there and this node puts the hand behind it
## (raised.position = guard * the grip place in the shield frame). The shield keeps the turn it has at rest,
## turned to face forward (yaw) and rolled about its face normal (guard_roll_deg).
## WeaponController sets shield_rest and the guard place of the loaded shield (set_guard).

@export var shield: MechShield
@export var arm_ik: TwoBoneIK
## The left hand IK target. Same parent as the two markers.
@export var hand_target: Node3D
@export var rest: Node3D
@export var raised: Node3D
## Elbow direction with the arm at the side.
@export var pole_rest: Vector3 = Vector3(-1.0, -0.2, 0.3)
## Elbow direction with the shield up.
@export var pole_raised: Vector3 = Vector3(-1.0, -0.6, -0.3)
@export_group("Guard")
## Place of a large shield (Hex Shield) when up: its center, weapon frame torso space (-Z forward, +X right).
@export var guard_large: Vector3 = Vector3(-1.0, 0.3, -3.2)
## Place of a small shield when up.
@export var guard_small: Vector3 = Vector3(-0.8, 0.6, -2.6)
## Turn of a large and a small shield about the plate's face normal when up (degrees).
@export var guard_roll_large_deg: float = 0.0
@export var guard_roll_small_deg: float = 0.0
## The top of the shield leans back toward the body by this much when up (degrees; the rest hold leans the
## top forward by about 13).
@export var guard_pitch_deg: float = 16.0
## Turn about the up axis from the rest hold to facing forward (degrees).
@export var guard_yaw_deg: float = -90.0
## A shield with at least this front area (m2) takes the large values.
@export var large_area_m2: float = 9.0
## The raise: the shield goes from its rest place to the guard place, and the hand moves with the grip. The
## progress of each part is the raise amount to a power (a bigger power = later): the shield forward and up
## (z, y), sideways (x), and its turn. The shield first goes forward beside the body, then in and round, so its
## edge keeps off the hip and the thigh. Lowering runs the same way back. (The hand must stay within the
## reach of the arm all the way: the tool tools/godot/render_shield.gd with SHIELD_SWEEP=1 prints it.)
## Powers (side, forward, turn) of a large and of a small shield.
@export var path_large: Vector3 = Vector3(1.5, 0.4, 2.0)
@export var path_small: Vector3 = Vector3(1.0, 0.8, 1.5)

## The shield model's rest mount marker (a child of the left elbow). WeaponController sets it.
var shield_rest: Node3D
## Where the shield stands when up, torso space. ShieldMount reads it.
var guard: Transform3D = Transform3D.IDENTITY
## True once the guard is known (the rest turn of the shield was read).
var has_guard: bool = false

var _guard_position: Vector3 = Vector3.ZERO
var _guard_roll: float = 0.0
## Powers of the loaded shield (side, forward, turn).
var _path: Vector3 = Vector3(1.5, 0.4, 2.0)
## The place of the shield at rest, torso space (read while the shield is down).
var _rest_basis: Basis = Basis.IDENTITY
var _rest_origin: Vector3 = Vector3.ZERO
var _has_rest: bool = false


func _ready() -> void:
	# Before the arm IK (10).
	process_physics_priority = 5


## WeaponController: the shield that was loaded (its front area picks the large or small guard).
func set_guard(area_m2: float) -> void:
	var large := area_m2 >= large_area_m2
	_guard_position = guard_large if large else guard_small
	_guard_roll = deg_to_rad(guard_roll_large_deg if large else guard_roll_small_deg)
	_path = path_large if large else path_small
	_has_rest = false
	has_guard = false


func _physics_process(_delta: float) -> void:
	if shield_rest != null and shield.amount <= 0.001:
		# The shield is down: read its turn in the torso frame (the guard keeps it, turned forward).
		var torso := raised.get_parent_node_3d()
		var place := torso.global_transform.affine_inverse() * shield_rest.global_transform
		_rest_basis = place.basis.orthonormalized()
		_rest_origin = place.origin
		_has_rest = true
	if shield_rest != null and _has_rest:
		var basis := Basis(Vector3.RIGHT, deg_to_rad(guard_pitch_deg)) * Basis(Vector3.UP, deg_to_rad(guard_yaw_deg)) \
			* _rest_basis * Basis(Vector3.BACK, _guard_roll)
		guard = Transform3D(basis, _guard_position)
		has_guard = true
		raised.position = hand_at(1.0)
	var t := smoothstep(0.0, 1.0, shield.amount)
	if has_guard:
		# The hand holds the shield where it did at rest: the same place in the shield frame.
		hand_target.position = hand_at(shield.amount)
	else:
		hand_target.position = rest.position
	arm_ik.pole_direction = pole_rest.lerp(pole_raised, t)


## The place of the shield (torso space) at this raise amount, from the rest place to the guard.
func place_at(amount: float) -> Transform3D:
	var t := smoothstep(0.0, 1.0, amount)
	var forward := pow(t, _path.y)
	var origin := Vector3(lerpf(_rest_origin.x, guard.origin.x, pow(t, _path.x)),
			lerpf(_rest_origin.y, guard.origin.y, forward), lerpf(_rest_origin.z, guard.origin.z, forward))
	var basis := Basis(_rest_basis.get_rotation_quaternion().slerp(guard.basis.get_rotation_quaternion(), pow(t, _path.z)))
	return Transform3D(basis, origin)


## The hand place (torso space) at this raise amount: the rest hand place moved by what the grip moved.
func hand_at(amount: float) -> Vector3:
	var grip := _grip()
	return rest.position + place_at(amount) * grip - place_at(0.0) * grip


## The place of the grip (the palm) in the shield frame.
func _grip() -> Vector3:
	return shield_rest.transform.affine_inverse() * Vector3(0.0, -arm_ik.lower_length, 0.0)
