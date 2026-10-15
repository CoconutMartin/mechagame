class_name AirClipBody
extends RefCounted
## Puts a retargeted jump, fall or landing clip (AirClip) on the rigged mech's body (user request
## 2026-10-15). The clip gives the rotations of the pelvis, waist, head and legs. Its own place
## (hips travel and height: Mixamo falls 8 m in 0.3 s) is not used. Instead the pelvis goes where the
## feet stand: the soles of the two feet touch the floor height (plus a small lift in the air) and the
## middle of the feet stays where it is in the pose under the clip (where the mech stands).
## The pelvis keeps its yaw from the pose under it (hip turn). The arms are not taken from the clip
## (SkeletalDodgeAnimation.ARM_BONES): they keep holding the weapon.
## After all layers, keep_feet_up() lifts the pelvis if a sole is under the floor.

const PELVIS := &"pelvis"
const LEG_BONES := [["thigh_L", "shin_L", "foot_L"], ["thigh_R", "shin_R", "foot_R"]]
## Foot meshes: the skeleton meshes with a point lower than this at rest (m, skeleton space).
const SOLE_SEARCH_HEIGHT := 0.2

var skeleton: Skeleton3D
var pelvis: int = -1
## Each leg: thigh, shin, foot (bone indices), local rest origins, sole points in the foot's bone space.
var _legs: Array[Dictionary] = []
## Animation -> {bone index: track} for the rotation tracks, plus the pelvis position track.
var _tracks := {}
## Animation -> the pelvis position track.
var _position_tracks := {}
## Sole height of the clip at its touchdown (clip lift), by animation.
var _ground := {}
## Hip height above the soles when standing at rest (m).
var stand_height: float = 6.0


func setup(target: Skeleton3D) -> void:
	skeleton = target
	pelvis = skeleton.find_bone(PELVIS)
	for names: Array in LEG_BONES:
		var leg := {
			"thigh": skeleton.find_bone(names[0]), "shin": skeleton.find_bone(names[1]),
			"foot": skeleton.find_bone(names[2]),
		}
		for key: String in ["thigh", "shin", "foot"]:
			leg[key + "_origin"] = skeleton.get_bone_rest(leg[key]).origin
		leg["soles"] = _sole_points(leg.foot, names[2].ends_with("_L"))
		_legs.append(leg)
	var rest_sole := INF
	var chain := skeleton.get_bone_global_rest(pelvis)
	for leg: Dictionary in _legs:
		var foot_rest := skeleton.get_bone_global_rest(leg.foot)
		for point: Vector3 in leg.soles:
			rest_sole = minf(rest_sole, (foot_rest * point).y)
	stand_height = chain.origin.y - rest_sole


## The four lowest corners of the foot meshes (those below SOLE_SEARCH_HEIGHT on this side) in the foot's
## bone space.
func _sole_points(foot: int, left: bool) -> PackedVector3Array:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for node in skeleton.get_children():
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var box := mesh.get_aabb()
		var corners: Array[Vector3] = []
		var bottom := INF
		for i in 8:
			var point := mesh.transform * box.get_endpoint(i)
			corners.append(point)
			bottom = minf(bottom, point.y)
		var middle := mesh.transform * box.get_center()
		if bottom > SOLE_SEARCH_HEIGHT or (middle.x > 0.0) != left:
			continue
		for point in corners:
			low = low.min(point)
			high = high.max(point)
	var inverse := skeleton.get_bone_global_rest(foot).affine_inverse()
	var points := PackedVector3Array()
	for x in [low.x, high.x]:
		for z in [low.z, high.z]:
			points.append(inverse * Vector3(x, low.y, z))
	return points


## Rotations of the clip at time (seconds), by bone index (no arm bones).
func sample(clip: AirClip, time: float) -> Dictionary:
	var animation := clip.animation
	if not _tracks.has(animation):
		_cache(animation)
	var out := {}
	var tracks: Dictionary = _tracks[animation]
	for bone: int in tracks:
		out[bone] = animation.rotation_track_interpolate(tracks[bone], time)
	return out


func _cache(animation: Animation) -> void:
	var tracks := {}
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(String(animation.track_get_path(track).get_concatenated_subnames()))
		if bone < 0 or skeleton.get_bone_name(bone) in SkeletalDodgeAnimation.ARM_BONES:
			continue
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			tracks[bone] = track
		elif bone == pelvis:
			_position_tracks[animation] = track
	_tracks[animation] = tracks


