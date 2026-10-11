class_name PS1SkinSettings
extends Resource
## Tuning values of the PS1 skin (shaders/ps1_skin.gdshader), shared by the mech body and every weapon
## and equipment on it (data/skins/ps1_skin.tres).

## Chunky pixels across the whole model texture (smaller = bigger pixels).
@export var uv_pixels: float = 256.0
## Detail texture (seams, rivets, vents, dirt) pixels per meter, and how strong it shows (0 = off).
@export var texels_per_meter: float = 16.0
@export_range(0.0, 2.0) var detail_strength: float = 0.8
## Color scale of a fully metallic material: the skin has no metal shine, so a metal surface is
## darkened to look as bright as before (0.75 matched Sanggigilid). Non-metal surfaces keep 1.0;
## in between it blends by the original metallic value.
@export var metal_brightness: float = 0.75
## Color steps per channel (32 = PS1 15-bit color).
@export var color_steps: float = 32.0
## Screen grid of the vertex snap (the PS1 wobble; smaller = more wobble); (0, 0) = no snap.
@export var snap_grid: Vector2 = Vector2(640.0, 480.0)
