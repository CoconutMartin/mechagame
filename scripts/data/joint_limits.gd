class_name JointLimits
extends Resource
## How far each mech joint can bend and twist away from its rest pose (user request 2026-10-15: the
## large hit clip bent and twisted the mech out of shape). Used on the Mixamo clip poses.
## Twist = turn about the bone's own axis (+Y); swing = every other bend.

## Bone name -> Vector2(largest swing, largest twist), in degrees. Bones not listed are free.
@export var limits: Dictionary[String, Vector2] = {}


## The local bone rotation, held inside this bone's limits (rest = the bone's rest rotation).
func clamp_rotation(bone: String, rest: Quaternion, rotation: Quaternion) -> Quaternion:
	if not limits.has(bone):
		return rotation
	var limit: Vector2 = limits[bone]
	var change := rest.inverse() * rotation
	if change.w < 0.0:
		change = -change
	var twist := Quaternion(0.0, change.y, 0.0, change.w).normalized()
	var swing := change * twist.inverse()
	return rest * _clamp_angle(swing, deg_to_rad(limit.x)) * _clamp_angle(twist, deg_to_rad(limit.y))


## The local bone rotation held inside limit (swing, twist; degrees) from rest.
static func clamp_with(rest: Quaternion, rotation: Quaternion, limit: Vector2) -> Quaternion:
	var change := rest.inverse() * rotation
	if change.w < 0.0:
		change = -change
	var twist := Quaternion(0.0, change.y, 0.0, change.w).normalized()
	var swing := change * twist.inverse()
	return rest * _clamp_angle(swing, deg_to_rad(limit.x)) * _clamp_angle(twist, deg_to_rad(limit.y))


static func _clamp_angle(turn: Quaternion, max_angle: float) -> Quaternion:
	var angle := turn.get_angle()
	if angle <= max_angle or angle < 0.0001:
		return turn
	return Quaternion.IDENTITY.slerp(turn, max_angle / angle)
