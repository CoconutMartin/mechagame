class_name SkeletalAnklePitch
extends SkeletonModifier3D
## Ankle pitch of the rigged mech while it walks, runs and strafes (user report 2026-10-15: the feet
## stay flat). The locomotion clips pitch the foot only a little (a few degrees), so this adds more:
##   Toe-off: while the ankle rises, the heel lifts first and the toes stay on the ground. The foot
##   turns toe down about its toes (the ankle goes up with it).
##   Swing: the toes keep pointing down while the foot is up.
##   Heel strike: before the landing, while the ankle comes down, the toes point up so the heel
##   touches first. The foot then rolls flat.
## A planted foot (ankle at its standing height) is not turned: it stays flat on the ground.
## The turn is added on top of the clip pose, about the foot bone's own side axis, and the foot bone
## moves up as much as the turn would push the toes (or heel) into the ground.
## A skeleton modifier must be a child of the Skeleton3D. SkeletalLocomotion adds this node at start,
## after the other modifiers (it runs last, after the leg poses).

@export var mech: Mech
@export var foot_bones: PackedStringArray = ["foot_L", "foot_R"]

@export_group("Foot Shape")
## Ankle bone to sole, heel and toe: in meters along the foot (bone-local Y = toward the toes,
## bone-local -Z = down). Measured on the model's foot meshes.
@export var sole_depth: float = 1.05
@export var heel_length: float = 0.91
@export var toe_length: float = 1.73

@export_group("Toe-off")
## Toe-down angle (degrees) the foot reaches while the ankle rises toe_off_height above standing.
@export var toe_off_deg: float = 26.0
## Ankle rise (m) that gives the full toe-off angle. The angle grows with the rise.
@export var toe_off_height: float = 0.25
## Above this ankle rise (m) the clip pose alone is used again (the swing). Must be above toe_off_height.
@export var toe_off_end_height: float = 0.6

@export_group("Heel strike")
## Toe-up angle (degrees) the foot reaches strike_height above the ground, while the ankle comes down.
@export var strike_deg: float = 14.0
## Ankle height (m above standing) of the full heel strike angle. The angle shrinks to flat at the ground.
@export var strike_height: float = 0.2
## Above this ankle height (m) the clip pose alone is used again. Must be above strike_height.
@export var strike_end_height: float = 0.5

@export_group("Blend")
## Ground speed (m/s) at which the ankle pitch is fully on. It is off while the mech stands.
@export var full_speed: float = 3.0
## Ankle speed (m/s up or down) that counts as a rise or a fall.
@export var move_threshold: float = 0.3
## How fast the added turn follows its target (per second).
@export var follow_speed: float = 60.0
## Fastest change of the added turn (degrees per second). Without it the foot flicked from toes down to
## toes up in 0.1 s just before each landing (user report 2026-10-22: the walk looks like a rooster).
@export var max_turn_rate_deg: float = 100.0

## Added turn now (degrees, + = toes up) per foot (for tests).
var added_deg: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])

var _bones: PackedInt32Array = PackedInt32Array()
var _last_height: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _rising: Array[bool] = [false, false]
var _amount: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if mech == null or skeleton == null or delta <= 0.0:
		return
	if _bones.is_empty():
		for bone_name in foot_bones:
			_bones.append(skeleton.find_bone(bone_name))
	var grounded := mech.is_on_floor() and not mech.is_fallen and not mech.is_wrecked
	var speed_weight := smoothstep(0.0, full_speed, mech.get_horizontal_speed()) if grounded else 0.0
	var follow := 1.0 - exp(-follow_speed * delta)
	for side in _bones.size():
		var bone := _bones[side]
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var height := world.origin.y - mech.global_position.y - sole_depth
		var speed := (height - _last_height[side]) / delta
		_last_height[side] = height
		if speed > move_threshold:
			_rising[side] = true
		elif speed < -move_threshold:
			_rising[side] = false
		# Toes-up elevation of the foot now (0 = flat).
		var clip_deg := rad_to_deg(asin(clampf(world.basis.y.y, -1.0, 1.0)))
		var target_deg := _target_deg(clip_deg, height, _rising[side])
		var wanted := (target_deg - clip_deg) * speed_weight
		_amount[side] = move_toward(_amount[side], lerpf(_amount[side], wanted, follow), max_turn_rate_deg * delta)
		added_deg[side] = _amount[side]
		if absf(_amount[side]) > 0.01:
			_apply(skeleton, bone, world, deg_to_rad(_amount[side]))


## Toes-up elevation (degrees) the foot should have: the clip pose, pushed toward toe-off while the
## ankle rises and toward heel strike while it comes down. Never less toe-down than the clip.
func _target_deg(clip_deg: float, height: float, rising: bool) -> float:
	var up := maxf(height, 0.0)
	if rising:
		var off := -toe_off_deg * clampf(up / toe_off_height, 0.0, 1.0)
		var weight := 1.0 - smoothstep(toe_off_height, toe_off_end_height, up)
		return lerpf(clip_deg, minf(clip_deg, off), weight)
	var strike := strike_deg * clampf(up / strike_height, 0.0, 1.0)
	var weight := 1.0 - smoothstep(strike_height, strike_end_height, up)
	return lerpf(clip_deg, maxf(clip_deg, strike), weight)


## Turns the foot toes-up by pitch (radians, - = toes down) about its side axis, and lifts the foot so
## the toes (toes down) or the heel (toes up) stay at the height they had.
func _apply(skeleton: Skeleton3D, bone: int, world: Transform3D, pitch: float) -> void:
	# A turn of the bone about its X axis by + moves the toes (+Y) toward the bone's +Z. The foot bone's +Z
	# points up (the sole is at -Z), so + is toes up. (Before 2026-10-22 this was -pitch: the added pitch
	# turned the toes the wrong way, so the toes dug 0.2 m into the ground before each landing and the
	# foot lifted again: the foot "kicked the ground twice".) The sign follows the bone's Z in case a
	# model export turns the bone roll.
	var turned := Basis(Vector3.RIGHT, pitch if world.basis.z.y >= 0.0 else -pitch)
	var new_basis := world.basis * turned
	var corner := Vector3(0.0, toe_length, -sole_depth) if pitch < 0.0 else Vector3(0.0, -heel_length, -sole_depth)
	var lift := maxf((world.basis * corner).y - (new_basis * corner).y, 0.0)
	var placed := Transform3D(new_basis, world.origin + Vector3.UP * lift)
	skeleton.set_bone_global_pose(bone, skeleton.global_transform.affine_inverse() * placed)
