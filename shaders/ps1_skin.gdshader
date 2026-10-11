shader_type spatial;
// PS1-style skin (Sanggigilid, user request 2026-10-11): the model's own colors (its albedo texture
// and color), read as chunky pixels (nearest filter, UV snapped to a coarse grid), with a pixel
// detail texture on top (seams, rivets, vents, dirt; box-mapped on the part's rest position), 15-bit
// color with an ordered dither, and vertices snapped to a low-resolution screen grid (a light PS1
// wobble: the mesh is far denser than a PS1 model). Set by PS1SkinLook; to_rest is the same
// per-frame transform as the char crust's.
render_mode cull_back, diffuse_lambert, specular_disabled;

// The model's own color: its albedo texture (when it has one) times its albedo color.
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_albedo_texture = true;
uniform vec4 albedo_color : source_color = vec4(1.0);
// Color scale, so the plain (non-metal) skin is as bright as the model's metal material was.
uniform float brightness = 1.0;
// UV grid of the chunky pixels (pixels across the whole texture; the model's are 2048 wide).
uniform float uv_pixels = 256.0;
// Detail: a grey pixel texture (0.55 = no change), its pixels per meter and size, its strength.
uniform sampler2D grey_texture : filter_nearest, repeat_enable;
uniform float texels_per_meter = 16.0;
uniform float texture_size = 64.0;
uniform float detail_strength = 1.0;
// Texture shift for this part, so the parts do not all show the same panel at the same place.
uniform vec2 uv_offset = vec2(0.0);
// Turns this frame's (skinned) vertex position back to its rest position (mesh space).
uniform mat4 to_rest = mat4(1.0);
// Color steps per channel (32 = PS1 15-bit color) and the screen grid of the vertex snap
// (0 = no snap).
uniform float color_steps = 32.0;
uniform vec2 snap_grid = vec2(640.0, 480.0);

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
	vec3 color = albedo_color.rgb * brightness;
	if (use_albedo_texture) {
		vec2 chunky = (floor(UV * uv_pixels) + 0.5) / uv_pixels;
		// The mip level whose pixels are the grid size: each chunky pixel is the average color there.
		float level = max(log2(float(textureSize(albedo_texture, 0).x) / uv_pixels), 0.0);
		color *= textureLod(albedo_texture, chunky, level).rgb;
	}
	// Box mapping: the detail lies on the plane facing the main axis of the rest normal.
	vec3 n = abs(rest_normal);
	vec2 plane = n.x > n.y && n.x > n.z ? rest_pos.zy : (n.y > n.z ? rest_pos.xz : rest_pos.xy);
	float grey = texture(grey_texture, plane * texels_per_meter / texture_size + uv_offset).r;
	color *= mix(1.0, grey / 0.55, detail_strength);
	// 15-bit color with an ordered dither.
	color = floor(color * (color_steps - 1.0) + dither(FRAGCOORD.xy)) / (color_steps - 1.0);
	ALBEDO = clamp(color, 0.0, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
