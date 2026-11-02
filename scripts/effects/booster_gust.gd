class_name BoosterGust
extends RefCounted
## The air a booster blows out as a gust of wind (user request 2026-11-02: "wind from boost pack should look like a
## gust of wind, not bubbles"). Thin, long, mostly transparent streaks of pale air that leave the outlet along its
## +Y axis, stay behind in the world and fade fast. Each streak is a particle that lies along its own motion and
## faces the camera (shaders/booster_gust.gdshader), so no round puff shows. BackPackOutlets makes one emitter per
## outlet with make().

const SHADER := preload("res://shaders/booster_gust.gdshader")


## Makes a streak emitter on an outlet (off until emitting is set). The values come from the owner's @export tuning.
## radius: the outlet's size (m), rate: streaks per second, speed: out of the outlet (m/s), spread_deg: cone angle,
## life: seconds a streak lasts, streak_length / streak_width: size of a streak (m), color: air tint and peak opacity.
static func make(outlet: Node3D, radius: float, rate: float, speed: float, spread_deg: float, life: float,
		streak_length: float, streak_width: float, color: Color) -> CPUParticles3D:
	var gust := CPUParticles3D.new()
	gust.name = "Gust"
	gust.emitting = false
	gust.local_coords = false
	gust.amount = maxi(int(ceil(rate * life)) + 2, 4)
	gust.lifetime = life
	gust.randomness = 0.6
	gust.direction = Vector3.UP
	gust.spread = spread_deg
	gust.gravity = Vector3.ZERO
	gust.initial_velocity_min = speed * 0.6
	gust.initial_velocity_max = speed * 1.3
	# The air slows down as it spreads: the streak stays behind the mech.
	gust.damping_min = speed * 0.9
	gust.damping_max = speed * 1.5
	gust.particle_flag_align_y = true
	gust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	gust.emission_ring_axis = Vector3.UP
	gust.emission_ring_height = 0.1
	gust.emission_ring_radius = radius * 1.3
	gust.emission_ring_inner_radius = radius * 0.2
	gust.scale_amount_min = 0.5
	gust.scale_amount_max = 1.2
	# A streak fades in fast and out slowly: opacity 0 -> 1 -> 0.
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.0)
	ramp.set_color(0, Color(color, 0.0))
	ramp.add_point(0.15, Color(color, color.a))
	ramp.set_color(1, Color(color, 0.0))
	gust.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"streak_length", streak_length)
	material.set_shader_parameter(&"streak_width", streak_width)
	quad.material = material
	gust.mesh = quad
	gust.add_to_group(BoosterPlume.SKIN_SKIP)
	outlet.add_child(gust)
	return gust
