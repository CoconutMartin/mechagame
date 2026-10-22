extends SceneTree
## Stagger meter unit test (MechStability; user choice 2026-10-16: the arcade stagger spec "B" with the
## crouch brace). Checks buildup, the decay delay and rate, one stagger at the threshold, the reset,
## the protection window (points ignored, not kept), the weight class and brace scales, the per-shot
## caps (shotgun pellets, missile volley), the single-shot knock-down and the window, frame-rate independence, bad input,
## and the stagger values and fire cooldowns in data/weapons. Exits with code 1 on any failure.
##   godot --headless --path . --script res://tools/godot/test_stability.gd

const TOLERANCE := 0.001
## [file, stagger points, cap per shot, finisher, seconds between shots (0 = not checked)].
const WEAPONS := [
	["shotgun", 4.0, 20.0, 0.0, 2.25], ["smg", 2.7, 12.0, 0.0, 0.33], ["heavy_rifle", 18.0, 0.0, 0.0, 3.0],
	["auto_cannon", 34.0, 0.0, 0.0, 4.0], ["auto_cannon_shoulder", 35.0, 0.0, 0.0, 5.0],
	["beam_rifle", 102.0, 102.0, 0.0, 4.0], ["beam_sniper", 32.0, 0.0, 0.0, 6.0],
	["missile_pod_l", 10.0, 30.0, 0.0, 1.0], ["missile_pod_r", 10.0, 30.0, 0.0, 1.0],
	["fist", 15.0, 0.0, 25.0, 0.0], ["hammer", 45.0, 0.0, 0.0, 0.0], ["pile_bunker", 30.0, 0.0, 0.0, 6.0],
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_buildup_and_threshold()
	_test_decay()
	_test_protection()
	_test_scales()
	_test_caps()
	_test_knock_down()
	_test_frame_rate()
	_test_bad_input()
	_test_data()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + text)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < TOLERANCE


## A meter with no mech (medium scale, no brace) and no knock-down unless asked.
func _meter(knock: bool = false) -> MechStability:
	var meter := MechStability.new()
	if not knock:
		meter.knock_points = 0.0
	return meter


func _test_buildup_and_threshold() -> void:
	var meter := _meter()
	var staggers := [0]
	meter.staggered.connect(func(_from: Vector3) -> void: staggers[0] += 1)
	meter.add_hit(18.0)
	_check(_near(meter.value, 18.0), "heavy rifle hit adds 18 (got %.2f)" % meter.value)
	for i in 4:
		meter.add_hit(18.0)
	_check(_near(meter.value, 90.0) and staggers[0] == 0, "5 rifle hits = 90, no stagger (got %.2f, %d)" % [meter.value, staggers[0]])
	meter.add_hit(10.0)
	_check(staggers[0] == 1, "exactly 100 staggers once (got %d)" % staggers[0])
	_check(_near(meter.value, 0.0), "the meter is 0 after a stagger (got %.2f)" % meter.value)


func _test_decay() -> void:
	var meter := _meter()
	meter.add_hit(50.0)
	meter.advance(0.99)
	_check(_near(meter.value, 50.0), "no decay before 1.0 s (got %.3f)" % meter.value)
	meter.advance(0.01)
	_check(_near(meter.value, 50.0), "no decay at exactly 1.0 s (got %.3f)" % meter.value)
	meter.advance(1.0)
	_check(_near(meter.value, 32.0), "18 per second after the delay (got %.3f)" % meter.value)
	meter.add_hit(10.0)
	meter.advance(0.5)
	_check(_near(meter.value, 42.0), "a new hit restarts the delay (got %.3f)" % meter.value)
	meter.advance(10.0)
	_check(_near(meter.value, 0.0), "the meter stops at 0 (got %.3f)" % meter.value)


func _test_protection() -> void:
	var meter := _meter()
	var staggers := [0]
	meter.staggered.connect(func(_from: Vector3) -> void: staggers[0] += 1)
	meter.add_hit(100.0)
	_check(staggers[0] == 1 and meter.is_protected(), "stagger starts the protection")
	meter.add_hit(100.0)
	meter.add_hit(100.0)
	_check(staggers[0] == 1 and _near(meter.value, 0.0), "points in the protection are ignored (staggers %d, meter %.2f)" % [staggers[0], meter.value])
	meter.advance(1.0)
	_check(not meter.is_protected() and _near(meter.value, 0.0), "after 1 s: no protection, nothing stored (meter %.2f)" % meter.value)
	meter.add_hit(100.0)
	_check(staggers[0] == 2, "a stagger again after the protection (got %d)" % staggers[0])


func _test_scales() -> void:
	for entry: Array in [[40.0, 1.25, "light"], [58.5, 1.0, "medium"], [80.0, 0.65, "heavy"]]:
		var mech := Mech.new()
		mech.stats = MechStats.new()
		mech.stats.total_weight_t = entry[0]
		var meter := _meter()
		meter.mech = mech
		meter.add_hit(28.0)
		_check(_near(meter.value, 28.0 * entry[1]), "%s mech: auto cannon 28 x %.2f = %.2f (got %.2f)" % [entry[2], entry[1], 28.0 * entry[1], meter.value])
		var kneel := MechKneel.new()
		kneel.is_kneeling = true
		mech.kneel = kneel
		var braced := _meter()
		braced.mech = mech
		braced.add_hit(28.0)
		_check(_near(braced.value, 28.0 * entry[1] * 0.75), "%s mech kneeling: x 0.75 more (got %.2f)" % [entry[2], braced.value])
		kneel.free()
		mech.free()


