class_name BreakWarmup
extends RefCounted
## Part break effects made once per game, out of sight, when the first mech is ready (lag spike fix
## 2026-10-18). The first explosion, sparks and smoke of a game built their materials then, and the
## renderer compiled their shaders in that frame (a War Hammer hit that broke a part: one frame of
## 269 ms on Forward+). This warm-up makes the same effects far below the level at load time, so the
## shaders are ready before the first hit. The materials stay (PartBreaker's preloaded scenes,
## PixelSmoke and DamageSmoke share theirs), so the shaders are not made again later.

## Where the warm-up effects play: far below the level, out of sight.
const PLACE := Vector3(0.0, -1000.0, 0.0)
## Seconds before the warm-up smoke goes (the explosion and sparks free themselves).
const SMOKE_TIME := 3.0

static var _done: bool = false


## Plays one explosion (with its sparks) and the solid and see-through smoke out of sight in level.
## Only the first call of the game does something.
static func run(level: Node) -> void:
	if _done or level == null or not level.is_inside_tree():
		return
	_done = true
	PartBreaker.explode_in(level, PLACE, 3.0)
	var holder := Node3D.new()
	holder.name = "BreakWarmup"
	level.add_child(holder)
	holder.global_position = PLACE
	DamageSmoke.create(holder, Vector3.ZERO, true)
	DamageSmoke.create(holder, Vector3.ZERO, false, 0.5)
	level.get_tree().create_timer(SMOKE_TIME).timeout.connect(holder.queue_free)
