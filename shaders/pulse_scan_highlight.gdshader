shader_type spatial;
// Pulse scan highlight (PulseScanHighlight): a glow over a found mech, seen through walls.
render_mode unshaded, depth_test_disabled, blend_mix, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform float strength = 1.0;

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb;
	ALPHA = clamp(strength * (0.55 + 0.45 * rim), 0.0, 1.0);
}
