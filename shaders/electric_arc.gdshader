shader_type spatial;
// A lightning ribbon (ElectricArcs): UV.y runs across the ribbon. A thin white-blue core and a soft blue halo, blended
// over the scene (an added blend vanished on the bright day map); values above 1 bloom with the map glow. COLOR tints the arc; COLOR.a fades it.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Color of the soft outer glow.
uniform vec3 halo_color : source_color = vec3(0.1, 0.45, 1.0);
// Color of the thin hot core.
uniform vec3 core_color : source_color = vec3(0.75, 0.95, 1.0);
// Brightness. Keep it low: bright emissive colors wash out in the tonemapper.
uniform float energy = 1.9;

void fragment() {
	float d = abs(UV.y * 2.0 - 1.0);
	float core = smoothstep(0.3, 0.0, d);
	float halo = exp(-d * d * 5.0) * (1.0 - d);
	vec3 color = mix(halo_color, core_color * 1.4, core);
	ALBEDO = color * energy * COLOR.rgb;
	ALPHA = clamp((core + halo * 0.9) * COLOR.a, 0.0, 1.0);
}
