class_name Garage
extends CanvasLayer
## Garage screen (Phase 5). G opens and closes it in the level (Esc also closes it).
## The game pauses and a camera circles the player mech. Every change rebuilds the mech at once
## at its place (full HP), so the look and the stats show the new build.
##   Frame: head, core, arms, legs, booster, generator, FCS (GarageCatalog).
##   Weapons: right arm, left arm (shield or none; none with a two-hand weapon), back units.
##   Plates: 0 to 3 per part (light or heavy), shown as armor slabs (PlateMounter).
##   Mods: up to max_mods.
##   Test targets: spawn or remove the enemy (AI) and the dummy mech.
## Stats show the change from the build the garage opened with (GarageStatPanel).

@export var catalog: GarageCatalog
@export var switcher: LoadoutSwitcher
## Most mods on one mech.
@export var max_mods: int = 3

var is_open: bool = false

var _edit: Loadout
var _before_loadout: Loadout
var _before: MechStats
var _root: Control
var _stats: GarageStatPanel
var _camera: GarageCamera
## Picker name -> OptionButton, and the items behind its entries (null = none).
var _pickers := {}
var _items := {}
## Other screen layers (HUD, reticle) hidden while the garage is open.
var _hidden_layers: Array[CanvasLayer] = []

const PARTS := [
	["head", "Head", "heads"], ["core", "Core", "cores"], ["arm_left", "Arm L", "arms_left"],
	["arm_right", "Arm R", "arms_right"], ["legs", "Legs", "legs"], ["booster", "Booster", "boosters"],
	["generator", "Generator", "generators"], ["fcs", "FCS", "fcs"],
]
## [loadout property, label, catalog list, "none" allowed]
const WEAPONS := [
	["weapon_right", "Right arm", "weapons_right", false], ["weapon_left", "Left arm", "weapons_left", true],
	["back_left", "Back L", "backs_left", true], ["back_right", "Back R", "backs_right", true],
]
const PLATE_SLOTS := ["Head", "Core", "Arm L", "Arm R", "Legs"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_camera = GarageCamera.new()
	_camera.name = "GarageCamera"
	add_child(_camera)
	_build_ui()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("garage"):
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open or switcher == null or not is_instance_valid(switcher.mech):
		return
	is_open = true
	_before_loadout = switcher.current_loadout
	_before = StatCalculator.compute(_before_loadout)
	_edit = _copy(_before_loadout)
	_show_loadout(_edit)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.start(switcher.mech)
	_refresh_stats()
	_root.visible = true
	_hidden_layers.clear()
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer_node := node as CanvasLayer
		if layer_node != self and layer_node.visible:
			layer_node.visible = false
			_hidden_layers.append(layer_node)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	for layer_node in _hidden_layers:
		if is_instance_valid(layer_node):
			layer_node.visible = true
	_hidden_layers.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var camera := switcher.mech.get_node_or_null("CameraRig/Pitch/SpringArm/Camera") as Camera3D
	if camera != null:
		camera.make_current()


# ---- Editing ----

## A copy with its own plate and mod lists, so edits never change a saved loadout.
static func _copy(loadout: Loadout) -> Loadout:
	var copy := loadout.duplicate() as Loadout
	copy.plates = loadout.plates.duplicate()
	copy.mods = loadout.mods.duplicate()
	return copy


## Reads every picker into the edited loadout and rebuilds the mech.
func _on_changed(_index: int = 0) -> void:
	for part in PARTS:
		_edit.set(part[0], _picked(part[0]))
	for weapon in WEAPONS:
		_edit.set(weapon[0], _picked(weapon[0]))
	# A two-hand weapon uses the left hand: no shield.
	var two_hand := _edit.weapon_right != null and _edit.weapon_right.two_handed
	var left: OptionButton = _pickers["weapon_left"]
	left.disabled = two_hand
	if two_hand:
		_edit.weapon_left = null
		left.select(0)
	var plates: Array[PlateData] = []
	for slot in PLATE_SLOTS.size():
		for i in PlateMounter.MAX_PLATES:
			var plate := _picked("plate_%d_%d" % [slot, i]) as PlateData
			if plate != null:
				plates.append(plate)
	_edit.plates = plates
	var mods: Array[ModData] = []
	for i in max_mods:
		var mod := _picked("mod_%d" % i) as ModData
		if mod != null:
			mods.append(mod)
	_edit.mods = mods
	_edit.display_name = "Custom"
	_rebuild()


func _rebuild() -> void:
	switcher.rebuild(_copy(_edit), switcher.mech.global_transform)
	_camera.target = switcher.mech
	_camera.make_current()
	_refresh_stats()


func _reset() -> void:
	_edit = _copy(_before_loadout)
	_show_loadout(_edit)
	_rebuild()


func _refresh_stats() -> void:
	_stats.show_stats(_edit, StatCalculator.compute(_edit), _before, _before_loadout)


func _picked(key: String) -> Resource:
	var picker: OptionButton = _pickers[key]
	return _items[key][maxi(picker.selected, 0)]


## Sets every picker to the loadout.
func _show_loadout(loadout: Loadout) -> void:
	for part in PARTS:
		_select(part[0], loadout.get(part[0]))
	for weapon in WEAPONS:
		_select(weapon[0], loadout.get(weapon[0]))
	(_pickers["weapon_left"] as OptionButton).disabled = loadout.weapon_right != null and loadout.weapon_right.two_handed
	for slot in PLATE_SLOTS.size():
		var of_slot := loadout.plates.filter(func(p: PlateData) -> bool: return p.slot == slot)
		for i in PlateMounter.MAX_PLATES:
			_select("plate_%d_%d" % [slot, i], of_slot[i] if i < of_slot.size() else null)
	for i in max_mods:
		_select("mod_%d" % i, loadout.mods[i] if i < loadout.mods.size() else null)


func _select(key: String, item: Resource) -> void:
	var items: Array = _items[key]
	var index := 0
	for i in items.size():
		if items[i] == item or (items[i] != null and item != null and items[i].resource_path == item.resource_path):
			index = i
			break
	(_pickers[key] as OptionButton).select(index)


# ---- Layout ----

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 12
	left.offset_top = 12
	left.offset_bottom = -12
	left.custom_minimum_size = Vector2(430, 0)
	_root.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var title := Label.new()
	title.text = "GARAGE   (G or Esc to close, right drag to turn, wheel to zoom)"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(title)

	var frame := _section(list, "FRAME")
	for part in PARTS:
		_add_picker(frame, part[0], part[1], catalog.get(part[2]), false)
	var weapons := _section(list, "WEAPONS")
	for weapon in WEAPONS:
		_add_picker(weapons, weapon[0], weapon[1], catalog.get(weapon[2]), weapon[3])
	var plates := _section(list, "PLATES (up to 3 per part)")
	for slot in PLATE_SLOTS.size():
		var choices := catalog.plates.filter(func(p: PlateData) -> bool: return p.slot == slot)
		var row := HBoxContainer.new()
		plates.add_child(row)
		var label := Label.new()
		label.text = PLATE_SLOTS[slot]
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)
		for i in PlateMounter.MAX_PLATES:
			var picker := _make_picker("plate_%d_%d" % [slot, i], choices, true, true)
			picker.custom_minimum_size = Vector2(98, 0)
			row.add_child(picker)
	var mods := _section(list, "MODS (up to %d)" % max_mods)
	for i in max_mods:
		_add_picker(mods, "mod_%d" % i, "Mod %d" % (i + 1), catalog.mods, true)
	var targets := _section(list, "TEST TARGETS")
	for node in get_tree().get_nodes_in_group(&"mech_spawner"):
		var spawner := node as MechSpawner
		var toggle := CheckButton.new()
		toggle.text = spawner.get_label()
		toggle.button_pressed = spawner.active
		toggle.toggled.connect(spawner.set_active)
		targets.add_child(toggle)

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_right = -12
	right.offset_top = 12
	right.offset_bottom = -12
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.custom_minimum_size = Vector2(380, 0)
	_root.add_child(right)
	var buttons := HBoxContainer.new()
	right.add_child(buttons)
	var reset := Button.new()
	reset.text = "Undo changes"
	reset.pressed.connect(_reset)
	buttons.add_child(reset)
	var done := Button.new()
	done.text = "Close (G)"
	done.pressed.connect(close)
	buttons.add_child(done)
	_stats = GarageStatPanel.new()
	right.add_child(_stats)
	right.add_child(GraphicsMenu.new())


func _section(parent: Control, text: String) -> VBoxContainer:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)
	var box := VBoxContainer.new()
	parent.add_child(box)
	return box


func _add_picker(parent: Control, key: String, text: String, items: Array, allow_none: bool) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	var picker := _make_picker(key, items, allow_none, false)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)


## An OptionButton with "None" (if allowed) and the display names of the items.
## short: plates show only "Light" or "Heavy".
func _make_picker(key: String, items: Array, allow_none: bool, short: bool) -> OptionButton:
	var picker := OptionButton.new()
	picker.clip_text = true
	var entries: Array = []
	if allow_none:
		entries.append(null)
		picker.add_item("None")
	for item: Resource in items:
		entries.append(item)
		var text: String = item.get("display_name")
		if short:
			text = "Heavy" if "heavy" in text.to_lower() else "Light"
		picker.add_item(text)
	_pickers[key] = picker
	_items[key] = entries
	picker.item_selected.connect(_on_changed)
	return picker
