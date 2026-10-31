class_name MechPaint
extends Resource
## A paint scheme for the mech body (the paint skin, MechSkinChoice; user request 2026-10-31, SGGv2).
## MechPaintSkin recolors each body texture by what each texel is (shaders/mech_paint.gdshader).

@export var display_name: String = "Paint"
@export_group("Colors")
## Main armor plates (the light armor of the model).
@export var armor_color: Color = Color(0.03, 0.03, 0.035)
## Accent panels (the darker armor panels of the model).
@export var accent_color: Color = Color(0.55, 0.03, 0.03)
## Frame, joints and the hands (the grey and black parts of the model).
@export var frame_color: Color = Color(0.13, 0.13, 0.14)
## Lamps (the orange parts of the model).
@export var lamp_color: Color = Color(1.0, 0.42, 0.05)
## Lamp glow strength.
@export_range(0.0, 8.0) var lamp_glow: float = 2.5
## Eye lenses (the red lenses of the model).
@export var eye_color: Color = Color(1.0, 0.42, 0.05)
## Eye glow strength.
@export_range(0.0, 8.0) var eye_glow: float = 3.0
@export_group("Surface")
@export_range(0.0, 1.0) var metallic: float = 0.35
@export_range(0.0, 1.0) var roughness: float = 0.5
## How much of the texture's own shading and panel lines stays (0 = flat color, 1 = full).
@export_range(0.0, 1.0) var detail: float = 0.8
@export_group("Texel classes")
## Saturation above which a texel is painted armor; below it is frame or grey armor.
@export_range(0.0, 1.0) var paint_saturation: float = 0.28
## Brightness that splits light armor (above) from the accent panels (below).
@export_range(0.0, 1.0) var accent_split: float = 0.45
## Brightness above which a grey texel is armor, not frame.
@export_range(0.0, 1.0) var grey_armor_split: float = 0.42
