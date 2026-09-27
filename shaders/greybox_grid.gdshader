// World-space grid for greybox geometry.
// Thin lines every 1 m, thick lines every 10 m. Helps judge scale and speed.
shader_type spatial;

uniform vec4 line_color : source_color = vec4(0.12, 0.12, 0.13, 1.0);
uniform float minor_cell = 1.0;
uniform float major_cell = 10.0;
uniform float minor_strength = 0.25;
uniform float major_strength = 0.8;
uniform float roughness_value = 0.85;
instance uniform vec4 tint : source_color = vec4(0.55, 0.55, 0.56, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(vec2 coord, float cell) {
	vec2 c = coord / cell;
	vec2 g = abs(fract(c - 0.5) - 0.5) / fwidth(c);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	// Project the grid onto the plane that best faces the surface.
	vec3 n = abs(world_normal);
	vec2 coord = world_pos.xz;
	if (n.x > n.y && n.x > n.z) {
		coord = world_pos.zy;
	} else if (n.z > n.y) {
		coord = world_pos.xy;
	}
	float line = max(grid_line(coord, minor_cell) * minor_strength,
			grid_line(coord, major_cell) * major_strength);
	ALBEDO = mix(tint.rgb, line_color.rgb, line);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
