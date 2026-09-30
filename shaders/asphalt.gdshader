// Ground (Phase 8): asphalt texture with large stains, plus faint 10 m lines
// (they help to judge scale and speed).
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.11, 0.11, 0.115, 1.0);
uniform float line_strength = 0.1;
// CC0 Poly Haven asphalt (materials/textures/cc0). Meters per texture repeat.
uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_size = 3.0;
uniform float texture_mean = 0.1;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += value_noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float stains = fbm(p * 0.05);
	vec2 tex_uv = p / texture_size;
	vec3 color = base_color.rgb * texture(asphalt_albedo, tex_uv).rgb / texture_mean * (0.75 + 0.45 * stains);
	NORMAL_MAP = texture(asphalt_normal, tex_uv).rgb;
	// Faint 10 m lines.
	vec2 c = p / 10.0;
	vec2 g = abs(fract(c - 0.5) - 0.5) / fwidth(c);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	color = mix(color, vec3(0.3, 0.3, 0.28), line * line_strength);
	ALBEDO = color;
	ROUGHNESS = texture(asphalt_rough, tex_uv).r * (0.95 - 0.1 * stains);
	METALLIC = 0.0;
}
