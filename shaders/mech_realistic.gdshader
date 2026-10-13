shader_type spatial;
// Realistic mech skin (user request 2026-10-13): the model's own colors as painted metal, with a
// worn paint texture on top (scratches, streaks and dirt in the paint, a normal map and a roughness
// map; CC0 green_metal_rust from Poly Haven, assets/textures/painted_metal; only its brightness
// changes the paint, so the model keeps its colors). The textures are box-mapped on the
// part's rest position (to_rest each frame, like PS1Skin), so they stay on the part when it moves.
// Low parts (feet, shins) get road dirt. Set by RealisticSkin.
render_mode cull_back;

// The model's own color: its albedo texture (when it has one) times its albedo color.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_texture = true;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float metallic = 0.3;
uniform float roughness = 0.55;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Detail texture repeats per meter. Its average brightness (smallest mipmap) is no color change.
uniform float detail_scale = 0.35;
// How much the detail texture darkens and lightens the paint (0 = clean paint).
uniform float detail_strength = 1.2;
uniform float normal_strength = 0.6;
// Large dirt patches: strength and size (repeats per meter of the same texture).
uniform float grime_strength = 0.35;
uniform float grime_scale = 0.06;
// Road dirt on low parts: strength, color and the height (rest position, meters) where it ends.
uniform float height_dirt = 0.0;
uniform vec4 dirt_color : source_color = vec4(0.32, 0.27, 0.21, 1.0);
uniform float dirt_height = 2.5;
// Texture shift for this part, so the parts do not all show the same place.
uniform vec3 uv_offset = vec3(0.0);
// Turns this frame's (skinned) vertex position back to its rest position (mesh space).
uniform mat4 to_rest = mat4(1.0);

varying vec3 rest_pos;
varying vec3 rest_normal;

void vertex() {
	rest_pos = (to_rest * vec4(VERTEX, 1.0)).xyz;
	rest_normal = normalize(mat3(to_rest) * NORMAL);
}

vec3 blend_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 triplanar(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

void fragment() {
	vec3 n = normalize(rest_normal);
	vec3 w = blend_weights(n);
	vec3 p = rest_pos * detail_scale + uv_offset;

	vec3 paint = albedo_color.rgb;
	if (use_albedo_texture) {
		paint *= texture(albedo_texture, UV).rgb;
	}
	float detail_mean = dot(textureLod(detail_albedo, vec2(0.5), 12.0).rgb, vec3(0.333));
	float detail = dot(triplanar(detail_albedo, p, w).rgb, vec3(0.333));
	vec3 color = paint * mix(1.0, detail / detail_mean, detail_strength);
	float grime = dot(triplanar(detail_albedo, rest_pos * grime_scale + uv_offset * 0.5, w).rgb, vec3(0.333));
	color *= 1.0 - grime_strength * (1.0 - smoothstep(detail_mean * 0.85, detail_mean * 1.05, grime));
	float low = height_dirt * (1.0 - smoothstep(0.0, dirt_height, rest_pos.y));
	color = mix(color, dirt_color.rgb * mix(0.7, 1.3, detail / (detail_mean * 2.0)), low * 0.75);

	// Whiteout blend of the three normal map planes (in rest space), then back to view space.
	vec3 tx = texture(detail_normal, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(detail_normal, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(detail_normal, p.xy).xyz * 2.0 - 1.0;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 bumped = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	bumped = normalize(mix(n, bumped, normal_strength));
	vec3 model_normal = inverse(mat3(to_rest)) * bumped;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(model_normal, 0.0)).xyz);

	float rough_map = triplanar(detail_roughness, p, w).r;
	ALBEDO = clamp(color, 0.0, 1.0);
	METALLIC = metallic * (1.0 - low);
	ROUGHNESS = clamp(roughness * (rough_map / 0.5) + low * 0.3, 0.05, 1.0);
}
