shader_type spatial;
// Panel flame (BoosterPanelFlame; user request 2026-11-03: "Boost Pack boosts should come from the entire backpack
// panel, light blue fire, realistic, some character"). mode 0: a flame tongue (UV.y: 1 at the panel, 0 at the tip),
// a turbulent ragged sheet, white-blue hot at the base, light blue in the middle, a deep blue see-through tail, faint
// bright bands at the base. mode 1: a card over the panel (seen from behind), a hot rippling sheet that fades with
// its layer. Unshaded, mix blend, values above 1 so the map glow blooms.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 hot_color : source_color = vec3(0.85, 0.95, 1.0);
uniform vec3 mid_color : source_color = vec3(0.45, 0.8, 1.0);
uniform vec3 tail_color : source_color = vec3(0.12, 0.3, 0.95);
// Brightness. Keep it low: bright emissive colors wash out in the tonemapper.
uniform float energy = 1.7;
// Turbulence speed (flame scroll) and strength.
uniform float scroll = 9.0;
uniform float ragged = 0.35;
instance uniform float seed = 0.0;
instance uniform float mode = 0.0;
// Card layer: 0 at the panel, 1 the farthest.
instance uniform float layer = 0.0;
instance uniform float fade = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 7.1) * 0.1;
}

void fragment() {
	float t = TIME;
	if (mode < 0.5) {
		float y = 1.0 - UV.y;
		float x = UV.x * 2.0 - 1.0;
		float n = fbm(vec2(x * 2.5 + seed, y * 3.0 - t * scroll));
		float sway = (fbm(vec2(seed * 1.7, y * 1.5 - t * scroll * 0.5)) - 0.5) * ragged * 2.0 * y;
		float width = pow(1.0 - y, 0.5) * (0.85 + 0.45 * n);
		float body = smoothstep(width, width * 0.15, abs(x + sway));
		float tip = smoothstep(1.0, 0.55 + 0.3 * n, y);
		float core = smoothstep(0.5, 0.0, abs(x + sway) / max(width, 0.01)) * smoothstep(0.45, 0.0, y);
		vec3 color = mix(mid_color, tail_color, smoothstep(0.25, 1.0, y));
		color = mix(color, hot_color * 1.6, core);
		float bands = exp(-pow((fract(y * 7.0 - t * 1.5 + seed) - 0.5) * 7.0, 2.0)) * smoothstep(0.4, 0.0, y) * 0.5;
		color += hot_color * bands * core;
		ALBEDO = color * energy;
		ALPHA = clamp(body * tip * (0.85 - 0.6 * y) * fade + core * 0.3 * fade, 0.0, 1.0);
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float n = fbm(p * 3.0 + vec2(seed, -t * scroll * 0.6));
		float edge = smoothstep(1.0, 0.55 - 0.2 * layer, max(abs(p.x), abs(p.y)) + (n - 0.5) * 0.35);
		float lit = edge * (0.75 + 0.55 * n) * (1.0 - 0.6 * layer);
		vec3 color = mix(hot_color * 1.5, mix(mid_color, tail_color, layer), smoothstep(0.0, 0.8, layer + (1.0 - n) * 0.3));
		ALBEDO = color * energy;
		ALPHA = clamp(lit * fade, 0.0, 1.0);
	}
}
