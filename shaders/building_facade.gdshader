// Building facade (Phase 8): concrete with floor slabs and a grid of glass windows, in world
// space, so the windows line up across the building blocks. Tops are plain concrete.
// windows = 0: plain concrete (rubble). Concrete: CC0 Poly Haven textures (materials/textures/cc0).
shader_type spatial;

uniform vec4 tint : source_color = vec4(0.55, 0.55, 0.56, 1.0);
uniform float windows = 1.0;
// Floor height and window spacing along the wall, in meters.
uniform float floor_height = 4.0;
uniform float window_spacing = 3.0;
// Window size (width, height) in meters.
uniform vec2 window_size = vec2(1.9, 2.3);
// Slab band at each floor, in meters.
uniform float slab_height = 0.45;
uniform vec4 glass_color : source_color = vec4(0.07, 0.09, 0.11, 1.0);
// Part of the windows with a warm light inside.
uniform float lit_share = 0.04;
uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// Meters per texture repeat.
uniform float texture_size = 4.0;
// Average brightness of the concrete texture (the tint sets the final brightness).
uniform float texture_mean = 0.36;

varying vec3 world_pos;
varying vec3 world_normal;

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
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	bool wall = n.y < 0.5;
	// Wall coordinate: along the wall and up.
	vec2 wall_uv = n.x > n.z ? world_pos.zy : world_pos.xy;
	vec2 top_uv = world_pos.xz;
	vec2 uv = wall ? wall_uv : top_uv;

	// Concrete texture, plus large stains so the repeats do not show.
	vec2 tex_uv = uv / texture_size;
	float stains = fbm(uv * 0.15);
	float grain = texture(concrete_rough, tex_uv).r;
	vec3 concrete = texture(concrete_albedo, tex_uv).rgb / texture_mean;
	vec3 color = tint.rgb * concrete * (0.8 + 0.3 * stains);
	NORMAL_MAP = texture(concrete_normal, tex_uv).rgb;
	// Rain streaks down the walls.
	if (wall) {
		float streak = value_noise(vec2(uv.x * 3.0, uv.y * 0.08));
		color *= 1.0 - 0.12 * smoothstep(0.55, 0.95, streak);
	}
	float rough = mix(0.7, 0.95, grain);
	float metal = 0.0;
	vec3 glow = vec3(0.0);

	if (wall && windows > 0.5) {
		float level = world_pos.y / floor_height;
		float in_floor = fract(level) * floor_height;
		// Slab band at the bottom of each floor.
		if (in_floor < slab_height) {
			color *= 0.8;
		}
		vec2 cell = vec2(wall_uv.x / window_spacing, level);
		vec2 local = vec2(fract(cell.x) * window_spacing, in_floor);
		vec2 lo = vec2((window_spacing - window_size.x) * 0.5, slab_height + 0.5);
		vec2 hi = lo + window_size;
		bool ground_floor = world_pos.y < floor_height;
		if (!ground_floor && local.x > lo.x && local.x < hi.x && local.y > lo.y && local.y < hi.y) {
			// Frame edge 0.08 m.
			vec2 edge = min(local - lo, hi - local);
			if (min(edge.x, edge.y) < 0.08) {
				color = vec3(0.16);
				rough = 0.5;
				metal = 0.6;
			} else {
				float id = hash(floor(cell) + floor(world_pos.x * 0.01) * 7.0);
				color = glass_color.rgb * (0.8 + 0.4 * id);
				rough = 0.06;
				metal = 0.85;
				if (id < lit_share) {
					glow = vec3(1.0, 0.8, 0.55) * 0.1;
				}
			}
		}
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = glow;
}
