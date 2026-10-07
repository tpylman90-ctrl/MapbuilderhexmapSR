shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float macro_scale = 0.85;
uniform float detail_scale = 9.0;

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
	float flecks = value_noise(world_position * detail_scale * 3.0);
	float mottling = 0.91 + broad * 0.10 + detail * 0.07 + flecks * 0.025;

	ALBEDO = COLOR.rgb * mottling;
}
