extends SceneTree
## Part break time test (lag spike report 2026-10-18: one 269 ms frame when a War Hammer hit breaks a
## part). It breaks parts of the player mech (and of a second mech, with warm caches) with one 520 damage
## hit each, the War Hammer overhead strike, and prints the time of the MechHealth.damage call and of
## the next frame. Exits with code 1 when a damage call takes more than max_break_ms. Headless:
##   godot --headless --path . --script res://tools/godot/test_break_time.gd
## Headless has a dummy renderer: GPU shader and pipeline compiles are not in these numbers. With a
## window (Forward+), they are:
##   godot --path . --script res://tools/godot/test_break_time.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## The War Hammer overhead strike damage.
const HIT := 520.0
## Parts that break with no death, in this order (Torso R takes Arm R and Back R with it). The second
## mech is a new player mech (LoadoutSwitcher.rebuild): its breaks show the cost with warm caches.
const PARTS: Array[String] = ["Arm L", "Weapon R", "Leg L", "Back L", "Torso R"]
const SECOND_PARTS: Array[String] = ["Arm L", "Leg L"]

## Fail limit for one damage call that breaks a part, ms.
@export var max_break_ms: float = 10.0
## Frames between two breaks (the effects of the last break play and go).
@export var gap_frames: int = 120

var _failures: int = 0
var _worst: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(40)
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var player := switcher.mech
	print("player mech: %s" % player.scene_file_path)
	for key in PARTS:
		await _break(player, key, "first mech")
		await _frames(gap_frames)
	switcher.rebuild(switcher.current_loadout, player.global_transform)
	await _frames(40)
	for key in SECOND_PARTS:
		await _break(switcher.mech, key, "second mech")
		await _frames(gap_frames)
	print("worst break: %.2f ms (limit %.1f ms)" % [_worst, max_break_ms])
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


## One hit that breaks the part: the damage call time, and the time of the frame after it.
func _break(mech: Mech, key: String, label: String) -> void:
	var health := mech.health
	if not health.is_part_alive(key):
		print("skip %s %s: no such part or already broken" % [label, key])
		return
	health.hp[key] = minf(health.hp[key], HIT * 0.5)
	var start := Time.get_ticks_usec()
	health.damage(key, HIT, mech.global_position - mech.global_basis.z * 30.0)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	var frame_start := Time.get_ticks_usec()
	await process_frame
	var frame_ms := (Time.get_ticks_usec() - frame_start) / 1000.0
	_worst = maxf(_worst, ms)
	var ok := ms <= max_break_ms and not health.is_part_alive(key)
	print("%s %s %s: damage call %.2f ms, next frame %.2f ms" % ["ok  " if ok else "FAIL", label, key, ms, frame_ms])
	if not ok:
		_failures += 1
