shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform vec4 base_color : source_color = vec4(0.45, 0.38, 0.28, 1.0);
uniform int surface_style = 0; // 0 stone, 1 timber, 2 foliage, 3 roof, 4 metal
uniform float detail_strength : hint_range(0.0, 1.0) = 0.82;

varying vec3 world_position;
varying vec3 world_normal;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1,0,0)), f.x),
		mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), f.x),
		mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float tri_noise(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(normalize(n)), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	return noise3(p.yzx * scale) * w.x + noise3(p.zxy * scale) * w.y + noise3(p.xyz * scale) * w.z;
}

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_position = wp.xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 p = world_position;
	vec3 n = normalize(world_normal);
	float broad = tri_noise(p, n, 2.8);
	float fine = tri_noise(p, n, 17.0);
	float grain = tri_noise(p, n, 46.0);
	float pattern = 0.5;
	float rough = 0.88;

	if (surface_style == 0) { // cut stone: mottled mineral flecks, courses, occasional hairline joints
		float course = smoothstep(0.47, 0.51, abs(fract((p.y + broad * 0.07) * 2.1) - 0.5));
		float fleck = smoothstep(0.68, 0.90, fine);
		pattern = 0.74 + (broad - 0.5) * 0.30 + (fine - 0.5) * 0.22 + fleck * 0.10 - course * 0.08;
		rough = 0.91;
	} else if (surface_style == 1) { // timber: long grain and dark seams
		float g = noise3(vec3(p.x * 3.0 + noise3(p * 4.0), p.y * 31.0, p.z * 3.0));
		float seam = smoothstep(0.47, 0.50, abs(fract(p.y * 4.0 + broad * 0.12) - 0.5));
		pattern = 0.69 + (g - 0.5) * 0.34 + (broad - 0.5) * 0.16 - seam * 0.10;
		rough = 0.86;
	} else if (surface_style == 2) { // foliage: overlapping tonal clusters
		float clusters = smoothstep(0.30, 0.72, tri_noise(p, n, 5.2));
		pattern = 0.62 + clusters * 0.34 + (fine - 0.5) * 0.12;
		rough = 0.94;
	} else if (surface_style == 3) { // fired roof tile / thatch: repeated shallow rows
		float row = smoothstep(0.46, 0.50, abs(fract((p.y + p.x * 0.10) * 5.0 + broad * 0.06) - 0.5));
		float tile = smoothstep(0.46, 0.50, abs(fract(p.x * 3.2) - 0.5));
		pattern = 0.75 + (broad - 0.5) * 0.24 + (fine - 0.5) * 0.12 - row * 0.10 - tile * 0.055;
		rough = 0.83;
	} else { // worked metal: brushed anisotropic streaks
		float brush = noise3(vec3(p.x * 48.0, p.y * 5.0, p.z * 9.0));
		pattern = 0.82 + (brush - 0.5) * 0.10 + (broad - 0.5) * 0.10;
		rough = 0.48;
	}

	float value = clamp(pattern * (0.94 + fine * 0.10) * detail_strength + (1.0 - detail_strength), 0.0, 1.15);
	ALBEDO = base_color.rgb * value;
	ROUGHNESS = rough;
	SPECULAR = surface_style == 4 ? 0.42 : 0.18;
}
