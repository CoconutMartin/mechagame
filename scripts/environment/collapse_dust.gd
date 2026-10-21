class_name CollapseDust
extends CPUParticles3D
## The big dust cloud of a building collapse (phase 5c, user choice 2026-10-19): large slow puffs roll
## out over the street from the impact and clear slowly. It plays once and frees itself. Same puff look
## as DustBurst (PixelSmoke).

## Footprint of the impact (m, x and z); the cloud starts over it and rolls out past it.
var footprint: Vector2 = Vector2(20.0, 20.0)


static func create(world: Node, point: Vector3, area: Vector2) -> CollapseDust:
	var dust := CollapseDust.new()
	dust.footprint = area
	world.add_child(dust)
	dust.global_position = point
	return dust


func _ready() -> void:
	name = "CollapseDust"
	one_shot = true
	explosiveness = 0.8
	amount = 64
	lifetime = 9.0
	local_coords = false
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(footprint.x * 0.5, 2.0, footprint.y * 0.5)
	direction = Vector3(1.0, 0.15, 0.0)
	spread = 180.0
	flatness = 0.85
	gravity = Vector3(0.0, 0.25, 0.0)
	initial_velocity_min = 4.0
	initial_velocity_max = 11.0
	damping_min = 1.2
	damping_max = 2.0
	var size := clampf(maxf(footprint.x, footprint.y) * 0.35, 6.0, 18.0)
	scale_amount_min = size * 0.6
	scale_amount_max = size
	DustBurst._shared_look()
	scale_amount_curve = DustBurst._curve
	color_ramp = DustBurst._ramp
	mesh = DustBurst._quad
	set_meta(&"opacity", 0.75)
	PixelSmoke.register(self)
	set_deferred(&"emitting", true)
	finished.connect(queue_free)
