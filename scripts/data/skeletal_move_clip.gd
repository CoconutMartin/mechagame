class_name SkeletalMoveClip
extends Resource
## One start or stop animation of a rigged mech (run start, run stop, Akira slide) and the body speed
## made for it in Blender. While the clip plays, SkeletalMoves moves the mech at that speed, so the
## planted feet stay on the ground. Written by tools/mech_gen/new_mech_moves.py.

## Animation name in the model's AnimationPlayer.
@export var animation: StringName
## Frames per second of the animation and of body_speeds.
@export var fps: float = 30.0
## Run speed the clip was made for (m/s). The clip plays at mech speed / this value.
@export var made_for_speed: float = 14.16
## Body speed (m/s, at made_for_speed) on each frame. The mech moves at this speed x the play rate.
@export var body_speeds: PackedFloat32Array = PackedFloat32Array()
## Frames where a foot lands (camera shake).
@export var footstep_frames: PackedFloat32Array = PackedFloat32Array()
## Run stops: stride phase of the run where frame 0 of the clip is (0 = left foot lands, 0.5 = right
## foot lands; -1 = not a run stop). The clip can start up to start_window frames late, from the same place.
@export var start_phase: float = -1.0
## Run stops: how many frames into the clip it can still start (its first frames are still the run).
@export var start_window: float = 0.0
## From this frame a move key ends the clip and the mech walks again (-1 = never).
@export var cancel_frame: float = -1.0
## Seconds to blend the clip in over the walk and run cycles.
@export var blend_in: float = 0.15
## Seconds to blend back to the walk and run cycles after the clip.
@export var blend_out: float = 0.25
## True: the clip ends on the first frame of the run cycle (run start), so the run carries on from it.
@export var ends_in_run: bool = false
## True: the hips keep their turn while the clip plays (stops go the way the mech was moving).
@export var hold_hips: bool = true


## Length in frames.
func get_frame_count() -> float:
	return float(body_speeds.size() - 1)


## Body speed (m/s at made_for_speed) at a frame, between the stored frames.
func get_body_speed(frame: float) -> float:
	if body_speeds.is_empty():
		return 0.0
	var last := body_speeds.size() - 1
	var f := clampf(frame, 0.0, float(last))
	var i := mini(int(f), last - 1) if last > 0 else 0
	if last == 0:
		return body_speeds[0]
	return lerpf(body_speeds[i], body_speeds[i + 1], f - i)
