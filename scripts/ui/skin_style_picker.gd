class_name SkinStylePicker
extends PanelContainer
## Mech texture picker in the garage (user request 2026-10-13): Basic, PS1 or Realistic for every
## mech, weapon and equipment (MechSkinChoice), and the pixel smoke switch (SmokeChoice). The
## changes show at once and are kept.


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "MECH TEXTURE"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var picker := OptionButton.new()
	for style_name in MechSkinChoice.NAMES:
		picker.add_item(style_name)
	picker.select(MechSkinChoice.style())
	picker.item_selected.connect(func(index: int) -> void:
			MechSkinChoice.set_style(get_tree(), index as MechSkinChoice.Style))
	box.add_child(picker)
	var smoke := CheckButton.new()
	smoke.text = "Pixel smoke (PS1 style, no flicker)"
	smoke.button_pressed = SmokeChoice.pixel_on()
	smoke.toggled.connect(func(on: bool) -> void: SmokeChoice.set_pixel(get_tree(), on))
	box.add_child(smoke)
