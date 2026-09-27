class_name MechKneel
extends Node
## Press Ctrl to kneel: right knee on the ground, left foot forward. Press Ctrl again to stand.
## The mech cannot move, boost, or charge a jump while it kneels.

@export var mech: Mech
@export var input: MechInput
@export var landing_recovery: MechLandingRecovery
## How fast the mech goes down and comes up (1 / seconds). 0.5 = 2 s down, 2 s up.
@export var kneel_speed: float = 0.5

## 0 = standing, 1 = fully down.
var amount: float = 0.0
## True while the mech is down or on the way down or up.
var is_kneeling: bool = false

var _wants: bool = false


func _ready() -> void:
	# Run before the Mech so it reads this frame's state.
	process_physics_priority = -4


func _physics_process(delta: float) -> void:
	if input.crouch_pressed:
		_wants = not _wants
	if not mech.is_on_floor() or landing_recovery.is_recovering():
		_wants = false
	amount = move_toward(amount, 1.0 if _wants else 0.0, kneel_speed * delta)
	is_kneeling = _wants or amount > 0.05
