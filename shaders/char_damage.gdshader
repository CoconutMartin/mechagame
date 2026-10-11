shader_type spatial;
// Charred damage crust (new mech): a lumpy, glossy black coal layer drawn over a part as a
// material overlay. It grows in patches with the damage and covers the part fully near 1 HP.
// Noise uses the part's rest-pose position (to_rest), so the crust stays on the part when it moves.
render_mode cull_back, depth_draw_opaque;

// 0 = no crust, 1 = fully covered (1 HP).
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Turns this frame's (skinned) vertex position back to its rest position (mesh space).
uniform mat4 to_rest = mat4(1.0);
// Crust lump size (noise cells per meter) and height (m) at full damage.
uniform float lump_scale = 2.2;
uniform float lump_height = 0.12;
// 0 = no push out (a low-poly mesh with hard edges would crack open along its edges).
uniform float push = 1.0;
// Fine rock grain (cells per meter) and its bump strength.
uniform float grain_scale = 9.0;
uniform float grain_bump = 0.9;
uniform vec3 coal_dark : source_color = vec3(0.012, 0.011, 0.016);
uniform vec3 coal_light : source_color = vec3(0.07, 0.065, 0.1);
// Small glints in the crust (bluish, like wet coal).
uniform vec3 glint_color : source_color = vec3(0.22, 0.24, 0.42);

varying vec3 rest_pos;
varying float cover;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += noise(p) * weight;
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		weight *= 0.5;
	}
	return sum / 0.9375;
}

// Where the crust is: patches that spread as amount grows (all of it at amount 0.95).
float coverage(vec3 p) {
	float patch = fbm(p * 0.6 + vec3(5.0));
	float edge = mix(0.78, 0.2, clamp(amount / 0.95, 0.0, 1.0));
	return smoothstep(edge - 0.04, edge + 0.04, patch);
}

void vertex() {
	rest_pos = (to_rest * vec4(VERTEX, 1.0)).xyz;
	cover = coverage(rest_pos);
	float lump = fbm(rest_pos * lump_scale);
	// A thin base layer over the armor, plus round lumps.
	VERTEX += NORMAL * (0.015 + lump * lump * lump_height * amount) * cover * push;
}

void fragment() {
	if (coverage(rest_pos) < 0.5) {
		discard;
	}
	float rock = fbm(rest_pos * grain_scale);
	float fine = noise(rest_pos * grain_scale * 4.0);
	// Screen-space bump from the rock grain height.
	float height = rock + fine * 0.35;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(height);
	float dhdy = dFdy(height);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grain_bump * grad);

	vec3 color = mix(coal_dark, coal_light, smoothstep(0.35, 0.8, rock));
	float glint = smoothstep(0.78, 0.92, fine) * smoothstep(0.4, 0.7, rock);
	ALBEDO = mix(color, glint_color, glint * 0.6);
	ROUGHNESS = mix(0.55, 0.18, glint) - rock * 0.15;
	METALLIC = 0.35;
	SPECULAR = 0.7;
}
