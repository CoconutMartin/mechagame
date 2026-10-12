// PS1 look for the environment (user request 2026-10-12): the material's own colors and texture,
// read as chunky pixels (box-mapped in world or mesh space like the original triplanar mapping, or its
// UVs), 15-bit color with an ordered dither, and vertices snapped to a low-resolution screen grid (a
// light PS1 wobble). No normal maps, no shine. Made from the original materials by PS1World.
// Shared by ps1_world.gdshader (solid) and ps1_world_alpha.gdshader (see-through: glass).

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
// The same texture with smooth filtering, for far surfaces.
uniform sampler2D albedo_smooth : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_texture = false;
// 0 = mesh UVs, 1 = box mapping in world space, 2 = box mapping in mesh space.
uniform int map_mode = 0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
// Chunky pixels across one texture repeat.
uniform float pixels_per_repeat = 64.0;
// Light it gives off (color times energy; lit windows).
uniform vec3 emission = vec3(0.0);
// Color steps per channel (32 = PS1 15-bit color) and the screen grid of the vertex snap (0 = none).
uniform float color_steps = 32.0;
uniform vec2 snap_grid = vec2(640.0, 480.0);

// High precision: tablet graphics chips may use half precision, which makes the texture pixels of
// world positions (up to about 130 m) shake.
varying highp vec3 map_pos;
varying vec3 map_normal;

void vertex() {
	if (map_mode == 1) {
		map_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		map_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	} else {
		map_pos = VERTEX;
		map_normal = NORMAL;
	}
	// POSITION is written on every path: a shader that writes it skips Godot's own transform.
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Snap only vertices in front of the camera: big ground boxes reach behind it.
	if (snap_grid.x > 0.0 && clip.w > 0.0) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_grid * 0.5 + 0.5) / (snap_grid * 0.5);
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
}

// 4 x 4 ordered dither value (0 to 1) for a screen pixel.
float dither(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int index = x + y * 4;
	int pattern[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(pattern[index]) + 0.5) / 16.0;
}

vec3 ps1_quantize(vec3 color, vec2 pixel) {
	return floor(color * (color_steps - 1.0) + dither(pixel)) / (color_steps - 1.0);
}

vec3 ps1_albedo(vec2 uv) {
	vec3 color = albedo_color.rgb;
	if (use_albedo_texture) {
		highp vec2 tex_uv;
		if (map_mode == 0) {
			tex_uv = uv * uv_scale.xy + uv_offset.xy;
		} else {
			// Box mapping: the plane facing the main axis of the normal.
			highp vec3 p = map_pos * uv_scale + uv_offset;
			vec3 n = abs(map_normal);
			tex_uv = n.x > n.y && n.x > n.z ? p.zy : (n.y > n.z ? p.xz : p.xy);
		}
		highp vec2 texels = tex_uv * vec2(textureSize(albedo_texture, 0));
		// Mip level the screen needs here (far or slanted surfaces need a blurrier one), and the level
		// whose pixels are the chunky pixel size.
		float screen_level = log2(max(length(dFdx(texels)), length(dFdy(texels))));
		float chunk_level = max(log2(float(textureSize(albedo_texture, 0).x) / pixels_per_repeat), 0.0);
		// Wrap to one repeat (the texture repeats), so the numbers stay small.
		highp vec2 wrapped = fract(tex_uv);
		if (screen_level <= chunk_level) {
			// Near: chunky pixels, each the average color there.
			highp vec2 chunky = (floor(wrapped * pixels_per_repeat) + 0.5) / pixels_per_repeat;
			color *= textureLod(albedo_texture, chunky, chunk_level).rgb;
		} else {
			// Far: a chunky pixel is smaller than a screen pixel; snapping would shimmer when moving.
			color *= textureLod(albedo_smooth, wrapped, screen_level).rgb;
		}
	}
	return color;
}
