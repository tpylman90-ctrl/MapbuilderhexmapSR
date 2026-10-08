shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec3 cliff_color : source_color = vec3(0.62, 0.50, 0.34);
uniform vec3 water_deep : source_color = vec3(0.028, 0.19, 0.27);
uniform vec3 water_light : source_color = vec3(0.075, 0.34, 0.39);
uniform vec3 water_edge : source_color = vec3(0.34, 0.68, 0.64);
uniform float surface_detail : hint_range(0.0, 1.0) = 0.88;
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.68;
uniform float blend_sharpness : hint_range(0.0, 0.2) = 0.06;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float c000 = hash3(cell);
	float c100 = hash3(cell + vec3(1.0, 0.0, 0.0));
	float c010 = hash3(cell + vec3(0.0, 1.0, 0.0));
	float c110 = hash3(cell + vec3(1.0, 1.0, 0.0));
	float c001 = hash3(cell + vec3(0.0, 0.0, 1.0));
	float c101 = hash3(cell + vec3(1.0, 0.0, 1.0));
	float c011 = hash3(cell + vec3(0.0, 1.0, 1.0));
	float c111 = hash3(cell + vec3(1.0, 1.0, 1.0));
	float low_plane = mix(mix(c000, c100, local.x), mix(c010, c110, local.x), local.y);
	float high_plane = mix(mix(c001, c101, local.x), mix(c011, c111, local.x), local.y);
	return mix(low_plane, high_plane, local.z);
}

void fragment() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = dot(world_normal, vec3(0.0, 1.0, 0.0));
	float top_blend = smoothstep(slope_threshold - blend_sharpness, slope_threshold + blend_sharpness, slope);
	float detail = surface_detail;

	// World-space noise keeps the material continuous across hex boundaries.
	float broad = value_noise(world_position * vec3(0.42, 0.24, 0.42));
	float patch = value_noise(world_position * vec3(1.6, 2.3, 1.6));
	float medium = value_noise(world_position * vec3(6.5, 4.0, 6.5));
	float fine = value_noise(world_position * vec3(24.0, 16.0, 24.0));
	float grain = value_noise(world_position * vec3(61.0, 36.0, 61.0));

	float grass_mask = smoothstep(0.23, 0.36, COLOR.g - COLOR.b) * top_blend;
	float sand_mask = smoothstep(0.20, 0.30, COLOR.g - COLOR.b) * smoothstep(0.24, 0.44, COLOR.r - COLOR.b) * top_blend;
	float soil_mask = smoothstep(0.08, 0.21, COLOR.r - COLOR.g) * (1.0 - sand_mask) * top_blend;
	float water_mask = smoothstep(0.25, 0.43, COLOR.b - COLOR.r) * top_blend;

	float macro_tone = mix(0.82, 1.12, broad * 0.68 + patch * 0.32);
	float top_grain = mix(0.90, 1.10, medium * 0.64 + fine * 0.36);
	vec3 top_surface = COLOR.rgb * 0.82 * macro_tone * top_grain;

	// Grass: subtle growth patches, darker damp flecks, and fine soil grain.
	float grass_patch = value_noise(world_position * vec3(2.8, 4.0, 2.8));
	float grass_fleck = smoothstep(0.70, 0.89, grain);
	float grass_variation = mix(0.84, 1.10, grass_patch) * mix(0.94, 1.06, fine);
	vec3 grass_surface = COLOR.rgb * 0.80 * grass_variation;
	grass_surface = mix(grass_surface, grass_surface * vec3(0.68, 0.78, 0.54), grass_fleck * 0.30);

	// Soil and sand read as granular ground instead of smooth color fields.
	float soil_mottle = mix(0.78, 1.17, medium * 0.72 + fine * 0.28);
	float soil_grit = smoothstep(0.73, 0.91, grain) * 0.15;
	vec3 soil_surface = COLOR.rgb * soil_mottle * (1.0 - soil_grit);
	float sand_grain = mix(0.84, 1.13, fine * 0.72 + grain * 0.28);
	float sand_ripple = 0.96 + 0.04 * sin(world_position.x * 8.0 + world_position.z * 5.0 + patch * 4.0);
	vec3 sand_surface = COLOR.rgb * sand_grain * sand_ripple;

	top_surface = mix(top_surface, grass_surface, grass_mask * (0.55 + detail * 0.45));
	top_surface = mix(top_surface, soil_surface, soil_mask * (0.50 + detail * 0.50));
	top_surface = mix(top_surface, sand_surface, sand_mask * (0.50 + detail * 0.50));
	vec3 exposed_rock = cliff_color * mix(0.78, 1.12, broad * 0.65 + medium * 0.35);

	// Intersecting wave trains create motion in multiple directions.
	float wave_a = sin(world_position.x * 2.2 + world_position.z * 1.4 + TIME * 1.2);
	float wave_b = sin(world_position.z * 2.8 - world_position.x * 1.8 - TIME * 0.9);
	float wave_c = sin((world_position.x + world_position.z) * 4.4 - TIME * 1.45);
	float wave = 0.42 + 0.20 * wave_a + 0.18 * wave_b + 0.10 * wave_c;
	float glint = smoothstep(0.72, 0.96, wave_a * wave_b + wave_c * 0.25);
	vec2 hex_uv = (UV - vec2(0.5)) * 2.0;
	float hex_edge = max(abs(hex_uv.y), abs(hex_uv.x) * 0.8660254 + abs(hex_uv.y) * 0.5);
	float shore = 1.0 - smoothstep(0.88, 0.985, hex_edge);
	vec3 water_surface = mix(water_deep, water_light, clamp(wave, 0.0, 1.0) * 0.72);
	water_surface += vec3(0.08, 0.13, 0.12) * glint;
	water_surface = mix(water_surface, water_edge, (1.0 - shore) * 0.32);

	ALBEDO = mix(mix(exposed_rock, top_surface, top_blend), water_surface, water_mask);
	ROUGHNESS = mix(0.90 - detail * 0.05 + fine * 0.04, 0.26, water_mask);
	SPECULAR = mix(0.20, 0.58, water_mask);

	// Fine procedural height variation drives a real lighting normal, not only color.
	float bump_height = (medium - 0.5) * 0.008 + (fine - 0.5) * 0.014 + (grain - 0.5) * 0.005;
	float bump_strength = (1.0 - water_mask) * top_blend * (0.72 + detail * 0.48);
	vec3 base_normal = normalize(NORMAL);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, base_normal);
	vec3 r2 = cross(base_normal, dpdx);
	float determinant = dot(dpdx, r1);
	vec3 bump_gradient = sign(determinant) * (dFdx(bump_height) * r1 + dFdy(bump_height) * r2);
	NORMAL = normalize(abs(determinant) * base_normal - bump_gradient * bump_strength);
}
