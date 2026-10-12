shader_type spatial;
// PS1 look for see-through environment surfaces (glass; see ps1_world.gdshaderinc).
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/ps1_world.gdshaderinc"

void fragment() {
	ALBEDO = clamp(ps1_quantize(ps1_albedo(UV), FRAGCOORD.xy), 0.0, 1.0);
	ALPHA = albedo_color.a;
	EMISSION = emission;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
