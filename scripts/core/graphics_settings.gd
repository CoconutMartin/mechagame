extends Node
## Graphics quality presets (Phase 5): Low, Medium, High. Autoload "GraphicsSettings".
## The choice is saved in user://settings.cfg and applied at start and to every level that loads.
##   High: SDFGI, SSR, SSAO, volumetric fog, glow, TAA, full resolution, 4096 shadows, soft shadows.
##   Medium: no SDFGI and no SSR, SSAO, volumetric fog, glow, TAA, full resolution, 2048 shadows.
##   Low: no SDFGI, SSR, SSAO or volumetric fog, glow, FXAA, 75% resolution (FSR), 1024 hard shadows.

signal changed(preset: int)

enum Preset { LOW, MEDIUM, HIGH }

const PATH := "user://settings.cfg"
const NAMES := ["Low", "Medium", "High"]

## Render scale at Low (FSR upscales to the window size).
@export var low_render_scale: float = 0.75

var preset: int = Preset.HIGH


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		preset = clampi(int(config.get_value("graphics", "preset", Preset.HIGH)), Preset.LOW, Preset.HIGH)
	get_tree().node_added.connect(_on_node_added)
	apply.call_deferred()


func set_preset(value: int) -> void:
	preset = clampi(value, Preset.LOW, Preset.HIGH)
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("graphics", "preset", preset)
	config.save(PATH)
	apply()
	changed.emit(preset)


func get_preset_name() -> String:
	return NAMES[preset]


## A level with its own environment loaded: set the preset on it too.
func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		apply.call_deferred()


func apply() -> void:
	var high := preset == Preset.HIGH
	var low := preset == Preset.LOW
	var viewport := get_viewport()
	viewport.use_taa = not low
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if low else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if low else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = low_render_scale if low else 1.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else (1024 if low else 2048), true)
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else (
			RenderingServer.SHADOW_QUALITY_HARD if low else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	var world := viewport.find_world_3d()
	var environment := world.environment if world != null else null
	if environment != null:
		environment.sdfgi_enabled = high
		environment.ssr_enabled = high
		environment.ssao_enabled = not low
		environment.volumetric_fog_enabled = not low
		environment.glow_enabled = true
