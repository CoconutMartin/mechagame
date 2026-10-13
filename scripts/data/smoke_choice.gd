class_name SmokeChoice
extends RefCounted
## Pixel smoke on or off (garage toggle, user request 2026-10-13), kept in user://smoke.cfg so it stays
## after a restart. On at first. PixelSmoke reads it.

const SAVE_PATH := "user://smoke.cfg"

static var _pixel := true
static var _loaded := false


## True when smoke and dust use the pixel look.
static func pixel_on() -> bool:
	if not _loaded:
		_loaded = true
		var file := ConfigFile.new()
		if file.load(SAVE_PATH) == OK:
			_pixel = bool(file.get_value("smoke", "pixel", true))
	return _pixel


## Sets the choice, saves it and changes every smoke emitter in the game.
static func set_pixel(tree: SceneTree, on: bool) -> void:
	pixel_on()
	_pixel = on
	var file := ConfigFile.new()
	file.set_value("smoke", "pixel", on)
	file.save(SAVE_PATH)
	PixelSmoke.apply_all(tree, on)
