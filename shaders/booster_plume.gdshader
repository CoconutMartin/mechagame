shader_type spatial;
// A rocket exhaust plume (BoosterPlume), drawn on a lathe mesh along +Y: UV.y runs from the nozzle (0) to the tip (1),
// UV.x runs round the plume. A white-blue hot core at the nozzle turns orange and then dark red toward a ragged,
// flickering tail; the silhouette fades by the view angle so no hard edge shows; the core mesh also carries subtle
// shock diamonds (bright rings). Blended over the scene (an added blend vanished on the bright day map); values above 1
// bloom with the map glow, also in the Compatibility renderer.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Seamless noise that streams along the plume.
uniform sampler2D noise_tex : repeat_enable, filter_linear;
// Color at the nozzle (white with a blue tint).
uniform vec3 hot_color : source_color = vec3(0.8, 0.9, 1.0);
// Color of the middle of the plume.
uniform vec3 mid_color : source_color = vec3(1.0, 0.45, 0.08);
// Color of the cool tail.
uniform vec3 tail_color : source_color = vec3(0.55, 0.08, 0.02);
// Brightness. Keep it low: bright emissive colors wash out in the tonemapper.
uniform float energy = 1.7;
// Thrust (0 to 1.4): brightness and opacity follow it.
uniform float intensity = 1.0;
// How far the hot color reaches along the plume (0 = none, 1 = most of it).
uniform float core_mix = 0.9;
// Sharpness of the soft edge (more = narrower bright part).
uniform float edge_power = 1.6;
// Strength of the shock diamonds (0 = none).
uniform float diamonds = 0.0;
// Number of shock diamonds along the mesh.
uniform float diamond_count = 4.0;
// Speed of the noise along the plume (1 / s).
uniform float noise_speed = 2.2;
// Opacity scale.
uniform float alpha_scale = 1.0;

// The plume axis (+Y of the mesh) in view space.
varying vec3 axis_view;

void vertex() {
	axis_view = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	float y = UV.y;
	vec3 view = normalize(VIEW);
	// Seen from the side the middle of the plume is solid and its rim fades. Seen end on (the camera behind the
	// mech) the whole plume stays visible, a little thinner.
	float end_on = abs(dot(axis_view, view));
	float facing = clamp(max(abs(dot(normalize(NORMAL), view)), end_on * 0.65), 0.0, 1.0);
	float edge = pow(facing, edge_power);
	float turb = texture(noise_tex, vec2(UV.x * 3.0, y * 1.5 - TIME * noise_speed)).r;
	float fall = pow(1.0 - y, 0.9);
	// The tail breaks up into tongues.
	float ragged = smoothstep(-0.25, 0.12, turb - y * 0.85);
	float hot = clamp(core_mix * pow(1.0 - y, 2.0) * edge * (0.75 + 0.5 * turb), 0.0, 1.0);
	vec3 color = mix(tail_color, mid_color, smoothstep(0.95, 0.2, y));
	color = mix(color, hot_color, hot);
	// Shock diamonds: bright rings with a darker core between them, fading with the length.
	float ring = pow(abs(sin(y * diamond_count * 3.14159 + 0.6)), 6.0);
	float strength = diamonds * (1.0 - y) * edge;
	color = mix(color * (1.0 - 0.3 * strength), color * (1.0 + 0.5 * strength) + hot_color * 0.45 * strength, ring);
	ALBEDO = color * energy * (0.8 + 0.4 * turb) * clamp(intensity, 0.35, 1.4);
	ALPHA = clamp(edge * fall * ragged * smoothstep(0.0, 0.03, y) * alpha_scale * clamp(intensity, 0.0, 1.0), 0.0, 1.0);
}
