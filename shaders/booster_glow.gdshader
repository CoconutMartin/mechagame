shader_type spatial;
// A soft round glow that faces the camera (the heat haze and the nozzle flare of BoosterPlume). Blended over the scene
// (an added blend vanished on the bright day map); values above 1 bloom with the map glow. The quad is 1 m wide;
// `size` makes it bigger.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Color of the glow.
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.15);
// Brightness. Keep it low: bright emissive colors wash out in the tonemapper.
uniform float energy = 1.6;
// Opacity at the center (0 to 1), also scaled by the thrust.
uniform float alpha_scale = 0.6;
// Width of the quad in meters.
uniform float size = 1.0;
// Thrust (0 to 1.4).
uniform float intensity = 1.0;

void vertex() {
	// Face the camera, keep the node position.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float soft = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	ALBEDO = glow_color * energy * mix(0.6, 1.0, soft);
	ALPHA = soft * alpha_scale * clamp(intensity, 0.0, 1.0);
}
