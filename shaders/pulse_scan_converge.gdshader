shader_type spatial;
// Pulse scan converge shell (PulseScanHighlight): a wire sphere that shrinks onto a found mech.
render_mode unshaded, depth_test_disabled, blend_add, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.35, 1.0, 0.45, 1.0);
uniform float strength = 1.0;
uniform vec2 lines = vec2(24.0, 12.0);

void fragment() {
	vec2 cell = abs(fract(UV * lines) - 0.5);
	vec2 width = fwidth(UV * lines) * 1.2;
	vec2 on = 1.0 - smoothstep(width * 0.5, width, 0.5 - cell);
	ALBEDO = color.rgb;
	ALPHA = clamp(max(on.x, on.y) * strength, 0.0, 1.0);
}
