extends CanvasLayer
## Shows live movement values for testing. Phase 2 adds weight and part HP.

@export var mech: Mech

@onready var _info: Label = $Info
@onready var _energy_bar: ProgressBar = $EnergyBar


func _process(_delta: float) -> void:
	var speed := mech.get_horizontal_speed()
	var state := "GROUND" if mech.is_on_floor() else "AIR"
	if mech.is_boosting:
		state += " + BOOST"
	if mech.is_jetting:
		state += " + JETS"
	var energy := mech.energy
	_info.text = "Speed: %.1f m/s (%d km/h)\nHeight: %.1f m\nState: %s\nEnergy: %d / %d%s\nFPS: %d" % [
		speed, roundi(speed * 3.6), mech.global_position.y, state,
		roundi(energy.current), roundi(energy.capacity),
		"  (EMPTY)" if energy.is_depleted else "",
		Engine.get_frames_per_second(),
	]
	_energy_bar.value = energy.get_fraction() * 100.0
	_energy_bar.modulate = Color(1.0, 0.35, 0.3) if energy.is_depleted else Color.WHITE
