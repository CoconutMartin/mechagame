shader_type spatial;
// Pulse scan wire frame (PulseScanEffect): a full screen pass. It rebuilds each pixel's world place from
// the depth buffer, draws green lines on depth edges (silhouettes and creases) and a world grid, and a
// bright ring at the pulse front. A place shows the wire frame for wire_time after the ring passes it.
// Then it fades out slowly over end_band / ring_speed seconds, starting at the origin and moving out at the
// ring speed (user request 2026-10-24: no second ring).
// The front ring fades over the last part of the range (range_fade) before it stops.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 origin;
uniform float elapsed = 0.0;
uniform float ring_speed = 350.0;
uniform float range_m = 500.0;
uniform float wire_time = 4.0;
uniform vec4 color : source_color = vec4(0.3, 1.0, 0.4, 1.0);
uniform vec4 dark : source_color = vec4(0.0, 0.08, 0.03, 1.0);
uniform float tint = 0.5;
uniform float edge_strength = 1.0;
uniform float edge_threshold = 0.004;
uniform float grid_m = 10.0;
uniform float grid_strength = 0.6;
uniform float ring_width = 3.0;
uniform float ring_strength = 0.7;
uniform float end_band = 150.0;
uniform float range_fade = 0.15;

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float depth = textureLod(depth_tex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 view = view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float z = -view.z;
	if (z > 3000.0) {
		discard;
	}
	vec3 world = (INV_VIEW_MATRIX * vec4(view, 1.0)).xyz;
	float dist = length(world.xz - origin.xz);
	float age = elapsed - dist / ring_speed;
	if (dist > range_m || age < -ring_width / ring_speed) {
		discard;
	}
	// After wire_time each place fades out slowly (over end_band / ring_speed seconds). Places near the
	// origin start first, so the fade moves out from the mech at the ring speed.
	float show = step(0.0, age) * (1.0 - smoothstep(wire_time, wire_time + end_band / ring_speed, age));
	// Edges: the screen space laplacian of 1/z is 0 on any flat surface, so only silhouettes and creases show.
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float c = 1.0 / z;
	float l = 1.0 / -view_pos(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX).z;
	float r = 1.0 / -view_pos(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX).z;
	float d = 1.0 / -view_pos(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX).z;
	float u = 1.0 / -view_pos(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX).z;
	float lap = abs(l + r + d + u - 4.0 * c) / c;
	float edge = smoothstep(edge_threshold, edge_threshold * 3.0, lap);
	// World grid lines, thinner with distance (fwidth).
	vec3 cell = abs(fract(world / grid_m) - 0.5);
	vec3 width = fwidth(world / grid_m) * 1.5;
	vec3 on = 1.0 - smoothstep(width * 0.5, width, 0.5 - cell);
	float grid = max(max(on.x, on.z), on.y * 0.6) * grid_strength;
	float front = elapsed * ring_speed;
	float front_fade = 1.0 - smoothstep(range_m * (1.0 - range_fade), range_m, front);
	float ring = front <= range_m ? exp(-pow((dist - front) / ring_width, 2.0)) * ring_strength * front_fade : 0.0;
	// Dark green over the scanned places, bright lines on top (the reference pictures).
	float line = clamp(max(edge * edge_strength, grid) * show + ring, 0.0, 1.0);
	ALBEDO = mix(dark.rgb, color.rgb, line);
	ALPHA = clamp(max(tint * show, line), 0.0, 1.0);
}
