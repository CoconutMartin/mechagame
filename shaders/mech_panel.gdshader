// Mech armor on box pieces (Phase 8): painted metal with grime, a panel groove inset from the
// edges, bolts near the corners and worn bright edges. Box meshes put each face in one cell of a
// 3 x 2 UV grid, so fract(UV * (3, 2)) is the place on the face (0 to 1). The face size in meters
// comes from the screen derivatives, so the grooves keep the same width on every box.
// The grime, roughness and normal textures map in object space (they move with the part).
shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.7, 0.69, 0.66, 1.0);
uniform float metallic = 0.45;
uniform float roughness = 0.62;
uniform sampler2D grime_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 0.3;
uniform float normal_strength = 0.35;
// Panel groove: inset from the face edge and width, in meters. Faces smaller than min_panel get none.
uniform float groove_inset = 0.16;
uniform float groove_width = 0.035;
uniform float min_panel = 0.75;
// Bolts: radius in meters.
uniform float bolt_radius = 0.045;
// Worn edge width in meters and how bright it gets.
uniform float edge_width = 0.05;
uniform float edge_wear = 0.35;

varying vec3 object_pos;
varying vec3 object_normal;
varying vec3 world_pos;

vec4 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

void vertex() {
	object_pos = VERTEX;
	object_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = object_pos * texture_scale;
	vec3 grime = triplanar(grime_texture, p, object_normal).rgb;
	float rough_tex = triplanar(roughness_texture, p, object_normal).r;
	vec3 color = albedo.rgb * grime;
	float rough = roughness * rough_tex;
	float metal = metallic;

	// Place on the face (0 to 1) and meters per face unit (u and v).
	vec2 face = UV * vec2(3.0, 2.0);
	vec2 f = fract(face);
	vec3 dpdx = dFdx(world_pos);
	vec3 dpdy = dFdy(world_pos);
	vec2 dfdx = dFdx(face);
	vec2 dfdy = dFdy(face);
	float det = dfdx.x * dfdy.y - dfdx.y * dfdy.x;
	vec2 size = vec2(1.0);
	if (abs(det) > 1e-8) {
		vec3 dpdu = (dpdx * dfdy.y - dpdy * dfdx.y) / det;
		vec3 dpdv = (dpdy * dfdx.x - dpdx * dfdy.x) / det;
		size = vec2(length(dpdu), length(dpdv));
	}
	vec2 meters = f * size;
	vec2 to_edge = min(meters, size - meters);
	float edge = min(to_edge.x, to_edge.y);

	// Worn edges: patchy bright metal.
	float wear = (1.0 - smoothstep(edge_width * 0.4, edge_width, edge)) * smoothstep(0.35, 0.75, grime.r * 1.2 - 0.2 + rough_tex * 0.3);
	color = mix(color, vec3(0.62, 0.62, 0.6), wear * edge_wear);
	metal = mix(metal, 0.85, wear);
	rough = mix(rough, 0.35, wear);

	if (min(size.x, size.y) > min_panel) {
		// Groove.
		float groove = 1.0 - smoothstep(groove_width * 0.5, groove_width, abs(edge - groove_inset));
		color *= 1.0 - 0.55 * groove;
		rough = mix(rough, 0.9, groove);
		// Bolts inside the groove corners.
		vec2 corner = min(meters, size - meters) - vec2(groove_inset * 0.55);
		float bolt = 1.0 - smoothstep(bolt_radius * 0.7, bolt_radius, length(corner));
		color = mix(color, color * 0.45 + vec3(0.05), bolt);
		metal = mix(metal, 0.8, bolt);
	}

	ALBEDO = color;
	METALLIC = metal;
	ROUGHNESS = rough;
	NORMAL_MAP = triplanar(normal_texture, p * 1.5, object_normal).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