## Soles and ankles of a pose: the pelvis at the origin of the skeleton (x, z) and the height 0.
## Returns {low (lowest sole y), ankles (skeleton-space origins)}; basis is the pelvis basis.
func _feet(rotations: Dictionary, pelvis_basis: Basis) -> Dictionary:
	var pelvis_pose := Transform3D(pelvis_basis, Vector3.ZERO)
	var low := INF
	var ankles: Array[Vector3] = []
	for leg: Dictionary in _legs:
		var thigh := pelvis_pose * Transform3D(Basis(rotations[leg.thigh] as Quaternion), leg.thigh_origin)
		var shin := thigh * Transform3D(Basis(rotations[leg.shin] as Quaternion), leg.shin_origin)
		var foot := shin * Transform3D(Basis(rotations[leg.foot] as Quaternion), leg.foot_origin)
		ankles.append(foot.origin)
		for point: Vector3 in leg.soles:
			low = minf(low, (foot * point).y)
	return {"low": low, "ankles": ankles}


## Blends the clip pose at time into the skeleton at weight (0 to 1). anchor is the place (skeleton
## space) of the middle of the feet, yaw the pelvis turn about the up axis (radians, from the pose
## under the clip), sole_level the height of the lowest sole. Returns the crouch depth (0 = stand,
## 1 = deep: the hips half the standing height above the soles) of the clip pose.
func apply(clip: AirClip, time: float, weight: float, anchor: Vector3, yaw: float, sole_level: float) -> float:
	var rotations := sample(clip, time)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(pelvis))
	var turn := Basis(Vector3.UP, yaw)
	var local_pelvis := Quaternion(parent.basis.inverse() * turn * parent.basis * Basis(rotations[pelvis] as Quaternion))
	rotations[pelvis] = local_pelvis
	var pelvis_basis := parent.basis * Basis(local_pelvis)
	var feet := _feet(rotations, pelvis_basis)
	var ankles: Array[Vector3] = feet.ankles
	var middle := (ankles[0] + ankles[1]) * 0.5
	var origin := Vector3(anchor.x - middle.x, sole_level - (feet.low as float), anchor.z - middle.z)
	var target := parent.affine_inverse() * origin
	for bone: int in rotations:
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(rotations[bone] as Quaternion, weight))
	skeleton.set_bone_pose_position(pelvis, skeleton.get_bone_pose_position(pelvis).lerp(target, weight))
	var height := -(feet.low as float)
	return clampf((stand_height - height) / (stand_height * 0.5), 0.0, 1.0)


## Sole height of the clip's own pose at time over its sole height at its touchdown (m): how high the
## clip's feet are above the ground. Needs the pelvis position track.
func clip_height(clip: AirClip, time: float) -> float:
	var animation := clip.animation
	var rotations := sample(clip, time)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(pelvis))
	var feet := _feet(rotations, parent.basis * Basis(rotations[pelvis] as Quaternion))
	var y := _clip_sole_y(animation, time, feet.low)
	if not _ground.has(animation):
		var at := clip.contact_time
		var r := sample(clip, at)
		var f := _feet(r, parent.basis * Basis(r[pelvis] as Quaternion))
		_ground[animation] = _clip_sole_y(animation, at, f.low)
	return maxf(y - (_ground[animation] as float), 0.0)


func _clip_sole_y(animation: Animation, time: float, low: float) -> float:
	if not _position_tracks.has(animation):
		return low
	return low + (animation.position_track_interpolate(_position_tracks[animation], time) as Vector3).y


## Lifts the pelvis when a sole is under floor_height (skeleton space), after all layers. Returns the
## lift in meters.
func keep_feet_up(floor_height: float) -> float:
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(pelvis))
	var pelvis_pose := parent * Transform3D(Basis(skeleton.get_bone_pose_rotation(pelvis)), skeleton.get_bone_pose_position(pelvis))
	var rotations := {}
	for leg: Dictionary in _legs:
		for key: String in ["thigh", "shin", "foot"]:
			rotations[leg[key]] = skeleton.get_bone_pose_rotation(leg[key])
	var feet := _feet(rotations, pelvis_pose.basis)
	var low := (feet.low as float) + pelvis_pose.origin.y
	if low >= floor_height:
		return 0.0
	var lift := floor_height - low
	var raised := parent.affine_inverse() * (pelvis_pose.origin + Vector3.UP * lift)
	skeleton.set_bone_pose_position(pelvis, raised)
	return lift
