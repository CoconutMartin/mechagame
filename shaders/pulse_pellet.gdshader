shader_type spatial;
// An electric pulse pellet (PulsePelletLook): a camera-facing orb with a hot core, a blue halo, a wobbling ring and
// crackling filaments that jump about 14 times a second. Blended over the scene (an added blend vanished on the bright
// day map); values above 1 bloom with the map glow. Size, seed and fade are per instance.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 halo_color : source_color = vec3(0.1, 0.45, 1.0);
uniform vec3 core_color : source_color = vec3(0.8, 0.96, 1.0);
// Brightness. Keep it low: bright emissive colors wash out in the tonemapper.
uniform float energy = 1.5;
// Filament jumps per second.
uniform float crackle_rate = 14.0;
instance uniform float size = 1.0;
instance uniform float seed = 0.0;
instance uniform float fade = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX *= size;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = TIME;
	float core = smoothstep(0.24, 0.06, r);
	float halo = exp(-r * r * 7.0) * 0.8;
	float filaments = 0.0;
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float jump = floor(t * crackle_rate + fk * 0.5);
		float n = vnoise(vec2(a * 2.5 + seed + fk * 3.1 + jump * 0.37, r * 3.0 - t * 6.0 + fk * 5.0));
		float bent = a + (n - 0.5) * 1.8 * r;
		float spokes = abs(sin(bent * (2.5 + fk) + jump * 1.7 + seed));
		filaments += pow(1.0 - spokes, 28.0) * smoothstep(1.0, 0.3, r) * smoothstep(0.1, 0.2, r);
	}
	float ring = exp(-pow((r - 0.55 - 0.06 * sin(t * 30.0 + seed)) * 14.0, 2.0)) * 0.3;
	float flicker = 0.82 + 0.18 * sin(t * 53.0 + seed * 7.0) * sin(t * 31.0 + seed);
	float edge = smoothstep(1.0, 0.85, r);
	float glow = clamp(halo * 0.7 + filaments * 1.2 + ring, 0.0, 1.0);
	vec3 color = mix(halo_color * (1.0 + filaments), core_color * 1.5, core);
	ALBEDO = color * energy * flicker;
	ALPHA = clamp(core + glow, 0.0, 1.0) * fade * edge;
}
