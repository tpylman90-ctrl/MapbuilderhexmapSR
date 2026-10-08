shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform vec3 cliff_color : source_color = vec3(0.62, 0.50, 0.34);
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

	// Layered triplanar-style world noise gives the flat rock planes a mineral surface.
	float broad = value_noise(world_position * vec3(0.72, 0.38, 0.72));
	float medium = value_noise(world_position * vec3(3.4, 2.0, 3.4));
	float grain = value_noise(world_position * vec3(13.0, 8.0, 13.0));
	float warp = value_noise(world_position * vec3(1.2, 0.7, 1.2));
	float strata_wave = sin(world_position.y * 6.0 + (warp - 0.5) * 3.0);
	float strata = 1.0 - smoothstep(0.74, 0.94, abs(strata_wave));
	float mineral = broad * 0.48 + medium * 0.34 + grain * 0.18;
	vec3 dark_tan = cliff_color * 0.70;
	vec3 light_tan = cliff_color * 1.26;
	vec3 mineral_color = mix(dark_tan, light_tan, smoothstep(0.22, 0.78, mineral));
	vec3 rock = mix(mineral_color, COLOR.rgb, 0.30);
	rock *= 0.94 + grain * 0.12;
	rock *= 1.0 - strata * 0.12;
	vec3 upper_edge = COLOR.rgb * mix(0.96, 1.04, broad);
	ALBEDO = mix(rock, upper_edge, top_blend * 0.65);
	ROUGHNESS = mix(0.88, 0.98, grain);
}
