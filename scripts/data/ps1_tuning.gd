class_name PS1Tuning
extends RefCounted
## The player's PS1 skin tuning (garage menu, user request 2026-10-13): changes the shared settings
## (data/skins/ps1_skin.tres, used by every PS1 skin material) at run time, keeps them in
## user://ps1_tuning.cfg so they stay after a restart, and resets them to the file's values.

const SETTINGS_PATH := "res://data/skins/ps1_skin.tres"
const SAVE_PATH := "user://ps1_tuning.cfg"
## The tuned values (the menu shows these).
const KEYS: Array[StringName] = [&"uv_pixels", &"texels_per_meter", &"detail_strength", &"metal_brightness",
		&"color_steps", &"snap_grid"]

static var _loaded := false


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
	return shared


## Sets one value, saves the tuning and updates every skin material in the game.
static func set_value(tree: SceneTree, key: StringName, value: Variant) -> void:
	var shared := settings()
	shared.set(key, value)
	var file := ConfigFile.new()
	for k in KEYS:
		file.set_value("ps1", k, shared.get(k))
	file.save(SAVE_PATH)
	PS1Skin.refresh_all(tree.root, shared)


## Back to the values in the settings file; the saved tuning is removed.
static func reset(tree: SceneTree) -> void:
	var shared := settings()
	var defaults := ResourceLoader.load(SETTINGS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PS1SkinSettings
	for key in KEYS:
		shared.set(key, defaults.get(key))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	PS1Skin.refresh_all(tree.root, shared)
