extends SceneTree
## Unit test of WeaponData.damage_factor against "weapon_damage_falloff_implementation_spec.md"
## (2026-10-16). Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_damage_falloff.gd
## Checks for the six weapons (data from data/weapons/*.tres): the configured S / E / M, the factor at
## 0, S - 1, S, (S + E) / 2, E, E + 1 and 1000 m, the spec formula on a 1 m grid from 0 to 300 m,
## monotonic non-increasing, never below M, no NaN or infinity or negative values. Then the invalid
## and missing configurations. The spec's reference table (section 5) is compared too: cells that do not
## match the spec formula (section 3) are listed as notes, not failures.

const TOLERANCE := 0.0005
## [file, S, E, M] from the spec, section 2. auto_cannon_shoulder uses the Autocannon values.
const WEAPONS := [
	["shotgun", 12.0, 45.0, 0.20], ["smg", 30.0, 90.0, 0.35], ["heavy_rifle", 70.0, 150.0, 0.60],
	["auto_cannon", 55.0, 130.0, 0.50], ["auto_cannon_shoulder", 55.0, 130.0, 0.50],
	["beam_rifle", 100.0, 200.0, 0.70], ["beam_sniper", 160.0, 250.0, 0.85],
]
## Spec section 5 (percent), by weapon file, for 0, 25, 50 ... 250 m.
const SPEC_TABLE := {
	"shotgun": [100, 60.6, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	"smg": [100, 100, 70.0, 43.8, 35, 35, 35, 35, 35, 35, 35],
	"heavy_rifle": [100, 100, 100, 93.8, 81.3, 66.3, 60, 60, 60, 60, 60],
	"auto_cannon": [100, 100, 100, 86.7, 70.0, 53.3, 50, 50, 50, 50, 50],
	"beam_rifle": [100, 100, 100, 100, 100, 91.3, 82.5, 73.8, 70, 70, 70],
	"beam_sniper": [100, 100, 100, 100, 100, 100, 100, 95.8, 92.2, 88.3, 85],
}

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	for entry: Array in WEAPONS:
		_test_weapon(entry[0], entry[1], entry[2], entry[3])
	_test_invalid()
	_compare_spec_table()
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


func _test_weapon(file: String, s: float, e: float, m: float) -> void:
	var data := load("res://data/weapons/%s.tres" % file) as WeaponData
	_check(data != null, "%s loads" % file)
	if data == null:
		return
	_check(is_equal_approx(data.effective_range_m, s) and is_equal_approx(data.falloff_end_m, e)
			and is_equal_approx(data.falloff_min, m),
			"%s data S/E/M = %.1f/%.1f/%.2f (want %.1f/%.1f/%.2f)" % [file, data.effective_range_m,
			data.falloff_end_m, data.falloff_min, s, e, m])
	var cases := {0.0: 1.0, s - 1.0: 1.0, s: 1.0, (s + e) * 0.5: (1.0 + m) * 0.5, e: m, e + 1.0: m, 1000.0: m}
	var line := "%s:" % file
	for distance: float in cases:
		var got := data.damage_factor(distance)
		_check(absf(got - cases[distance]) < TOLERANCE, "%s at %.1f m: %.4f, want %.4f" % [file, distance, got, cases[distance]])
		line += "  %.1f m %.4f" % [distance, got]
	print(line)
	var last := INF
	for i in 301:
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


func _compare_spec_table() -> void:
	var notes := 0
	for entry: Array in WEAPONS:
		var file: String = entry[0]
		if not SPEC_TABLE.has(file):
			continue
		var row: Array = SPEC_TABLE[file]
		for i in row.size():
			var distance := 25.0 * i
			var formula := expected(distance, entry[1], entry[2], entry[3]) * 100.0
			if absf(formula - float(row[i])) > 0.06:
				notes += 1
				print("NOTE: spec table %s at %d m says %.1f%%, the spec formula gives %.1f%%" % [file, distance, row[i], formula])
	print("NOTE: %d spec table cells differ from the spec formula (the code follows the formula)" % notes)
