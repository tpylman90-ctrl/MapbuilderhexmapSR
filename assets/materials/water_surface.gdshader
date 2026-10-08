shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec3 deep_water : source_color = vec3(0.025, 0.20, 0.29);
uniform vec3 shallow_water : source_color = vec3(0.07, 0.43, 0.48);
uniform vec3 foam_color : source_color = vec3(0.52, 0.76, 0.60);
uniform float wave_height : hint_range(0.0, 0.08) = 0.026;

varying vec3 world_position;
varying float edge_factor;
varying float wave_value;

void vertex() {
	vec2 uv_hex = (UV - vec2(0.5)) * 2.0;
	float edge = max(abs(uv_hex.y), abs(uv_hex.x) * 0.8660254 + abs(uv_hex.y) * 0.5);
	float shoreline_fade = 1.0 - smoothstep(0.78, 0.99, edge);

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;
	float phase_a = dot(p, vec2(0.82, 0.55)) * 2.0 + TIME * 1.15;
	float phase_b = dot(p, vec2(-0.38, 0.92)) * 3.1 - TIME * 0.82;
	float wave = sin(phase_a) * 0.66 + sin(phase_b) * 0.34;
	VERTEX.y += wave * wave_height * shoreline_fade;

	float dhdx = wave_height * shoreline_fade * (cos(phase_a) * 1.0824 - cos(phase_b) * 0.4013);
	float dhdz = wave_height * shoreline_fade * (cos(phase_a) * 0.726 - cos(phase_b) * 0.964);
	NORMAL = normalize(vec3(-dhdx, 1.0, -dhdz));

	world_position = world;
	edge_factor = edge;
	wave_value = wave;
}

void fragment() {
	vec2 p = world_position.xz;
	float broad_ripple = sin(dot(p, vec2(0.82, 0.55)) * 2.0 + TIME * 1.15);
	float crossing_ripple = sin(dot(p, vec2(-0.38, 0.92)) * 3.1 - TIME * 0.82);
	float ripple = 0.5 + 0.30 * broad_ripple + 0.20 * crossing_ripple;
	float fine_glint = sin(dot(p, vec2(1.9, -1.3)) * 4.2 + TIME * 1.7) *
		sin(dot(p, vec2(1.1, 1.8)) * 3.6 - TIME * 1.25);
	float glint = smoothstep(0.58, 0.94, fine_glint) * 0.10;
	float shoreline = 1.0 - smoothstep(0.84, 0.995, edge_factor);
	float foam_band = smoothstep(0.77, 0.86, edge_factor) * (1.0 - smoothstep(0.94, 1.0, edge_factor));
	float crest = smoothstep(0.42, 0.92, wave_value);

	ALBEDO = mix(deep_water, shallow_water, clamp(ripple * 0.85 + crest * 0.15, 0.0, 1.0));
	ALBEDO += vec3(glint * 0.32, glint * 0.52, glint * 0.46);
	ALBEDO = mix(ALBEDO, foam_color, foam_band * (0.16 + 0.20 * crest));
	ROUGHNESS = mix(0.29, 0.22, shoreline);
	SPECULAR = 0.48;
}
