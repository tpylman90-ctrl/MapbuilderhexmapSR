shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.52, 0.50, 0.45, 1.0);
uniform bool masonry = true;

varying vec3 castle_world_position;
varying vec3 castle_world_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash2(cell);
	float b = hash2(cell + vec2(1.0, 0.0));
	float c = hash2(cell + vec2(0.0, 1.0));
	float d = hash2(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

void vertex() {
	castle_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	castle_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal = abs(normalize(castle_world_normal));
	vec3 world_position = castle_world_position;
	vec3 base = base_color.rgb;

	if (masonry) {
		vec2 plane = world_position.xz;
		if (normal.x > normal.y && normal.x > normal.z) {
			plane = world_position.zy;
		} else if (normal.y > normal.x && normal.y > normal.z) {
			plane = world_position.xz;
		} else {
			plane = world_position.xy;
		}

		// Mortar courses are staggered and scaled to individual hand-laid blocks.
		vec2 brick_uv = plane / vec2(0.48, 0.24);
		float row = floor(brick_uv.y);
		brick_uv.x += mod(row, 2.0) * 0.5;
		vec2 brick_id = floor(brick_uv);
		vec2 local = fract(brick_uv);
		float mortar_gap = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
		float mortar_mask = 1.0 - smoothstep(0.035, 0.080, mortar_gap);
		float block_tone = hash2(brick_id);
		float weathering = value_noise(world_position.xz * 3.7 + world_position.xy * 1.2);
		vec3 block_color = base * mix(0.78, 1.12, block_tone);
		block_color *= mix(0.91, 1.06, weathering);
		vec3 mortar_color = base * vec3(0.46, 0.44, 0.40);
		ALBEDO = mix(block_color, mortar_color, mortar_mask);
	} else {
		float grain = value_noise(world_position.xz * 7.0 + world_position.xy * 4.0);
		ALBEDO = base * mix(0.91, 1.08, grain);
	}

	ROUGHNESS = 0.94;
}
