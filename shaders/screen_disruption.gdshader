shader_type canvas_item;
// Screen disruption (ScreenDisruption; user request 2026-11-02: hits by the pulse shotguns): the color channels split
// sideways, bands of the screen tear left and right, scanlines and blue static flicker over it. amount 0 to 1.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Largest sideways color split and band tear, as a part of the screen width, at amount 1.
uniform float split = 0.008;
uniform float tear = 0.05;
// Torn bands across the screen height.
uniform float bands = 36.0;
// Static strength and blue tint at amount 1.
uniform float static_strength = 0.22;
uniform vec3 tint : source_color = vec3(0.7, 0.9, 1.3);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 30.0);
	float row = floor(uv.y * bands);
	float torn = step(1.0 - 0.45 * amount, hash(vec2(row, t)));
	float shift = (hash(vec2(row + 7.0, t)) - 0.5) * 2.0 * tear * amount * torn;
	uv.x += shift;
	float s = split * amount * (0.6 + 0.4 * hash(vec2(t, 3.0)));
	vec3 color;
	color.r = texture(screen_texture, uv + vec2(s, 0.0)).r;
	color.g = texture(screen_texture, uv).g;
	color.b = texture(screen_texture, uv - vec2(s, 0.0)).b;
	color *= 1.0 - 0.18 * amount * (0.5 + 0.5 * sin(SCREEN_UV.y * 900.0 + TIME * 40.0));
	color += (hash(SCREEN_UV * 1000.0 + t) - 0.5) * static_strength * amount;
	color = mix(color, color * tint, 0.45 * amount);
	color *= 1.0 + 0.25 * amount * (hash(vec2(t, 9.0)) - 0.5);
	COLOR = vec4(color, 1.0);
}
