shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform vec3 cliff_color : source_color = vec3(0.62, 0.50, 0.34);
uniform float rock_detail : hint_range(0.0, 1.0) = 0.90;
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

	// Broad stone color bands with smaller, world-aligned mineral variation.
	float broad = value_noise(world_position * vec3(0.42, 0.20, 0.42));
	float medium = value_noise(world_position * vec3(3.8, 1.8, 3.8));
	float grain = value_noise(world_position * vec3(16.0, 9.0, 16.0));
	float micro_grain = value_noise(world_position * vec3(52.0, 31.0, 52.0));
	float warp = value_noise(world_position * vec3(1.15, 0.56, 1.15));
	float fracture = value_noise(world_position * vec3(23.0, 3.4, 23.0) + vec3(warp * 3.0, 0.0, warp * 2.0));
	float strata_phase = world_position.y * 8.0 + (warp - 0.5) * 5.5 + (medium - 0.5) * 2.0;
	float strata = 1.0 - smoothstep(0.78, 0.97, abs(sin(strata_phase)));
	float vein = 1.0 - smoothstep(0.012, 0.060, abs(fracture - 0.49));
	float pocket = smoothstep(0.69, 0.83, medium) * (1.0 - smoothstep(0.86, 0.97, grain));
	float mineral = broad * 0.42 + medium * 0.36 + grain * 0.22;

	vec3 shadow_rock = cliff_color * vec3(0.58, 0.56, 0.51);
	vec3 sun_rock = cliff_color * vec3(1.16, 1.11, 1.02);
	vec3 rock = mix(shadow_rock, sun_rock, smoothstep(0.22, 0.78, mineral));
	rock *= mix(0.84, 1.13, broad * 0.48 + medium * 0.34 + grain * 0.18);
	rock = mix(rock, rock * vec3(0.68, 0.66, 0.60), strata * (0.10 + rock_detail * 0.20));
	rock = mix(rock, rock * vec3(0.56, 0.53, 0.47), vein * rock_detail * 0.34);
	rock = mix(rock, rock * vec3(0.76, 0.79, 0.75), pocket * rock_detail * 0.15);
	float fine_stone_grain = mix(0.94, 1.06, micro_grain);
	rock *= fine_stone_grain;

	vec3 upper_edge = COLOR.rgb * mix(0.90, 1.02, broad);
	ALBEDO = mix(rock, upper_edge, top_blend * 0.55);
	ROUGHNESS = mix(0.88, 0.99, grain);
}
