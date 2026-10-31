shader_type spatial;
// Paint skin (user requests 2026-10-31, SGGv2: navy armor, orange accents, dark grey frame, orange lamps,
// eyes in the accent color).
// Recolors the model's own albedo by what each texel is: an orange lamp, a light armor plate, a dark armor
// panel (the accent), or the grey / black frame. The texel's brightness against its class's typical
// brightness keeps the texture's panel lines, dirt and shading. MechPaintSkin fills the uniforms from a
// MechPaint resource and the original material.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_normal = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
uniform float metallic = 0.3;
uniform float roughness = 0.55;

uniform vec4 armor_color : source_color;
uniform vec4 accent_color : source_color;
uniform vec4 frame_color : source_color;
uniform vec4 lamp_color : source_color;
uniform float lamp_glow = 2.0;
uniform vec4 eye_color : source_color;
uniform float eye_glow = 3.0;
// Eye lens: red (hue near 0), the lowest saturation and brightness.
uniform float eye_saturation = 0.45;
uniform float eye_value = 0.3;
// Saturation above which a texel is painted (olive armor); below it is frame or grey armor.
uniform float paint_saturation = 0.28;
// Brightness that splits light armor (above) from the darker accent panels (below).
uniform float accent_split = 0.45;
// Brightness above which an unpainted (grey) texel counts as armor, not frame.
uniform float grey_armor_split = 0.42;
// Lamp: hue range (0..1) and the lowest saturation and brightness.
uniform vec2 lamp_hue = vec2(0.03, 0.12);
uniform float lamp_saturation = 0.55;
uniform float lamp_value = 0.5;
// How much of the texture's own brightness change stays (0 = flat color, 1 = full detail).
uniform float detail = 0.8;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 shade(vec3 target, float value, float typical) {
	float ratio = clamp(value / max(typical, 0.02), 0.45, 1.6);
	return target * mix(1.0, ratio, detail);
}

void fragment() {
	vec3 source = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	vec3 hsv = rgb_to_hsv(source);
	float painted = smoothstep(paint_saturation - 0.06, paint_saturation + 0.06, hsv.y);
	float light = smoothstep(accent_split - 0.05, accent_split + 0.05, hsv.z);
	float grey_light = smoothstep(grey_armor_split - 0.05, grey_armor_split + 0.05, hsv.z);
	float lamp = step(lamp_hue.x, hsv.x) * step(hsv.x, lamp_hue.y)
			* smoothstep(lamp_saturation - 0.05, lamp_saturation + 0.05, hsv.y)
			* smoothstep(lamp_value - 0.05, lamp_value + 0.05, hsv.z);
	float red = max(step(hsv.x, 0.025), step(0.95, hsv.x));
	float eye = red * smoothstep(eye_saturation - 0.05, eye_saturation + 0.05, hsv.y)
			* smoothstep(eye_value - 0.05, eye_value + 0.05, hsv.z);
	vec3 armor = shade(armor_color.rgb, hsv.z, 0.6);
	vec3 accent = shade(accent_color.rgb, hsv.z, 0.33);
	vec3 frame = shade(frame_color.rgb, hsv.z, 0.18);
	vec3 paint = mix(accent, armor, light);
	vec3 grey = mix(frame, shade(armor_color.rgb, hsv.z, 0.55), grey_light);
	vec3 color = mix(grey, paint, painted);
	color = mix(color, lamp_color.rgb, lamp);
	color = mix(color, eye_color.rgb, eye);
	ALBEDO = color;
	EMISSION = lamp_color.rgb * lamp * lamp_glow + eye_color.rgb * eye * eye_glow;
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, 0.3, max(lamp, eye));
	if (has_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
