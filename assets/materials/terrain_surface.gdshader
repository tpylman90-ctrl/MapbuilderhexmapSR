shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec3 cliff_color : source_color = vec3(0.48, 0.43, 0.35);
uniform vec3 water_deep : source_color = vec3(0.018, 0.105, 0.155);
uniform vec3 water_light : source_color = vec3(0.055, 0.255, 0.315);
uniform vec3 water_edge : source_color = vec3(0.52, 0.70, 0.62);
uniform float surface_detail : hint_range(0.0, 1.0) = 0.88;
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.68;
uniform float blend_sharpness : hint_range(0.0, 0.2) = 0.06;
uniform vec2 water_flow_direction = vec2(0.707107, 0.707107);

varying vec3 world_position_v;
varying vec3 world_normal_v;
varying vec3 terrain_color_v;

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

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 c = COLOR.rgb;
	float mean_color = (c.r + c.g + c.b) / 3.0;
	float warm = smoothstep(0.035, 0.20, c.r - c.b);
	float pale = smoothstep(0.73, 0.86, mean_color);
	float blue_water = smoothstep(0.10, 0.28, c.b - c.r);
	float sand_mask = warm * (1.0 - pale) * smoothstep(0.52, 0.68, mean_color) * (1.0 - blue_water);
	float snow_mask = pale * (1.0 - blue_water);
	float ash_mask = (1.0 - smoothstep(0.28, 0.36, mean_color)) * (1.0 - blue_water);
	float lava_mask = smoothstep(0.20, 0.40, c.r - c.g) * smoothstep(0.34, 0.48, mean_color);
	float stone_mask = smoothstep(0.53, 0.63, mean_color) * (1.0 - smoothstep(0.025, 0.10, abs(c.r - c.g))) * (1.0 - snow_mask) * (1.0 - blue_water);
	float mud_mask = (1.0 - smoothstep(0.38, 0.45, mean_color)) * (1.0 - smoothstep(0.02, 0.095, abs(c.r - c.g))) * (1.0 - blue_water);
	float broad_noise = value_noise(vec3(p.x * 0.48, 3.0, p.z * 0.48));
	float dune_wave = sin(dot(p.xz, normalize(vec2(0.84, 0.54))) * 4.8 + broad_noise * 5.4)
		+ 0.36 * sin(dot(p.xz, normalize(vec2(-0.32, 0.95))) * 8.2 + broad_noise * 3.0);
	float snow_drift = sin(dot(p.xz, normalize(vec2(0.63, 0.77))) * 2.25 + broad_noise * 2.2)
		+ 0.28 * sin(dot(p.xz, normalize(vec2(-0.88, 0.47))) * 4.1 + broad_noise * 3.4);
	float mud_ruts = sin(p.x * 7.0 + sin(p.z * 2.5) * 2.0) * 0.25;
	float ash_ripples = sin(dot(p.xz, normalize(vec2(0.82, 0.57))) * 3.8 + broad_noise * 4.0);
	float lava_pulse = sin(dot(p.xz, normalize(vec2(0.46, 0.89))) * 3.4 - TIME * 0.65 + broad_noise * 2.5);
	float rock_roughness = broad_noise - 0.5;
	VERTEX.y += surface_detail * (sand_mask * dune_wave * 0.040 + snow_mask * snow_drift * 0.022 + mud_mask * mud_ruts * 0.012 + stone_mask * rock_roughness * 0.028 + ash_mask * ash_ripples * 0.009 + lava_mask * lava_pulse * 0.018);
	world_position_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal_v = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	terrain_color_v = c;
}

