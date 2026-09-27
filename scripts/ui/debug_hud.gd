extends CanvasLayer
## Shows live movement values for testing. Phase 2 adds weight and part HP.

@export var mech: Mech
@export var mech_aim: MechAim

@onready var _info: Label = $Info
@onready var _energy_bar: ProgressBar = $EnergyBar


func _ready() -> void:
	($AimReticle as AimReticle).mech_aim = mech_aim


func _process(_delta: float) -> void:
	var speed := mech.get_horizontal_speed()
	var state := "GROUND" if mech.is_on_floor() else "AIR"
	if mech.is_boosting:
		state += " + BOOST"
	var charge := mech.jump_charge
	if charge.is_charging:
		state += "\nJump charge: %d%% (%.1f m)" % [roundi(charge.charge * 100.0), charge.charge * charge.full_height]
	if mech.is_exiting_boost:
		state += " + BOOST EXIT"
	var recovery := mech.landing_recovery
	if recovery.is_recovering():
		state += "\nLanding recovery: %.1f s" % recovery.time_left
	elif not mech.is_boost_ready():
		state += "\nBoost ready in %d steps" % mech.get_walk_steps_left()
	var energy := mech.energy
	_info.text = "Speed: %.1f m/s (%d km/h)\nHeight: %.1f m\nWeight: %d t\nState: %s\nEnergy: %d / %d%s\nFPS: %d" % [
		speed, roundi(speed * 3.6), mech.global_position.y, roundi(mech.mass_tons), state,
		roundi(energy.current), roundi(energy.capacity),
		"  (EMPTY)" if energy.is_depleted else "",
		Engine.get_frames_per_second(),
	]
	_energy_bar.value = energy.get_fraction() * 100.0
	_energy_bar.modulate = Color(1.0, 0.35, 0.3) if energy.is_depleted else Color.WHITE
