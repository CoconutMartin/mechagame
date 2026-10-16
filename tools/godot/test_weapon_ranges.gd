extends SceneTree
## Weapon range unit test (user choice 2026-10-16: MechWarrior Online ranges). Checks each weapon's
## optimal and max range in data/weapons/*.tres and WeaponData.damage_factor: 1 up to the optimal
## range, linear down to 0 at the max range, 0 beyond, never increasing, never NaN or negative.
## Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_weapon_ranges.gd

const TOLERANCE := 0.0005
## [file, MWO weapon, optimal, max]. A max-only weapon has optimal 0 (no falloff).
const WEAPONS := [
	["shotgun", "LB 10-X AC", 540.0, 1080.0], ["smg", "Machine Gun", 130.0, 260.0],
	["heavy_rifle", "AC/5", 620.0, 1240.0], ["auto_cannon", "AC/10", 450.0, 900.0],
	["auto_cannon_shoulder", "AC/10", 450.0, 900.0], ["beam_rifle", "Large Laser", 450.0, 900.0],
	["beam_sniper", "ER Large Laser", 675.0, 1350.0], ["missile_pod_r", "LRM", 0.0, 1000.0],
	["missile_pod_l", "LRM", 0.0, 1000.0],
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	for entry: Array in WEAPONS:
		_test_weapon(entry[0], entry[1], entry[2], entry[3])
	var none := WeaponData.new()
	_check(is_equal_approx(none.damage_factor(5000.0), 1.0), "no optimal range: factor 1")
	var odd := WeaponData.new()
	odd.effective_range_m = 100.0
	odd.range_m = 100.0
	_check(is_equal_approx(odd.damage_factor(150.0), 1.0), "optimal = max: factor 1, no division by zero")
	odd.range_m = 200.0
	_check(is_equal_approx(odd.damage_factor(NAN), 1.0), "NaN distance: factor 1")
	_check(is_equal_approx(odd.damage_factor(-5.0), 1.0), "negative distance: factor 1")
	_check(is_equal_approx(odd.damage_factor(INF), 0.0), "infinite distance: factor 0")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + text)


static func expected(distance: float, optimal: float, max_range: float) -> float:
	if optimal <= 0.0 or distance <= optimal:
		return 1.0
	return maxf(1.0 - (distance - optimal) / (max_range - optimal), 0.0)


func _test_weapon(file: String, mwo: String, optimal: float, max_range: float) -> void:
	var data := load("res://data/weapons/%s.tres" % file) as WeaponData
	_check(data != null, "%s loads" % file)
	if data == null:
		return
	_check(is_equal_approx(data.effective_range_m, optimal) and is_equal_approx(data.range_m, max_range),
			"%s (%s) optimal / max %.0f / %.0f, want %.0f / %.0f" % [file, mwo, data.effective_range_m, data.range_m, optimal, max_range])
	var line := "%s (MWO %s, %.0f / %.0f m):" % [file, mwo, data.effective_range_m, data.range_m]
	for distance in [0.0, optimal - 1.0, optimal, (optimal + max_range) * 0.5, max_range, max_range + 1.0]:
		if distance < 0.0:
			continue
		line += "  %.0f m %.3f" % [distance, data.damage_factor(distance)]
	print(line)
	var last := INF
	for i in 2001:
		var distance := float(i)
		var got := data.damage_factor(distance)
		_check(absf(got - expected(distance, optimal, max_range)) < TOLERANCE, "%s at %d m: %.4f, want %.4f" % [file, i, got, expected(distance, optimal, max_range)])
		_check(got <= last + 1e-6, "%s not increasing at %d m" % [file, i])
		_check(is_finite(got) and got >= 0.0, "%s finite and not negative at %d m" % [file, i])
		last = got
