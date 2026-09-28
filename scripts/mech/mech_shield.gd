class_name MechShield
extends Node
## The shield on the left arm. Hold the left arm key (LMB) to lift it.
## While it is up the mech moves slower. A bigger shield gives a lower top speed:
## top speed = reference_speed x reference_area / area. ShieldPose moves the arm.

@export var input: MechInput
## Front area of the shield in square meters. Set from the shield model size.
@export var area_m2: float = 13.6
## Shield area that gives reference_speed.
@export var reference_area_m2: float = 13.6
## Top move speed (m/s) with a shield of reference_area_m2 fully up.
@export var reference_speed: float = 6.0
## Top speed limits (m/s) for very big or very small shields.
@export var min_speed: float = 2.0
@export var max_speed: float = 9.1
## How fast the shield comes up (1 / seconds). 2 = 0.5 s.
@export var raise_speed: float = 2.0
## How fast the shield goes down (1 / seconds).
@export var lower_speed: float = 3.0

## False when the loadout has no shield (WeaponController sets it). LMB does nothing then.
var enabled: bool = true
## 0 = shield down, 1 = shield up.
var amount: float = 0.0


func _ready() -> void:
	# Before the Mech (0), so the speed limit is ready.
	process_physics_priority = -3


func _physics_process(delta: float) -> void:
	var held := enabled and input.shield_held
	var speed := raise_speed if held else lower_speed
	amount = move_toward(amount, 1.0 if held else 0.0, speed * delta)


## Top move speed (m/s) with the shield fully up.
func get_speed_limit() -> float:
	return clampf(reference_speed * reference_area_m2 / maxf(area_m2, 0.1), min_speed, max_speed)