void fragment() {
	vec3 world_position = world_position_v;
	vec3 world_normal = normalize(world_normal_v);
	float slope = dot(world_normal, vec3(0.0, 1.0, 0.0));
	float top_blend = smoothstep(slope_threshold - blend_sharpness, slope_threshold + blend_sharpness, slope);
	float detail = surface_detail;
	vec3 tint = terrain_color_v;

	// World-aligned noise gives connected tiles continuous soil and mineral patterns.
	float broad = value_noise(world_position * vec3(0.34, 0.18, 0.34));
	float patch = value_noise(world_position * vec3(1.25, 2.1, 1.25));
	float medium = value_noise(world_position * vec3(5.0, 3.4, 5.0));
	float fine = value_noise(world_position * vec3(19.0, 14.0, 19.0));
	float grain = value_noise(world_position * vec3(63.0, 42.0, 63.0));
	float mean_color = (tint.r + tint.g + tint.b) / 3.0;
	float warm = smoothstep(0.035, 0.20, tint.r - tint.b);
	float grass_mask = smoothstep(0.17, 0.30, tint.g - tint.r) * top_blend;
	float water_mask = smoothstep(0.10, 0.28, tint.b - tint.r) * top_blend;
	float snow_mask = smoothstep(0.70, 0.84, mean_color) * (1.0 - water_mask) * top_blend;
	float sand_mask = warm * smoothstep(0.52, 0.68, mean_color) * (1.0 - snow_mask) * (1.0 - water_mask) * top_blend;
	float stone_mask = smoothstep(0.53, 0.63, mean_color) * (1.0 - smoothstep(0.025, 0.10, abs(tint.r - tint.g))) * (1.0 - snow_mask) * (1.0 - water_mask) * top_blend;
	float mud_mask = (1.0 - smoothstep(0.38, 0.45, mean_color)) * (1.0 - smoothstep(0.02, 0.095, abs(tint.r - tint.g))) * smoothstep(0.35, 0.40, mean_color) * (1.0 - grass_mask) * (1.0 - water_mask) * top_blend;
	float road_mask = smoothstep(0.055, 0.15, tint.r - tint.g) * (1.0 - smoothstep(0.48, 0.56, mean_color)) * (1.0 - sand_mask) * (1.0 - water_mask) * top_blend;
	float dirt_mask = warm * smoothstep(0.43, 0.51, mean_color) * (1.0 - sand_mask) * (1.0 - road_mask) * (1.0 - water_mask) * top_blend;
	float ash_mask = (1.0 - smoothstep(0.28, 0.36, mean_color)) * (1.0 - water_mask) * top_blend;
	float lava_mask = smoothstep(0.20, 0.40, tint.r - tint.g) * smoothstep(0.34, 0.48, mean_color) * (1.0 - water_mask) * top_blend;

	vec3 grass = tint * mix(0.77, 1.10, broad * 0.52 + patch * 0.48);
	float grass_speckle = smoothstep(0.71, 0.89, grain);
	grass = mix(grass, grass * vec3(0.59, 0.67, 0.43), grass_speckle * (0.26 + detail * 0.18));

	float soil_mottle = mix(0.64, 1.23, medium * 0.66 + fine * 0.34);
	float soil_grit = smoothstep(0.68, 0.91, grain);
	vec3 dirt = tint * soil_mottle * (1.0 - soil_grit * 0.16);
	float ash_cloud = value_noise(world_position * vec3(0.8, 0.25, 0.8) + vec3(TIME * 0.025, 0.0, -TIME * 0.018));
	float ash_grain = value_noise(world_position * vec3(24.0, 10.0, 24.0));
	float ash_ridge = 0.5 + 0.5 * sin(dot(world_position.xz, normalize(vec2(0.82, 0.57))) * 3.8 + (broad - 0.5) * 4.0);
	vec3 ash_surface = mix(vec3(0.12, 0.115, 0.105), vec3(0.34, 0.315, 0.28), ash_cloud * 0.65 + ash_ridge * 0.35);
	ash_surface *= mix(0.82, 1.12, ash_grain);
	float ash_specks = smoothstep(0.86, 0.97, grain);
	ash_surface += vec3(0.08, 0.075, 0.065) * ash_specks * detail;
	float lava_flow_field = value_noise(vec3(world_position.x * 2.2 + TIME * 0.10, 1.7, world_position.z * 2.2 - TIME * 0.08));
	float lava_phase = dot(world_position.xz, normalize(vec2(0.46, 0.89))) * 4.2 + lava_flow_field * 5.0 - TIME * 0.72;
	float molten_channel = 1.0 - smoothstep(0.05, 0.42, abs(sin(lava_phase)));
	float cooling_crust = smoothstep(0.60, 0.82, value_noise(world_position * vec3(3.1, 1.3, 3.1) + TIME * 0.04));
	vec3 lava_surface = mix(vec3(0.105, 0.009, 0.002), vec3(0.92, 0.105, 0.006), molten_channel * 0.88 + lava_flow_field * 0.12);
	lava_surface = mix(lava_surface, vec3(0.035, 0.018, 0.014), cooling_crust * (1.0 - molten_channel) * 0.72);
	float stone_mottle = value_noise(world_position * vec3(4.8, 2.6, 4.8));
	float stone_grit = value_noise(world_position * vec3(31.0, 18.0, 31.0));
	float stone_fissure = smoothstep(0.87, 0.98, value_noise(world_position * vec3(17.0, 4.0, 17.0) + broad * 3.0));
	vec3 stone_surface = tint * mix(0.70, 1.20, stone_mottle * 0.72 + stone_grit * 0.28);
	stone_surface = mix(stone_surface, stone_surface * vec3(0.57, 0.61, 0.64), stone_fissure * detail * 0.56);
	stone_surface = mix(stone_surface, stone_surface * vec3(1.12, 1.10, 1.04), smoothstep(0.80, 0.94, stone_grit) * detail * 0.26);

	// Sand gets visible wind-carved ripple bands and bright granular crests.
	float dune_phase = dot(world_position.xz, normalize(vec2(0.84, 0.54))) * 4.8 + (broad - 0.5) * 5.0;
	float dunes = 0.5 + 0.5 * sin(dune_phase + sin(world_position.x * 1.4 + world_position.z * 0.9) * 0.8);
	float dune_ridge = smoothstep(0.69, 0.90, dunes);
	float sand_grit = smoothstep(0.60, 0.92, grain);
	vec3 sand = tint * mix(0.73, 1.16, 0.32 + dunes * 0.48 + fine * 0.20);
	sand = mix(sand, sand * vec3(1.10, 1.04, 0.88), dune_ridge * (0.25 + detail * 0.22));
	sand *= mix(0.93, 1.08, sand_grit * detail);

	// Snow is softly blue in hollows with broad rounded drifts and crystalline sparkle.
	float drift_phase = dot(world_position.xz, normalize(vec2(0.63, 0.77))) * 2.25 + (broad - 0.5) * 2.5;
	float drift = 0.5 + 0.5 * sin(drift_phase + sin(world_position.x * 0.7 - world_position.z * 0.55) * 0.8);
	float drift_shadow = 1.0 - smoothstep(0.12, 0.84, drift);
	float crystal = smoothstep(0.87, 0.98, grain) * smoothstep(0.48, 0.82, fine);
	vec3 snow = tint * mix(0.76, 1.08, drift * 0.56 + fine * 0.44);
	snow = mix(snow, snow * vec3(0.72, 0.85, 1.04), drift_shadow * 0.24);
	snow += vec3(0.045, 0.055, 0.065) * crystal * detail;

	// Mud reads wet, churned, and darker than ordinary soil.
	float rut_phase = world_position.x * 7.0 + sin(world_position.z * 2.5 + broad * 4.0) * 1.5;
	float rut = 0.5 + 0.5 * sin(rut_phase);
	float puddle = smoothstep(0.73, 0.91, patch) * smoothstep(0.60, 0.85, medium);
	vec3 mud = tint * mix(0.66, 1.16, medium * 0.62 + fine * 0.38);
	mud *= mix(0.72, 1.05, rut);
	mud = mix(mud, vec3(0.16, 0.20, 0.17), puddle * 0.44);

	float road_grit = mix(0.77, 1.10, fine * 0.62 + grain * 0.38);
	vec3 road = tint * road_grit;

	vec3 exposed_rock = cliff_color * mix(0.72, 1.19, broad * 0.60 + medium * 0.40);
	float rock_vein = smoothstep(0.89, 0.99, value_noise(world_position * vec3(22.0, 4.0, 22.0) + broad * 4.0));
	exposed_rock *= mix(0.76, 1.06, medium);
	exposed_rock = mix(exposed_rock, exposed_rock * vec3(0.64, 0.68, 0.71), rock_vein * detail * 0.35);

	vec3 top_surface = tint * mix(0.84, 1.12, broad * 0.54 + patch * 0.46);
	top_surface = mix(top_surface, grass, grass_mask * (0.72 + detail * 0.28));
	top_surface = mix(top_surface, dirt, dirt_mask * (0.70 + detail * 0.30));
	top_surface = mix(top_surface, ash_surface, ash_mask * (0.86 + detail * 0.14));
	top_surface = mix(top_surface, stone_surface, stone_mask * (0.78 + detail * 0.22));
	top_surface = mix(top_surface, sand, sand_mask * (0.80 + detail * 0.20));
	top_surface = mix(top_surface, snow, snow_mask * (0.80 + detail * 0.20));
	top_surface = mix(top_surface, mud, mud_mask * (0.80 + detail * 0.20));
	top_surface = mix(top_surface, road, road_mask * (0.74 + detail * 0.26));
	top_surface = mix(top_surface, lava_surface, lava_mask);

	vec2 flow = normalize(water_flow_direction);
	vec2 cross_flow = vec2(-flow.y, flow.x);
	vec2 secondary_flow = normalize(flow + cross_flow * 0.63);
	float wave_a = sin(dot(world_position.xz, flow) * 2.2 - TIME * 1.2);
	float wave_b = sin(dot(world_position.xz, secondary_flow) * 2.8 - TIME * 0.9);
	float wave_c = sin(dot(world_position.xz, cross_flow) * 4.4 - TIME * 1.45);
	float wave = 0.42 + 0.20 * wave_a + 0.18 * wave_b + 0.10 * wave_c;
	float glint = smoothstep(0.72, 0.96, wave_a * wave_b + wave_c * 0.25);
	vec3 water_surface = mix(water_deep, water_light, clamp(wave, 0.0, 1.0) * 0.76);
	water_surface += vec3(0.075, 0.12, 0.11) * glint;

	float shore_noise = value_noise(world_position * vec3(5.0, 2.0, 5.0) + vec3(TIME * 0.06, 0.0, -TIME * 0.04));
	float shore_band = (1.0 - smoothstep(0.055, 0.24, abs(water_mask - 0.5))) * smoothstep(0.18, 0.62, shore_noise * 0.72 + medium * 0.28);
	ALBEDO = mix(exposed_rock, top_surface, top_blend);
	ALBEDO = mix(ALBEDO, water_surface, water_mask);
	ALBEDO = mix(ALBEDO, water_edge, shore_band * 0.45);
	EMISSION = lava_surface * lava_mask * vec3(0.95, 0.17, 0.015);
	ROUGHNESS = mix(mix(0.92, 0.78, puddle * mud_mask), 0.22, water_mask);
	ROUGHNESS = mix(ROUGHNESS, mix(0.82, 0.33, molten_channel), lava_mask);
	SPECULAR = mix(0.18 + puddle * mud_mask * 0.20, 0.58, water_mask);
	SPECULAR = mix(SPECULAR, 0.42, lava_mask);

	float bump_height = (medium - 0.5) * 0.009 + (fine - 0.5) * 0.016 + (grain - 0.5) * 0.006;
	bump_height += (stone_mottle - 0.5) * stone_mask * 0.026 + (stone_fissure - 0.5) * stone_mask * 0.018;
	bump_height += (dunes - 0.5) * sand_mask * 0.036 + (drift - 0.5) * snow_mask * 0.024 + (rut - 0.5) * mud_mask * 0.018;
	bump_height += (ash_ridge - 0.5) * ash_mask * 0.018 + (molten_channel - 0.5) * lava_mask * 0.022;
	float bump_strength = (1.0 - water_mask) * top_blend * (0.70 + detail * 0.55);
	vec3 base_normal = normalize(NORMAL);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, base_normal);
	vec3 r2 = cross(base_normal, dpdx);
	float determinant = dot(dpdx, r1);
	vec3 bump_gradient = sign(determinant) * (dFdx(bump_height) * r1 + dFdy(bump_height) * r2);
	NORMAL = normalize(abs(determinant) * base_normal - bump_gradient * bump_strength);
}
