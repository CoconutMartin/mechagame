class_name LegPart
extends PartData
## Legs: carry the weight and set the base speed and jump.

enum LegType { BIPED, REVERSE_JOINT, TANK, QUAD }

@export var leg_type: LegType = LegType.BIPED
## Weight the legs carry before the mech slows down a lot, in tons.
@export var load_capacity_t: float = 80.0
## Top walk speed with no load, in m/s. The weight formula lowers it.
@export var base_speed: float = 11.742
## Full jump jet height, in meters.
@export var jump_height: float = 9.0
## Leg turn speeds (A / D) before the weight factor, in degrees per second.
@export var turn_speed_deg: float = 77.4
@export var turn_speed_standing_deg: float = 38.7
## Forward lean of the upper body while walking, in degrees (0 = upright). Full at walk speed.
@export var walk_lean_deg: float = 0.0

## Waist socket: the place of the core's waist ball (the hip ball joint, the torso's turn point), in the pelvis bone's frame (m).
## The torso bone sits here whatever core is on the legs (user 2026-11-08: "The torso should be joined at the hip 'ball joint'").
## Zero: the torso keeps the core's own rig offset. Measured from the meshes (DESIGN "Waist ball joint").
@export var waist_socket: Vector3 = Vector3.ZERO

## The mech scene with these legs' rig: its leg lengths and clips (empty: the switcher's default scene). A path, because the scene's
## start loadout holds these legs and two resources cannot load each other.
@export_file("*.tscn") var mech_scene_path: String = ""
