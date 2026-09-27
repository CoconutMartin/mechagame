class_name MechKneel
extends Node
## Hold Ctrl to kneel: right knee on the ground, left foot forward.
## The mech cannot move, boost, or charge a jump while it kneels.

@export var mech: Mech
@export var input: MechInput
@export var landing_recovery: MechLandingRecovery
## How fast the mech goes down and comes up (1 / seconds).
@export var kneel_speed: float = 2.5

## 0 = standing, 1 = fully down.
var amount: float = 0.0
## True while the mech is down or on the way down or up.
var is_kneeling: bool = false


func _ready() -> void:
	# Run before the Mech so it reads this frame's state.
	process_physics_priority = -4


func _physics_process(delta: float) -> void:
	var wants := input.crouch_held and mech.is_on_floor() and not landing_recovery.is_recovering()
	amount = move_toward(amount, 1.0 if wants else 0.0, kneel_speed * delta)
	is_kneeling = wants or amount > 0.05
