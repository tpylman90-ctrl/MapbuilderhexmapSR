shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec2 flow_direction = vec2(0.707107, 0.707107);
uniform vec3 foam_tint : source_color = vec3(0.57, 0.88, 0.79);

varying float flow_along_edge;

void vertex() {
	vec3 edge_tangent = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	vec2 tangent_xz = edge_tangent.xz;
	flow_along_edge = dot(normalize(flow_direction), tangent_xz / max(length(tangent_xz), 0.001));
}

void fragment() {
	float along = UV.x;
	float drift = TIME * flow_along_edge * 2.3;
	float broad_foam = sin(along * 31.0 - drift + sin(along * 13.0) * 0.8);
	float small_foam = sin(along * 67.0 - drift * 1.35 + sin(along * 19.0) * 1.1);
	float broken_wave = smoothstep(-0.42, 0.62, broad_foam) * smoothstep(-0.58, 0.58, small_foam);
	float across = smoothstep(0.02, 0.22, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
	ALBEDO = foam_tint * (0.82 + 0.18 * broken_wave);
	ALPHA = across * (0.08 + 0.54 * broken_wave);
}
