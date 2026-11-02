class_name SkeletalHeadSteady
extends SkeletonModifier3D
## Keeps the rigged mech's head steady while it aims or shoots (user request 2026-11-02: "always keep the head
## steady when aiming down or when shooting weapons"). What moved the head before:
##   - the idle head scan (Head_Scan, always blended into the head track) kept turning it up to 17 degrees to
##     each side while the weapon fired;
##   - the torso follows the aim with its twist and, in the sniping stance, bends with the aim height (up to
##     30 degrees, SkeletalArmRig); the head looked along the rifle on top of that (up to 30 degrees below the
##     horizon), so aiming down tilted the head into the chest;
##   - every shot kicks the aim (FreeAim, camera), and the torso twist follows it, so the head jerked with it.
## While a weapon is aimed (WeaponPose.aim_amount) or fires (and hold_time seconds after the last trigger) this
## node sets the head's world turn from scratch: the heading is the torso's heading, low-pass filtered (the shot
## kicks and the hip jolts do not pass; a real turn follows within a fraction of a second), the elevation is a
## small share of the torso's elevation, limited and filtered, and the head stays level (no roll). It blends in and
## out, and it lets go during a dodge, melee attack, hit reaction, stagger and death: those clips own the head.
## Skeleton space: +Z is the front, +Y is up. A skeleton modifier must be a child of the Skeleton3D; this node
## moves itself there at start. Keep it after every other pose node (before AccessoryFollow).

@export var model: Node3D
@export var mech: Mech
@export var weapon_pose: WeaponPose
@export var weapons: WeaponController

@export_group("Hold")
## The head holds for this many seconds after the last trigger pull.
@export var hold_time: float = 1.0
## How fast the hold blends in and out (1 / seconds).
@export var blend_in_speed: float = 5.0
@export var blend_out_speed: float = 3.0

@export_group("Heading")
## Filter time (s) of the head heading. The aim kick of a shot (about 0.1 s) is lost in it; a long turn follows.
@export var yaw_filter_time: float = 0.3
## Fastest the head heading turns (degrees per second).
@export var max_yaw_speed_deg: float = 120.0

@export_group("Elevation")
## The head takes this share of the torso's elevation (aiming down does not nod the head down).
@export_range(0.0, 1.0) var pitch_share: float = 0.2
## Largest head elevation (degrees) below and above the horizon.
@export var max_down_deg: float = 6.0
@export var max_up_deg: float = 8.0
## Filter time (s) of the head elevation.
@export var pitch_filter_time: float = 0.35
## The head may not tilt further than this (degrees) from the torso's up axis (it may turn about it freely): a larger
## tilt sinks the head into the chest (the neck hollow is shallow; tools/godot/test_head_clip.gd). A bent torso
## (the sniping stance) takes the head along within this limit.
@export var max_neck_tilt_deg: float = 4.0

@export_group("Bones")
@export var head_bone: StringName = &"head"
@export var torso_bone: StringName = &"torso"

## The hold now (0 = the animation has the head, 1 = steady). For tests.
var amount: float = 0.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _started: bool = false
var _since_trigger: float = 99.0
var _clips: Array[Node] = []


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


## True while the weapon is aimed or fired lately.
func _wanted(delta: float) -> bool:
	var held := false
	if weapons != null:
		for weapon: MechWeapon in [weapons.right_weapon, weapons.left_weapon]:
			if weapon != null and is_instance_valid(weapon) and weapon.trigger_held:
				held = true
	_since_trigger = 0.0 if held else _since_trigger + delta
	var aimed := weapon_pose != null and weapon_pose.weapon != null and weapon_pose.aim_amount > 0.05
	# The aim key (a one-hand gun raises only when it fires) holds the head too, so it settles before the first shot.
	aimed = aimed or (mech != null and mech.input != null and mech.input.aim_held)
	return aimed or _since_trigger < hold_time


