extends SceneTree
## Unit test of WeaponData.damage_factor (formula of "weapon_damage_falloff_implementation_spec.md";
## values: user choice 2026-10-16, MechWarrior 5 / MechWarrior Online ranges, Shotgun from the spec).
## Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_damage_falloff.gd
## Checks for the six weapons (data from data/weapons/*.tres): the configured S / E / M, the factor at
## 0, S - 1, S, (S + E) / 2, E, E + 1 and E + 1000 m, the spec formula on a 1 m grid from 0 to 2000 m,
## monotonic non-increasing, never below M, no NaN or infinity or negative values, and the max range
## (range_m). Then the invalid and missing configurations.

const TOLERANCE := 0.0005
## [file, S, E, M, max range]. auto_cannon_shoulder uses the Auto Cannon values.
const WEAPONS := [
	["shotgun", 12.0, 45.0, 0.20, 150.0], ["smg", 104.0, 208.0, 0.0, 208.0],
	["heavy_rifle", 620.0, 1240.0, 0.0, 1240.0], ["auto_cannon", 450.0, 900.0, 0.0, 900.0],
	["auto_cannon_shoulder", 450.0, 900.0, 0.0, 900.0], ["beam_rifle", 540.0, 1080.0, 0.0, 1080.0],
	["beam_sniper", 810.0, 1620.0, 0.0, 1620.0],
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	for entry: Array in WEAPONS:
		_test_weapon(entry[0], entry[1], entry[2], entry[3], entry[4])
	_test_invalid()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## The spec formula, section 3.
static func expected(distance: float, s: float, e: float, m: float) -> float:
	if distance <= s:
		return 1.0
	if distance >= e:
		return m
	return 1.0 - (distance - s) / (e - s) * (1.0 - m)


func _check(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + text)


func _test_weapon(file: String, s: float, e: float, m: float, max_range: float) -> void:
	var data := load("res://data/weapons/%s.tres" % file) as WeaponData
	_check(data != null, "%s loads" % file)
	if data == null:
		return
	_check(is_equal_approx(data.effective_range_m, s) and is_equal_approx(data.falloff_end_m, e)
			and is_equal_approx(data.falloff_min, m),
			"%s data S/E/M = %.1f/%.1f/%.2f (want %.1f/%.1f/%.2f)" % [file, data.effective_range_m,
			data.falloff_end_m, data.falloff_min, s, e, m])
	_check(is_equal_approx(data.range_m, max_range), "%s max range %.1f (want %.1f)" % [file, data.range_m, max_range])
	var cases := {0.0: 1.0, s - 1.0: 1.0, s: 1.0, (s + e) * 0.5: (1.0 + m) * 0.5, e: m, e + 1.0: m, e + 1000.0: m}
	var line := "%s:" % file
	for distance: float in cases:
		var got := data.damage_factor(distance)
		_check(absf(got - cases[distance]) < TOLERANCE, "%s at %.1f m: %.4f, want %.4f" % [file, distance, got, cases[distance]])
		line += "  %.1f m %.4f" % [distance, got]
	print(line)
	var last := INF
	for i in 2001:
		var distance := float(i)
		var got := data.damage_factor(distance)
		_check(absf(got - expected(distance, s, e, m)) < TOLERANCE, "%s formula at %d m: %.4f, want %.4f" % [file, i, got, expected(distance, s, e, m)])
		_check(got <= last + 1e-6, "%s not increasing at %d m" % [file, i])
		_check(got >= m - 1e-6, "%s not below M at %d m" % [file, i])
		_check(is_finite(got) and got >= 0.0, "%s finite and not negative at %d m" % [file, i])
		_check(is_finite(data.damage * got) and data.damage * got >= 0.0, "%s damage finite at %d m" % [file, i])
		last = got


func _test_invalid() -> void:
	var none := WeaponData.new()
	_check(is_equal_approx(none.damage_factor(500.0), 1.0), "no falloff configured: factor 1")
	var bad := WeaponData.new()
	bad.display_name = "Test bad falloff"
	bad.effective_range_m = 100.0
	bad.falloff_end_m = 100.0
	bad.falloff_min = 0.5
	print("(a warning about 'Test bad falloff' is expected next)")
	var got := bad.damage_factor(150.0)
	_check(is_equal_approx(got, 1.0) and is_finite(got), "E == S: factor 1 (got %.4f), no division by zero" % got)
	bad.falloff_end_m = 50.0
	_check(is_equal_approx(bad.damage_factor(150.0), 1.0), "E < S: factor 1")
	var odd := WeaponData.new()
	odd.effective_range_m = 10.0
	odd.falloff_end_m = 20.0
	odd.falloff_min = 0.5
	_check(is_equal_approx(odd.damage_factor(NAN), 1.0), "NaN distance: factor 1")
	_check(is_equal_approx(odd.damage_factor(-5.0), 1.0), "negative distance: factor 1")
	_check(is_equal_approx(odd.damage_factor(INF), 0.5), "infinite distance: factor M")
	var missiles := load("res://data/weapons/missile_pod_r.tres") as WeaponData
	_check(is_equal_approx(missiles.damage_factor(550.0), 1.0), "missile pod (no falloff data): factor 1")
