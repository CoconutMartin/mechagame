shader_type spatial;
// One streak of a gust of air (BoosterGust). Each particle is a thin, soft lens that lies along its own direction of
// motion (the particle's Y axis) and turns about that axis to face the camera, so it reads as a stretched wisp of
// moving air from any side. COLOR tints it and COLOR.a fades it. Mostly transparent and blended over the scene.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Streak length in meters at particle scale 1.
uniform float streak_length = 3.0;
// Streak width in meters at particle scale 1.
uniform float streak_width = 0.12;
// Tint of the air (COLOR from the particle multiplies it).
uniform vec3 air_color : source_color = vec3(1.0, 1.0, 1.0);
// Opacity at the center of a streak (before COLOR.a).
uniform float alpha_scale = 0.5;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_camera = normalize(INV_VIEW_MATRIX[3].xyz - center);
	vec3 side = cross(axis, to_camera);
	// Seen along its axis a streak has no side: keep a valid direction.
	side = length(side) < 0.001 ? MODEL_MATRIX[0].xyz : normalize(side);
	vec3 world = center + axis * VERTEX.y * streak_length * s + side * VERTEX.x * streak_width * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(clamp(UV.y, 0.0, 1.0) * 3.14159);
	float a = pow(across, 1.4) * pow(along, 1.2);
	ALBEDO = air_color * COLOR.rgb;
	ALPHA = clamp(a * alpha_scale * COLOR.a, 0.0, 1.0);
}