## True while a clip owns the head (dodge, melee, hit, stagger, death).
func _clip_busy() -> bool:
	if _clips.is_empty() and mech != null:
		for clip_name in ["DodgeAnimation", "MeleeAnimation", "HitAnimation", "StaggerAnimation", "DeathAnimation"]:
			var clip := mech.find_child(clip_name, true, false)
			if clip != null:
				_clips.append(clip)
	for clip: Node in _clips:
		if not is_instance_valid(clip):
			continue
		if clip.get("is_playing") == true:
			return true
		if clip.has_method("is_fading") and clip.call("is_fading"):
			return true
		if clip.has_method("is_staggered") and clip.call("is_staggered"):
			return true
	return false


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	var head := skeleton.find_bone(head_bone)
	var torso := skeleton.find_bone(torso_bone)
	if head < 0 or torso < 0 or mech == null:
		return
	var wanted := _wanted(delta) and not _clip_busy() and (mech.health == null or not mech.health.is_destroyed)
	amount = move_toward(amount, 1.0 if wanted else 0.0, (blend_in_speed if wanted else blend_out_speed) * delta)
	# The torso's own heading and elevation now (the chest turns with the aim; the animation does not count).
	var skeleton_yaw := _yaw_of(skeleton.global_basis)
	var torso_rest := skeleton.get_bone_global_rest(torso).basis.orthonormalized()
	var forward := skeleton.get_bone_global_pose(torso).basis.orthonormalized() * (torso_rest.inverse() * Vector3.BACK)
	var flat := Vector2(forward.x, forward.z)
	if flat.length() < 0.01:
		return
	var yaw_world := atan2(forward.x, forward.z) + skeleton_yaw
	var pitch_now := atan2(forward.y, flat.length())
	if not _started or amount <= 0.0:
		# Not holding: follow the torso at once, so the hold starts from where the head looks.
		_yaw = yaw_world
		_pitch = clampf(pitch_now * pitch_share, deg_to_rad(-max_down_deg), deg_to_rad(max_up_deg))
		_started = true
	else:
		var turn := wrapf(yaw_world - _yaw, -PI, PI)
		var step := turn * (1.0 - exp(-delta / maxf(yaw_filter_time, 0.001)))
		var limit := deg_to_rad(max_yaw_speed_deg) * delta
		_yaw = wrapf(_yaw + clampf(step, -limit, limit), -PI, PI)
		var pitch_goal := clampf(pitch_now * pitch_share, deg_to_rad(-max_down_deg), deg_to_rad(max_up_deg))
		_pitch = lerpf(_pitch, pitch_goal, 1.0 - exp(-delta / maxf(pitch_filter_time, 0.001)))
	if amount <= 0.0:
		return
	# The head's level frame: forward along the filtered heading and elevation, up as the world up.
	var yaw_skeleton := _yaw - skeleton_yaw
	var aim := Vector3(sin(yaw_skeleton) * cos(_pitch), sin(_pitch), cos(yaw_skeleton) * cos(_pitch))
	var up := (skeleton.global_basis.orthonormalized().inverse() * Vector3.UP).normalized()
	var head_up := (up - aim * up.dot(aim)).normalized()
	var target_frame := Basis(head_up.cross(aim), head_up, aim)
	var rest := skeleton.get_bone_global_rest(head).basis.orthonormalized()
	var forward_local := rest.inverse() * Vector3.BACK
	var up_local := rest.inverse() * Vector3.UP
	var local_frame := Basis(up_local.cross(forward_local), up_local, forward_local)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(head)).basis.orthonormalized()
	var steady := (parent.inverse() * target_frame * local_frame.inverse()).get_rotation_quaternion()
	# The neck: a free turn about the head's up axis, a limited tilt (swing-twist split of the turn from the rest pose).
	var rest_local := skeleton.get_bone_rest(head).basis.get_rotation_quaternion()
	steady = rest_local * _limit_tilt(rest_local.inverse() * steady, up_local.normalized(), deg_to_rad(max_neck_tilt_deg))
	var from := skeleton.get_bone_pose_rotation(head)
	skeleton.set_bone_pose_rotation(head, from.slerp(steady, smoothstep(0.0, 1.0, amount)))


## Heading of a basis (radians about the up axis; 0 when its +Z points along the world +Z).
static func _yaw_of(basis: Basis) -> float:
	var z := basis.orthonormalized() * Vector3.BACK
	return atan2(z.x, z.z)


## The turn q with its swing (the tilt away from axis) limited to limit radians. q = swing * twist, the twist is the
## part about axis (free).
static func _limit_tilt(q: Quaternion, axis: Vector3, limit: float) -> Quaternion:
	var along := axis * Vector3(q.x, q.y, q.z).dot(axis)
	var twist := Quaternion(along.x, along.y, along.z, q.w)
	if twist.length_squared() < 0.000001:
		return q
	twist = twist.normalized()
	var swing := q * twist.inverse()
	var angle := swing.get_angle()
	if angle > PI:
		angle = TAU - angle
	if angle <= limit or angle < 0.0001:
		return q
	return Quaternion.IDENTITY.slerp(swing, limit / angle) * twist
