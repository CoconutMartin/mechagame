class_name SkirtFollow
extends Node
## Turns a waist armor plate (skirt) with the thighs, so the thighs do not go through it.
## A front plate follows its hip when the leg swings forward.
## A rear plate follows the hip that swings back the most.

enum Placement { FRONT, REAR }

## The skirt pivot. It turns on its X axis. The plate hangs down from it.
@export var skirt: Node3D
## Hips to follow. A front plate uses one hip, a rear plate uses both.
@export var hips: Array[Node3D] = []
@export var placement: Placement = Placement.FRONT
## Skirt turn = hip turn x this value.
@export_range(0.0, 1.5) var follow: float = 0.8


func _ready() -> void:
	# After the leg animation.
	process_physics_priority = 11


func _physics_process(_delta: float) -> void:
	var angle := 0.0
	for hip in hips:
		if placement == Placement.FRONT:
			angle = maxf(angle, hip.rotation.x)
		else:
			angle = minf(angle, hip.rotation.x)
	skirt.rotation.x = angle * follow
