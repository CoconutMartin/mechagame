class_name PulseArcWeb
extends ElectricArcs
## Lightning that jumps between the neighbor pellets of one pulse shot (Shotgun 2 and 3; user request 2026-11-02:
## "more electric looking"). PulseShotgunWeapon sets pellets and links. Each redraw lights a random share of the links,
## so the web flickers. It ends when its pellets are gone.

## Redraws per second.
@export var refresh_hz: float = 24.0
## Share of the links lit at each redraw.
@export var link_chance: float = 0.65
## Arc width seen from the camera (degrees), and the side offset as a share of the link length.
@export var width_deg: float = 0.32
@export var jag: float = 0.1
## Seconds after the shot before the web shows (the pellets are still in the muzzle).
@export var delay: float = 0.03
## Arc tint (multiplies the shader colors).
@export var tint: Color = Color(1.0, 1.0, 1.0)

var pellets: Array[Node3D] = []
## Pellet index pairs that can arc.
var links: Array[Vector2i] = []

var _age: float = 0.0
var _next_refresh: float = 0.0


func _process(delta: float) -> void:
	_age += delta
	var alive := false
	for pellet in pellets:
		if is_instance_valid(pellet):
			alive = true
			break
	if not alive:
		queue_free()
		return
	_next_refresh -= delta
	if _next_refresh > 0.0 or _age < delay:
		return
	_next_refresh = 1.0 / maxf(refresh_hz, 1.0)
	clear_arcs()
	var view := ElectricArcs.view_position(self)
	for link in links:
		if randf() >= link_chance:
			continue
		var a := pellets[link.x]
		var b := pellets[link.y]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var pa := a.global_position
		var pb := b.global_position
		var distance := maxf(view.distance_to((pa + pb) * 0.5), 1.0)
		var width := distance * tan(deg_to_rad(width_deg))
		add_bolt(pa, pb, width, pa.distance_to(pb) * jag, 8, tint, 0.12)
	commit()