func _test_caps() -> void:
	var meter := _meter()
	var shot := MechStability.new_shot_id()
	for pellet in 8:
		meter.add_hit(4.0, shot, 20.0)
	_check(_near(meter.value, 20.0), "8 shotgun pellets of one blast: capped at 20 (got %.2f)" % meter.value)
	meter.add_hit(4.0, MechStability.new_shot_id(), 20.0)
	_check(_near(meter.value, 24.0), "a pellet of the next blast counts again (got %.2f)" % meter.value)
	var volley := _meter()
	var flinches: Array = []
	volley.hit_taken.connect(func(points: float, _from: Vector3) -> void: flinches.append(points))
	var id := MechStability.new_shot_id()
	for missile in 4:
		volley.add_hit(10.0, id, 30.0)
		volley.advance(0.25)
	_check(_near(volley.value, 30.0), "4 missiles of one volley: capped at 30 (got %.2f)" % volley.value)
	_check(flinches.size() == 3, "the capped 4th missile gives no flinch event (events %d)" % flinches.size())


func _test_knock_down() -> void:
	var meter := _meter(true)
	var knocks := [0]
	var staggers := [0]
	meter.knocked_down.connect(func(_from: Vector3) -> void: knocks[0] += 1)
	meter.staggered.connect(func(_from: Vector3) -> void: staggers[0] += 1)
	meter.add_hit(45.0)
	_check(knocks[0] == 1 and staggers[0] == 0, "War Hammer 45: knock-down (knocks %d)" % knocks[0])
	meter.advance(1.1)
	meter.add_hit(30.0)
	_check(knocks[0] == 1, "Pile Bunker with no power (30): no knock-down")
	meter.advance(2.0)
	var second := _meter(true)
	second.knocked_down.connect(func(_from: Vector3) -> void: knocks[0] += 1)
	second.add_hit(30.0, 11, 30.0)
	second.advance(0.1)
	second.add_hit(30.0, 12, 30.0)
	_check(knocks[0] == 1, "two missile volleys within 0.3 s (60): no knock-down, one shot only (knocks %d)" % knocks[0])
	var twin := _meter(true)
	twin.knocked_down.connect(func(_from: Vector3) -> void: knocks[0] += 1)
	twin.add_hit(28.0)
	twin.add_hit(28.0)
	_check(knocks[0] == 1, "two auto cannon hits at once (56): no knock-down (knocks %d)" % knocks[0])
	var bunker := _meter(true)
	bunker.knocked_down.connect(func(_from: Vector3) -> void: knocks[0] += 1)
	var bunker_id := MechStability.new_shot_id()
	bunker.add_hit(30.0, bunker_id, 60.0)
	bunker.add_hit(30.0, bunker_id, 60.0)
	_check(knocks[0] == 2, "one shot of 60 in two parts: knock-down (knocks %d)" % knocks[0])
	var window := _meter(true)
	window.single_shot_knock = false
	window.knocked_down.connect(func(_from: Vector3) -> void: knocks[0] += 1)
	window.add_hit(28.0)
	window.advance(0.1)
	window.add_hit(28.0)
	_check(knocks[0] == 3, "single_shot_knock off: two hits within 0.3 s knock down (knocks %d)" % knocks[0])
	var slow := _meter(true)
	slow.single_shot_knock = false
	slow.knocked_down.connect(func(_from: Vector3) -> void: knocks[0] += 1)
	slow.add_hit(28.0)
	slow.advance(0.5)
	slow.add_hit(28.0)
	_check(knocks[0] == 3, "single_shot_knock off: two hits 0.5 s apart: no knock-down")


## The same hits and time give the same meter at 30, 60 and 144 frames per second.
func _test_frame_rate() -> void:
	var results: Array = []
	for fps in [30.0, 60.0, 144.0]:
		var meter := _meter()
		meter.add_hit(60.0)
		var steps := int(round(2.5 * fps))
		for i in steps:
			meter.advance(1.0 / fps)
		results.append(meter.value)
	_check(_near(results[0], 33.0) and _near(results[1], 33.0) and _near(results[2], 33.0),
			"frame rate independent: 60 - 18 x 1.5 = 33 at 30/60/144 fps (got %s)" % [results])


func _test_bad_input() -> void:
	var meter := _meter()
	meter.add_hit(NAN)
	meter.add_hit(-20.0)
	meter.add_hit(INF)
	meter.advance(NAN)
	meter.advance(-1.0)
	_check(_near(meter.value, 0.0) and is_finite(meter.value), "NaN, negative and infinite input change nothing (got %s)" % meter.value)
	var zero := _meter()
	zero.threshold = 0.0
	zero.add_hit(5.0)
	_check(is_finite(zero.get_fraction()), "threshold 0: the fraction stays finite")


func _test_data() -> void:
	for entry: Array in WEAPONS:
		var data := load("res://data/weapons/%s.tres" % entry[0]) as WeaponData
		_check(data != null, "%s loads" % entry[0])
		if data == null:
			continue
		_check(_near(data.stagger_points, entry[1]) and _near(data.stagger_cap_per_shot, entry[2])
				and _near(data.stagger_finisher_points, entry[3]),
				"%s stagger %.0f / cap %.0f / finisher %.0f (want %.0f / %.0f / %.0f)" % [entry[0], data.stagger_points,
				data.stagger_cap_per_shot, data.stagger_finisher_points, entry[1], entry[2], entry[3]])
		if entry[4] > 0.0:
			var gap := 1.0 / data.fire_rate
			_check(absf(gap - entry[4]) < 0.01, "%s: %.2f s between shots (want %.2f)" % [entry[0], gap, entry[4]])
