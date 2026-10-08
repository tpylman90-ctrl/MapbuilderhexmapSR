shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec3 deep_water : source_color = vec3(0.035, 0.21, 0.29);
uniform vec3 shallow_water : source_color = vec3(0.085, 0.37, 0.43);
uniform vec2 flow_direction = vec2(0.707107, 0.707107);
uniform float flow_speed = 0.92;
uniform float wave_height : hint_range(0.0, 0.08) = 0.032;

varying vec3 world_position;
varying float edge_factor;
varying float wave_value;

void vertex() {
	vec2 uv_hex = (UV - vec2(0.5)) * 2.0;
	float edge = max(abs(uv_hex.y), abs(uv_hex.x) * 0.8660254 + abs(uv_hex.y) * 0.5);
	float shoreline_fade = 1.0 - smoothstep(0.78, 0.99, edge);

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;
	vec2 flow = normalize(flow_direction);
	vec2 cross_flow = vec2(-flow.y, flow.x);
	vec2 wave_vector_a = flow * 1.7 + cross_flow * 0.24;
	vec2 wave_vector_b = flow * 1.28 - cross_flow * 0.56;
	float phase_a = dot(p, wave_vector_a) * 2.0 - TIME * flow_speed;
	float phase_b = dot(p, wave_vector_b) * 3.1 - TIME * flow_speed * 0.76;
	float wave = sin(phase_a) * 0.66 + sin(phase_b) * 0.34;
	VERTEX.y += wave * wave_height * shoreline_fade;

	float dhdx = wave_height * shoreline_fade * (cos(phase_a) * 0.66 * wave_vector_a.x * 2.0 + cos(phase_b) * 0.34 * wave_vector_b.x * 3.1);
	float dhdz = wave_height * shoreline_fade * (cos(phase_a) * 0.66 * wave_vector_a.y * 2.0 + cos(phase_b) * 0.34 * wave_vector_b.y * 3.1);
	NORMAL = normalize(vec3(-dhdx, 1.0, -dhdz));

	world_position = world;
	edge_factor = edge;
	wave_value = wave;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 flow = normalize(flow_direction);
	vec2 cross_flow = vec2(-flow.y, flow.x);
	vec2 wave_vector_a = flow * 1.7 + cross_flow * 0.24;
	vec2 wave_vector_b = flow * 1.28 - cross_flow * 0.56;
	float broad_ripple = sin(dot(p, wave_vector_a) * 2.0 - TIME * flow_speed);
	float crossing_ripple = sin(dot(p, wave_vector_b) * 3.1 - TIME * flow_speed * 0.76);
	float short_ripple = sin(dot(p, flow * 4.2 - cross_flow * 2.6) * 2.1 - TIME * flow_speed * 1.15);
	float ripple = 0.5 + 0.24 * broad_ripple + 0.17 * crossing_ripple + 0.09 * short_ripple;
	vec2 drifting_p = p - flow * TIME * flow_speed * 0.45;
	float fine_glint = sin(dot(drifting_p, flow * 2.6 + cross_flow * 1.3) * 1.6) *
		sin(dot(drifting_p, flow * 1.4 - cross_flow * 1.8) * 1.9);
	float glint = smoothstep(0.62, 0.96, fine_glint) * 0.075;
	float shoreline = 1.0 - smoothstep(0.84, 0.995, edge_factor);
	float crest = smoothstep(0.42, 0.92, wave_value);

	float surface_tone = clamp(ripple * 0.82 + crest * 0.18, 0.0, 1.0);
	ALBEDO = mix(deep_water, shallow_water, surface_tone);
	ALBEDO += vec3(glint * 0.34, glint * 0.52, glint * 0.48);
	ROUGHNESS = mix(0.34, 0.24, shoreline);
	SPECULAR = 0.48;
}
