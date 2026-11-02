class_name ScreenDisruption
extends CanvasLayer
## Screen disruption when the player's mech is hit by an electric weapon (user request 2026-11-02: "screen should get a
## screen disruption effect when getting hit by weapons like shotgun 2 and 3"). Each hit adds WeaponData.screen_disruption
## (up to 1); the effect fades at fade_per_second. Made on the first hit, in the current scene
## (shaders/screen_disruption.gdshader on a full-screen rect).

const SHADER := preload("res://shaders/screen_disruption.gdshader")

## Amount lost per second (1 = a full disruption fades in 1 / fade_per_second seconds).
@export var fade_per_second: float = 1.6
## Highest amount.
@export var max_amount: float = 1.0

var amount: float = 0.0

var _rect: ColorRect
var _material: ShaderMaterial


## Adds amount to the disruption of the scene that node is in. Only the player's mech gets it: call it for hits on that
## mech.
static func hit(node: Node, add: float) -> void:
	if add <= 0.0 or not node.is_inside_tree():
		return
	var scene := node.get_tree().current_scene
	if scene == null:
		return
	var effect := scene.get_node_or_null("ScreenDisruption") as ScreenDisruption
	if effect == null:
		effect = ScreenDisruption.new()
		effect.name = "ScreenDisruption"
		scene.add_child(effect)
	effect.amount = minf(effect.amount + add, effect.max_amount)


## True when a hit body is the player's mech or one of its parts (a parent in the "player" group). No Mech type here:
## Bullet uses this class, and Mech loads the bullet scene.
static func hits_player(body: Object) -> bool:
	var node := body as Node
	while node != null:
		if node.is_in_group(&"player"):
			return true
		node = node.get_parent()
	return false


func _ready() -> void:
	layer = 90
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _process(delta: float) -> void:
	amount = maxf(amount - fade_per_second * delta, 0.0)
	_rect.visible = amount > 0.0
	_material.set_shader_parameter(&"amount", amount)
