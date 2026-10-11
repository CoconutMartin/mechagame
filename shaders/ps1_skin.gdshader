shader_type spatial;
// PS1-style skin (Sanggigilid, user request 2026-10-11): chunky nearest-filtered pixel textures in a
// box mapping on the part's rest position, a tint per part, pixel-edged hazard stripes and a round
// emblem, 15-bit color with an ordered dither, and vertices snapped to a low-resolution screen grid
// (the PS1 wobble, a light one: the mesh is far denser than a PS1 model). Set by PS1SkinLook; to_rest is the same per-frame transform as the char crust's.
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D grey_texture : source_color, filter_nearest, repeat_enable;
// Turns this frame's (skinned) vertex position back to its rest position (mesh space).
uniform mat4 to_rest = mat4(1.0);
// Texture pixels per meter (the texture is texture_size pixels wide).
uniform float texels_per_meter = 16.0;
uniform float texture_size = 64.0;
// Texture shift for this part, so the parts do not all show the same panel at the same place.
uniform vec2 uv_offset = vec2(0.0);
uniform vec3 tint : source_color = vec3(0.45, 0.46, 0.44);
// Grey texture to color: color = tint * grey * brightness, grey contrast stretched around 0.55.
uniform float brightness = 1.9;
uniform float contrast = 1.8;
// Hazard stripe: a band of rest height (mesh space, m) on the side faces. Off when min >= max.
uniform vec3 stripe_color : source_color = vec3(0.85, 0.66, 0.12);
uniform float stripe_min = 0.0;
uniform float stripe_max = 0.0;
// Emblem: a red disc with a light ring on the faces that look along emblem_normal (rest space).
uniform vec3 emblem_center = vec3(0.0);
uniform vec3 emblem_normal = vec3(0.0, 1.0, 0.0);
uniform float emblem_radius = 0.0;
uniform vec3 emblem_color : source_color = vec3(0.75, 0.16, 0.08);
uniform vec3 emblem_ring : source_color = vec3(0.86, 0.84, 0.78);
// Color steps per channel (32 = PS1 15-bit color) and the screen grid of the vertex snap
// (0 = no snap).
uniform float color_steps = 32.0;
uniform vec2 snap_grid = vec2(320.0, 240.0);

varying vec3 rest_pos;
varying vec3 rest_normal;

void vertex() {
	rest_pos = (to_rest * vec4(VERTEX, 1.0)).xyz;
	rest_normal = normalize(mat3(to_rest) * NORMAL);
	if (snap_grid.x > 0.0) {
		vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_grid * 0.5 + 0.5) / (snap_grid * 0.5);
		clip.xy = ndc * clip.w;
		POSITION = clip;
	}
}

// 4 x 4 ordered dither value (0 to 1) for a screen pixel.
float dither(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int index = x + y * 4;
	int pattern[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(pattern[index]) + 0.5) / 16.0;
}

void fragment() {
	// Box mapping: the texture lies on the plane facing the main axis of the rest normal.
	vec3 n = abs(rest_normal);
	vec2 plane = n.x > n.y && n.x > n.z ? rest_pos.zy : (n.y > n.z ? rest_pos.xz : rest_pos.xy);
	vec2 uv = plane * texels_per_meter / texture_size + uv_offset;
	float grey = clamp((texture(grey_texture, uv).r - 0.55) * contrast + 0.55, 0.0, 1.0);
	vec3 color = tint * grey * brightness;
	// Pattern positions on the texel grid, so the stripe and emblem edges are pixel steps.
	vec3 cell = (floor(rest_pos * texels_per_meter) + 0.5) / texels_per_meter;
	if (stripe_max > stripe_min && n.y < 0.7 && cell.y > stripe_min && cell.y < stripe_max) {
		color = stripe_color * grey * brightness;
	}
	if (emblem_radius > 0.0 && dot(rest_normal, emblem_normal) > 0.6) {
		vec3 offset = cell - emblem_center;
		float distance_on_face = length(offset - emblem_normal * dot(offset, emblem_normal));
		if (distance_on_face < emblem_radius) {
			color = emblem_color * (0.8 + grey * 0.4);
		} else if (distance_on_face < emblem_radius * 1.25) {
			color = emblem_ring * grey * 1.4;
		}
	}
	// 15-bit color with an ordered dither.
	color = floor(color * (color_steps - 1.0) + dither(FRAGCOORD.xy)) / (color_steps - 1.0);
	ALBEDO = clamp(color, 0.0, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
