shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec3 cliff_color : source_color = vec3(0.62, 0.50, 0.34);
uniform vec3 water_deep : source_color = vec3(0.018, 0.20, 0.31);
uniform vec3 water_light : source_color = vec3(0.045, 0.46, 0.56);
uniform vec3 water_edge : source_color = vec3(0.34, 0.76, 0.70);
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

	float broad = value_noise(world_position * 0.72);
	float fine = value_noise(world_position * 5.5);
	float grass_mask = smoothstep(0.035, 0.19, COLOR.g - COLOR.b) * top_blend;
	float grain = mix(0.94, 1.07, broad) * mix(0.96, 1.04, fine);
	vec3 top_surface = COLOR.rgb * 0.66 * grain;
	vec3 exposed_rock = cliff_color * mix(0.93, 1.08, broad);

	float water_mask = smoothstep(0.25, 0.43, COLOR.b - COLOR.r) * top_blend;
	float wave_a = sin(world_position.x * 2.4 + world_position.z * 1.3 + TIME * 1.25);
	float wave_b = sin(world_position.z * 3.1 - world_position.x * 1.7 - TIME * 0.92);
	float wave = 0.5 + 0.25 * wave_a + 0.25 * wave_b;
	float glint = smoothstep(0.76, 0.96, sin((world_position.x + world_position.z) * 4.1 + TIME * 1.7) * sin((world_position.x - world_position.z) * 2.7 - TIME * 1.1));
	vec2 hex_uv = (UV - vec2(0.5)) * 2.0;
	float hex_edge = max(abs(hex_uv.y), abs(hex_uv.x) * 0.8660254 + abs(hex_uv.y) * 0.5);
	float shore = 1.0 - smoothstep(0.88, 0.985, hex_edge);
	vec3 water = mix(water_deep, water_light, wave * 0.66);
	water += vec3(0.12, 0.18, 0.12) * glint;
	water = mix(water, water_edge, (1.0 - shore) * 0.42);

	ALBEDO = mix(mix(exposed_rock, top_surface, top_blend), water, water_mask);
	ROUGHNESS = mix(0.93, 0.28, water_mask);
	SPECULAR = mix(0.16, 0.64, water_mask);
}
