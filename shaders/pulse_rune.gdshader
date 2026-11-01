shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Rune pulse card for the electric shotgun shots (user reference 2026-11-01: a golden rune ring with a cyan center).
// On a 1 x 1 quad scaled to `size` (meters): a rounded rectangle with a thin outer gold line, a band of flickering gold
// glyphs, a thin inner gold line, a cyan glowing center, and sparkles in the band. Line widths follow the short side.

uniform vec2 size = vec2(4.0, 2.0);
uniform vec4 gold : source_color = vec4(1.0, 0.78, 0.32, 1.0);
uniform vec4 cyan : source_color = vec4(0.35, 0.92, 1.0, 1.0);
// Parts of the short side: outer line, glyph band, gaps, inner line; corner radius; glyph cells along the long side.
uniform float line_w = 0.045;
uniform float band_w = 0.28;
uniform float gap_w = 0.04;
uniform float corner = 0.45;
uniform float cells = 18.0;
// Center fill strength (0 = none) and a bright core line along the long axis (the X arms).
uniform float fill = 0.75;
uniform float core = 0.0;
// 0 to 1: fades the whole card.
uniform float fade = 1.0;
uniform float seed = 0.0;
// HDR boost of the gold and cyan (bloom).
uniform float glow = 1.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float s = min(size.x, size.y);
	vec2 p = (UV - 0.5) * size;
	float d = sd_round_box(p, size * 0.5 - vec2(s * line_w), s * corner * 0.5);
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	// Outer line.
	float outer = 1.0 - smoothstep(0.0, s * line_w * 0.6, abs(d));
	color += gold.rgb * outer * glow;
	alpha = max(alpha, outer);
	// Glyph band: cells around the outline, each a 3 x 4 grid of small strokes lit by a hash that changes over time.
	float band_in = s * (gap_w + band_w);
	float r = (-d - s * gap_w) / (s * band_w);
	if (r > 0.0 && r < 1.0) {
		// Glyph cells along the nearest edge (upright runes, not rays): the side edges run along y, the top and bottom
		// along x; they scroll round the ring.
		vec2 hb = size * 0.5 - vec2(s * line_w);
		vec2 ap = abs(p);
		bool on_side = (hb.x - ap.x) < (hb.y - ap.y);
		float along = on_side ? p.y * sign(p.x) : -p.x * sign(p.y);
		float cell_len = s * band_w * 0.85;
		float u = along / cell_len + TIME * 1.2;
		float edge_id = on_side ? (p.x > 0.0 ? 1.0 : 2.0) : (p.y > 0.0 ? 3.0 : 4.0);
		vec2 cell = vec2(floor(u) + edge_id * 97.0, floor(TIME * 6.0 + seed));
		vec2 g = vec2(fract(u) * 3.0, r * 4.0);
		vec2 sub = floor(g);
		vec2 f = fract(g);
		float lit = step(0.42, hash(cell * 3.1 + sub));
		float vertical = step(0.5, hash(sub + cell * 1.7 + 9.0));
		float stroke = vertical > 0.5 ? step(abs(f.x - 0.5), 0.24) * step(0.08, f.y) * step(f.y, 0.92)
				: step(abs(f.y - 0.5), 0.22) * step(0.08, f.x) * step(f.x, 0.92);
		// A blank gap between glyphs.
		stroke *= step(0.12, fract(u)) * step(fract(u), 0.94);
		float glyph = lit * stroke * (0.75 + 0.25 * hash(cell + sub + 3.0));
		float spark = step(0.982, hash(floor(vec2(u * 5.0, r * 6.0)) + floor(TIME * 24.0)));
		color += gold.rgb * glyph * glow + vec3(1.0, 0.95, 0.85) * spark * glow;
		alpha = max(alpha, max(glyph, spark));
		// A faint gold haze in the band behind the glyphs.
		alpha = max(alpha, 0.12);
		color += gold.rgb * 0.12;
	}
	// Inner line.
	float inner_d = abs(-d - band_in - s * gap_w);
	float inner = 1.0 - smoothstep(0.0, s * line_w * 0.5, inner_d);
	color += gold.rgb * inner * glow;
	alpha = max(alpha, inner * 0.9);
	// Cyan center: brighter toward the middle, rippling; a core line along the long axis.
	float inside = -d - band_in - s * gap_w * 2.0;
	if (inside > 0.0) {
		float depth = clamp(inside / (s * 0.5), 0.0, 1.0);
		float ripple = 0.85 + 0.15 * sin(length(p) / s * 18.0 - TIME * 14.0);
		float a = fill * (0.65 + 0.35 * depth) * ripple;
		vec2 axis = size.x >= size.y ? vec2(p.y, size.y) : vec2(p.x, size.x);
		float core_line = core * (1.0 - smoothstep(0.0, axis.y * 0.12, abs(axis.x)));
		color += cyan.rgb * (a + core_line * 1.2) * glow;
		alpha = max(alpha, clamp(a + core_line, 0.0, 1.0));
	}
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0) * fade;
}
