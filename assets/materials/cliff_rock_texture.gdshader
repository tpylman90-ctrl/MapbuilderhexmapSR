shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform float macro_scale = 0.62;
uniform float detail_scale = 2.8;
uniform float grain_scale = 8.0;
uniform float texture_strength = 0.24;
uniform float strata_strength = 0.16;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);

	float c000 = hash3(cell + vec3(0.0, 0.0, 0.0));
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
	float broad = value_noise(world_position * macro_scale);
	float detail = value_noise(world_position * detail_scale);
	float grain = value_noise(world_position * grain_scale);
	// UV Y follows cliff height while UV X follows the wall, so stretched noise
	// reads as long mineral bands instead of mottled noise on a vertical face.
	float strata = value_noise(vec3(UV.x * 3.4, UV.y * 0.24, 0.0));

	float broad_tone = mix(1.0 - texture_strength, 1.0 + texture_strength, broad);
	float detail_tone = mix(0.92, 1.08, detail);
	float grain_tone = mix(0.97, 1.03, grain);
	vec3 stone_tint = mix(vec3(0.78, 0.82, 0.79), vec3(1.04, 1.00, 0.92), broad);
	float strata_tone = mix(1.0 - strata_strength, 1.0 + strata_strength, strata);

	ALBEDO = COLOR.rgb * stone_tint * broad_tone * detail_tone * grain_tone * strata_tone;
	ROUGHNESS = clamp(0.88 + (detail - 0.5) * 0.12, 0.78, 0.96);
}
