class_name PS1Tuning
extends RefCounted
## The player's PS1 skin tuning (garage menu, user request 2026-10-13): changes the shared settings
## (data/skins/ps1_skin.tres, used by every PS1 skin material) at run time, keeps them in
## user://ps1_tuning.cfg so they stay after a restart, and resets them to the file's values.

const SETTINGS_PATH := "res://data/skins/ps1_skin.tres"
const SAVE_PATH := "user://ps1_tuning.cfg"
## The tuned values (the menu shows these).
const KEYS: Array[StringName] = [&"uv_pixels", &"texels_per_meter", &"detail_strength", &"metal_brightness",
		&"color_steps", &"snap_grid", &"world_pixels_per_meter"]

static var _loaded := false
static var _environment := false


## The shared settings, with the saved tuning on them (read once).
static func settings() -> PS1SkinSettings:
	var shared := load(SETTINGS_PATH) as PS1SkinSettings
	if not _loaded:
		_loaded = true
		var file := ConfigFile.new()
		if file.load(SAVE_PATH) == OK:
			for key in KEYS:
				if file.has_section_key("ps1", key):
					shared.set(key, file.get_value("ps1", key))
			_environment = bool(file.get_value("ps1", "environment", false))
	return shared


## Sets one value, saves the tuning and updates every skin material in the game.
static func set_value(tree: SceneTree, key: StringName, value: Variant) -> void:
	var shared := settings()
	shared.set(key, value)
	_save()
	PS1Skin.refresh_all(tree.root, shared)


## True when the environment has the PS1 look too (off at first).
static func environment_on() -> bool:
	settings()
	return _environment


## The PS1 look on the environment on or off (every PS1WorldLook in the game), and saved.
static func set_environment(tree: SceneTree, on: bool) -> void:
	settings()
	_environment = on
	_save()
	for look in tree.get_nodes_in_group(&"ps1_world_look"):
		(look as PS1WorldLook).set_active(on)


static func _save() -> void:
	var shared := settings()
	var file := ConfigFile.new()
	for k in KEYS:
		file.set_value("ps1", k, shared.get(k))
	file.set_value("ps1", "environment", _environment)
	file.save(SAVE_PATH)


## Back to the values in the settings file (the environment switch stays).
static func reset(tree: SceneTree) -> void:
	var shared := settings()
	var defaults := ResourceLoader.load(SETTINGS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PS1SkinSettings
	for key in KEYS:
		shared.set(key, defaults.get(key))
	# The tuning goes back; the environment switch stays as it is.
	_save()
	PS1Skin.refresh_all(tree.root, shared)
