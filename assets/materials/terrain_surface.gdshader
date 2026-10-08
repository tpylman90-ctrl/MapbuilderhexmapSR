shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec3 cliff_color : source_color = vec3(0.62, 0.50, 0.34);
uniform vec3 water_deep : source_color = vec3(0.018, 0.20, 0.31);
uniform vec3 water_light : source_color = vec3(0.045, 0.46, 0.56);
uniform vec3 water_edge : source_color = vec3(0.34, 0.76, 0.70);
uniform float surface_detail : hint_range(0.0, 1.0) = 0.78;
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

	float broad = value_noise(world_position * vec3(0.72, 0.38, 0.72));
	float medium = value_noise(world_position * vec3(4.8, 2.7, 4.8));
	float fine = value_noise(world_position * vec3(16.0, 12.0, 16.0));
	float grass_mask = smoothstep(0.23, 0.36, COLOR.g - COLOR.b) * top_blend;
	float sand_mask = smoothstep(0.20, 0.30, COLOR.g - COLOR.b) * smoothstep(0.24, 0.44, COLOR.r - COLOR.b) * top_blend;
	float soil_mask = smoothstep(0.08, 0.21, COLOR.r - COLOR.g) * (1.0 - sand_mask) * top_blend;
	float water_mask = smoothstep(0.25, 0.43, COLOR.b - COLOR.r) * top_blend;

	vec3 top_base = COLOR.rgb * 0.68 * mix(0.91, 1.07, broad);
	float grass_patches = value_noise(world_position * vec3(2.4, 7.0, 2.4));
	float grass_grain = value_noise(world_position * vec3(22.0, 14.0, 22.0));
	float grass_fleck = smoothstep(0.70, 0.88, grass_grain);
	vec3 grass_surface = COLOR.rgb * mix(0.65, 0.86, grass_patches) * mix(0.92, 1.08, medium);
	grass_surface = mix(grass_surface, grass_surface * vec3(0.70, 0.84, 0.55), grass_fleck * 0.32);

	float soil_mottle = mix(0.75, 1.18, medium) * mix(0.90, 1.10, fine);
	float soil_ripple = 0.94 + 0.06 * sin((world_position.x * 8.0 + world_position.z * 4.5) + broad * 3.0);
	vec3 soil_surface = COLOR.rgb * soil_mottle * soil_ripple;
	float sand_ripple = 0.93 + 0.07 * sin(world_position.x * 12.0 + world_position.z * 4.0 + broad * 4.0);
	vec3 sand_surface = COLOR.rgb * mix(0.90, 1.08, fine) * sand_ripple;

	vec3 top_surface = top_base;
	top_surface = mix(top_surface, grass_surface, grass_mask * (0.42 + detail * 0.58));
	top_surface = mix(top_surface, soil_surface, soil_mask * (0.24 + detail * 0.50));
	top_surface = mix(top_surface, sand_surface, sand_mask * (0.30 + detail * 0.50));
	vec3 exposed_rock = cliff_color * mix(0.91, 1.09, broad);

	float wave_a = sin(world_position.x * 2.4 + world_position.z * 1.3 + TIME * 1.25);
	float wave_b = sin(world_position.z * 3.1 - world_position.x * 1.7 - TIME * 0.92);
	float wave = 0.5 + 0.25 * wave_a + 0.25 * wave_b;
	float glint = smoothstep(0.76, 0.96, sin((world_position.x + world_position.z) * 4.1 + TIME * 1.7) * sin((world_position.x - world_position.z) * 2.7 - TIME * 1.1));
	vec2 hex_uv = (UV - vec2(0.5)) * 2.0;
	float hex_edge = max(abs(hex_uv.y), abs(hex_uv.x) * 0.8660254 + abs(hex_uv.y) * 0.5);
	float shore = 1.0 - smoothstep(0.88, 0.985, hex_edge);
	vec3 water_surface = mix(water_deep, water_light, wave * 0.66);
	water_surface += vec3(0.12, 0.18, 0.12) * glint;
	water_surface = mix(water_surface, water_edge, (1.0 - shore) * 0.42);

	ALBEDO = mix(mix(exposed_rock, top_surface, top_blend), water_surface, water_mask);
	ROUGHNESS = mix(0.94 - detail * 0.10, 0.28, water_mask);
	SPECULAR = mix(0.16, 0.64, water_mask);
}
