class_name MechSkinChoice
extends RefCounted
## The mech texture the player picked in the garage (user request 2026-10-13): Basic (the model's own
## materials), PS1 (PS1Skin) or Realistic (RealisticSkin). It is for every mech, weapon and equipment,
## kept in user://mech_skin.cfg so it stays after a restart. PS1 at first.

enum Style { BASIC, PS1, REALISTIC }

const NAMES: Array[String] = ["Basic", "PS1", "Realistic"]
const SAVE_PATH := "user://mech_skin.cfg"
## Group of the nodes that put the skin on a mech (PS1SkinLook).
const GROUP := &"mech_skin_look"

static var _style := Style.PS1
static var _loaded := false


## The style in use (the pick, read once from the save file). PS1 shows as Basic while the PS1 look is off
## (PS1SkinSettings.enabled, user 2026-10-31: "lift the PS1 graphics for now").
static func style() -> Style:
	if not _loaded:
		_loaded = true
		var file := ConfigFile.new()
		if file.load(SAVE_PATH) == OK:
			_style = clampi(int(file.get_value("skin", "style", Style.PS1)), 0, NAMES.size() - 1) as Style
	return _usable(_style)


## The pick as saved (PS1 stays PS1 here even while the look is off).
static func picked() -> Style:
	style()
	return _style


## True when the PS1 look may be used (data/skins/ps1_skin.tres).
static func ps1_enabled() -> bool:
	var settings := load("res://data/skins/ps1_skin.tres") as PS1SkinSettings
	return settings == null or settings.enabled


static func _usable(value: Style) -> Style:
	return Style.BASIC if value == Style.PS1 and not ps1_enabled() else value


## Sets the style, saves it and changes the skin on every mech in the game.
static func set_style(tree: SceneTree, value: Style) -> void:
	style()
	_style = value
	var file := ConfigFile.new()
	file.set_value("skin", "style", int(value))
	file.save(SAVE_PATH)
	for look in tree.get_nodes_in_group(GROUP):
		look.set_style(_usable(value))
