class_name CameraAds
extends Node
## Aim down sight: while the aim key is held, the camera zooms in and the mouse slows down.

@export var input: MechInput
@export var camera: Camera3D
@export var spring_arm: SpringArm3D
@export var rig: MechCameraRig
## Camera field of view while aiming, in degrees.
@export var aim_fov: float = 35.0
## Camera distance while aiming, in meters.
@export var aim_spring_length: float = 6.0
## Mouse sensitivity multiplier while aiming.
@export var aim_sensitivity_scale: float = 0.5
## How fast the zoom changes (1 / seconds).
@export var zoom_speed: float = 5.0

var _amount: float = 0.0
var _normal_fov: float
var _normal_spring_length: float


func _ready() -> void:
	_normal_fov = camera.fov
	_normal_spring_length = spring_arm.spring_length


func _process(delta: float) -> void:
	_amount = move_toward(_amount, 1.0 if input.aim_held else 0.0, zoom_speed * delta)
	var t := smoothstep(0.0, 1.0, _amount)
	camera.fov = lerpf(_normal_fov, aim_fov, t)
	spring_arm.spring_length = lerpf(_normal_spring_length, aim_spring_length, t)
	rig.sensitivity_scale = lerpf(1.0, aim_sensitivity_scale, t)
