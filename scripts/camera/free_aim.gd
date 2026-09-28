class_name FreeAim
extends Node
## Free aim with a dead zone (like the arm aim in ARMA or MechWarrior).
## The mech aim (blue ring) moves 1:1 with the mouse inside a box around the camera crosshair.
## Only the mouse movement that pushes past the box edge turns the camera.
## Each shot kicks the mech aim up and a little to the side (muzzle climb). The camera does not
## move. The player pulls the aim back onto the target. There is no automatic return.

## Half width of the box (left and right of the crosshair), in degrees.
@export var box_half_yaw_deg: float = 3.0
## Half height of the box (above and below the crosshair), in degrees.
@export var box_half_pitch_deg: float = 2.0
## Muzzle climb per shot, in degrees.
@export var recoil_up_deg: float = 1.8
## Largest random side kick per shot, in degrees.
@export var recoil_side_deg: float = 0.8

## Mech aim offset from the camera crosshair, in degrees: x = yaw (positive = left), y = pitch
## (positive = up).
var offset: Vector2 = Vector2.ZERO


## Moves the mech aim by a mouse movement (degrees, same signs as offset).
## Returns the part that went past the box edge. The camera turns by that part.
func take_motion(motion: Vector2) -> Vector2:
	var wanted := offset + motion
	offset = _clamp_to_box(wanted)
	return wanted - offset


## Recoil kick after a shot: up, plus a random side kick. Stays inside the box.
func kick() -> void:
	offset = _clamp_to_box(offset + Vector2(randf_range(-recoil_side_deg, recoil_side_deg), recoil_up_deg))


func _clamp_to_box(value: Vector2) -> Vector2:
	return Vector2(clampf(value.x, -box_half_yaw_deg, box_half_yaw_deg),
			clampf(value.y, -box_half_pitch_deg, box_half_pitch_deg))
