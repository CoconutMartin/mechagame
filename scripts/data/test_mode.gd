class_name TestMode
extends Resource
## Play-test switches (user request 2026-10-24: "remove energy consumption, scan cool down for now
## (testing)"). The settings file is data/test/test_mode.tres. Set both off to get the normal game back.

const PATH := "res://data/test/test_mode.tres"

## Boost, dodge and every other energy use cost nothing.
@export var free_energy: bool = true
## The pulse scan has no cool down and no use limit.
@export var free_scan: bool = true

static var _settings: TestMode


## The loaded settings (defaults when the file is missing).
static func settings() -> TestMode:
	if _settings == null:
		_settings = load(PATH) as TestMode if ResourceLoader.exists(PATH) else TestMode.new()
	return _settings
