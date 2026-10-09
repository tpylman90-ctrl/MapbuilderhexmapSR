class_name HexBoardView
extends Node3D

const CAP_HEIGHT: float = 0.18
const EDGE_RADIUS: float = HexGrid.HEX_RADIUS
const STEP_HEIGHT: float = HexGrid.HEIGHT_PER_LEVEL
const GRASS_TUFTS_PER_HEX: int = 6
const SELECT_COLOR := Color("efcf78")

var data: HexGrid
var world_environment: WorldEnvironment
var grid_node: MeshInstance3D
var grass_instances: MultiMesh
var grass_node: MultiMeshInstance3D
var water_instances: MultiMesh
var water_node: MultiMeshInstance3D
var water_shader_material: ShaderMaterial
var water_subdivisions: int = 4
var water_flow_direction := Vector2(0.707107, 0.707107)
var shoreline_edges: Dictionary = {}
var _shoreline_rebuild_queued := false
var shoreline_node: MeshInstance3D
var shoreline_shader_material: ShaderMaterial
var _refreshing_all := false
var terrain_shader_material: ShaderMaterial
var cliff_shader_material: ShaderMaterial
var surface_detail_strength: float = 0.78
var cliff_detail_strength: float = 0.82
var outline_node: MeshInstance3D
var cliff_node: MeshInstance3D
var selection_node: MeshInstance3D
var selected_cell := Vector2i(-1, -1)
var corner_cells: Dictionary = {}
var displayed_elevations := PackedInt32Array()
var _surface_update_queued := false
var _surface_heights_dirty := false
var _surface_dirty_cells: Dictionary = {}
var cliff_noise := FastNoiseLite.new()
var cliff_blend_top_y := 0.0
var cliff_blend_color := Color.WHITE

func initialize(grid_data: HexGrid) -> void:
	data = grid_data
	cliff_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cliff_noise.frequency = 0.34
	cliff_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	cliff_noise.fractal_octaves = 2
	_build_backing()
	_build_tile_mesh()
	_build_selection_outline()
	refresh_all()

func _build_backing() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	# A restrained outdoor sky supplies a natural horizon and image-based ambient fill.
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("66808b")
	sky_material.sky_horizon_color = Color("d0d0b9")
	sky_material.ground_bottom_color = Color("384238")
	sky_material.ground_horizon_color = Color("919b7c")
	sky_material.sky_curve = 0.24
	sky_material.ground_curve = 0.20
	sky_material.sky_energy_multiplier = 0.82
	sky_material.ground_energy_multiplier = 0.62
	sky_material.use_debanding = true
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.43
	environment.tonemap_exposure = 0.86
	environment.fog_enabled = true
	environment.fog_light_color = Color("a9bdb1")
	environment.fog_light_energy = 0.66
	environment.fog_sky_affect = 0.14
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 48.0
	environment.fog_depth_end = 260.0
	environment.fog_depth_curve = 1.22
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.environment = environment
	world_environment = world
	add_child(world)

	var plane := PlaneMesh.new()
	plane.size = Vector2(125.0, 215.0)
	var backing := MeshInstance3D.new()
	backing.name = "DarkGridBacking"
	backing.mesh = plane
	# Keep the backing below the full editable elevation range so lowering terrain
	# never buries a tile under the background plane.
	backing.position.y = HexGrid.MIN_ELEVATION * STEP_HEIGHT - 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("18221b")
	material.roughness = 1.0
	backing.material_override = material
	add_child(backing)

func set_distant_haze(enabled: bool) -> void:
	if world_environment != null and world_environment.environment != null:
		world_environment.environment.fog_enabled = enabled

func _build_tile_mesh() -> void:
	grid_node = MeshInstance3D.new()
	grid_node.name = "ContinuousHexTerrain"
	terrain_shader_material = ShaderMaterial.new()
	terrain_shader_material.shader = load("res://assets/materials/terrain_surface.gdshader") as Shader
	terrain_shader_material.set_shader_parameter("surface_detail", surface_detail_strength)
	terrain_shader_material.set_shader_parameter("water_flow_direction", water_flow_direction)
	grid_node.material_override = terrain_shader_material
	add_child(grid_node)

	outline_node = MeshInstance3D.new()
	outline_node.name = "HexGridLinesOnTerrain"
	outline_node.visible = false
	var outline_material := StandardMaterial3D.new()
	outline_material.albedo_color = Color("536649")
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	outline_node.material_override = outline_material
	add_child(outline_node)

	_build_grass_instances()
	_build_water_instances()
	_build_shoreline_node()

func _add_terrain_vertex(surface: SurfaceTool, point: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.set_uv(Vector2(point.x, point.z) * 0.5)
	surface.add_vertex(point)

func _sample_base_cell(world_x: float, world_z: float) -> Vector2i:
	var cell := data.world_to_cell(world_x, world_z)
	if data.contains(cell):
		return cell
	var approximate_row := clampi(roundi(world_z / 1.5 + (HexGrid.ROWS - 1) * 0.5), 0, HexGrid.ROWS - 1)
	var best_cell := Vector2i.ZERO
	var best_distance := INF
	for row in range(maxi(0, approximate_row - 2), mini(HexGrid.ROWS, approximate_row + 3)):
		var row_offset := 0.5 if row % 2 == 1 else 0.0
		var approximate_column := roundi(world_x / sqrt(3.0) + (HexGrid.COLUMNS - 1) * 0.5 + 0.25 - row_offset)
		for column in range(maxi(0, approximate_column - 2), mini(HexGrid.COLUMNS, approximate_column + 3)):
			var candidate := Vector2i(column, row)
			var center := data.world_center(candidate)
			var distance := Vector2(world_x - center.x, world_z - center.z).length_squared()
			if distance < best_distance:
				best_distance = distance
				best_cell = candidate
	return best_cell

func _sample_terrain(world_x: float, world_z: float) -> Vector4:
	var base := _sample_base_cell(world_x, world_z)
	var axial := data.axial_coordinates(base)
	var sample_position := Vector2(world_x, world_z)
	var support_radius := 2.55
	var height_sum := 0.0
	var color_r := 0.0
	var color_g := 0.0
	var color_b := 0.0
	var total_weight := 0.0
	for dq in range(-2, 3):
		for dr in range(-2, 3):
			if maxi(absi(dq), maxi(absi(dr), absi(dq + dr))) > 2:
				continue
			var row := axial.y + dr
			var column := axial.x + dq + floori(float(row) * 0.5)
			var cell := Vector2i(column, row)
			if not data.contains(cell):
				continue
			var center := data.world_center(cell)
			var distance := sample_position.distance_to(Vector2(center.x, center.z))
			if distance >= support_radius:
				continue
			var falloff := 1.0 - (distance * distance) / (support_radius * support_radius)
			var weight := falloff * falloff * falloff
			var terrain := data.terrain_at(cell)
			var elevation := float(data.elevation_at(cell)) * STEP_HEIGHT + CAP_HEIGHT * 0.5
			if terrain == HexGrid.Terrain.WATER:
				elevation = CAP_HEIGHT * 0.5
			var tint: Color = HexGrid.TERRAIN_COLORS[terrain]
			height_sum += elevation * weight
			color_r += tint.r * weight
			color_g += tint.g * weight
			color_b += tint.b * weight
			total_weight += weight
	if total_weight <= 0.0001:
		var fallback := data.terrain_at(base)
		var tint: Color = HexGrid.TERRAIN_COLORS[fallback]
		return Vector4(float(data.elevation_at(base)) * STEP_HEIGHT + CAP_HEIGHT * 0.5, tint.r, tint.g, tint.b)
	return Vector4(height_sum / total_weight, color_r / total_weight, color_g / total_weight, color_b / total_weight)

func _add_sampled_terrain_vertex(surface: SurfaceTool, world_x: float, world_z: float, sample: Vector4) -> void:
	var point := Vector3(world_x, sample.x, world_z)
	_add_terrain_vertex(surface, point, Color(sample.y, sample.z, sample.w, 1.0))

func _rebuild_terrain_surface() -> void:
	if grid_node == null:
		return
	var minimum_x := INF
	var maximum_x := -INF
	var minimum_z := INF
	var maximum_z := -INF
	for row in range(HexGrid.ROWS):
		for column in range(HexGrid.COLUMNS):
			var center := data.world_center(Vector2i(column, row))
			minimum_x = minf(minimum_x, center.x)
			maximum_x = maxf(maximum_x, center.x)
			minimum_z = minf(minimum_z, center.z)
			maximum_z = maxf(maximum_z, center.z)
	var spacing := 0.5
	minimum_x -= 0.65
	maximum_x += 0.65
	minimum_z -= 0.65
	maximum_z += 0.65
	var x_steps := ceili((maximum_x - minimum_x) / spacing) + 1
	var z_steps := ceili((maximum_z - minimum_z) / spacing) + 1
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var row_a := PackedVector4Array()
	for x_index in range(x_steps):
		row_a.append(_sample_terrain(minimum_x + float(x_index) * spacing, minimum_z))
	for z_index in range(z_steps - 1):
		var z_a := minimum_z + float(z_index) * spacing
		var z_b := z_a + spacing
		var row_b := PackedVector4Array()
		for x_index in range(x_steps):
			row_b.append(_sample_terrain(minimum_x + float(x_index) * spacing, z_b))
		for x_index in range(x_steps - 1):
			var x_a := minimum_x + float(x_index) * spacing
			var x_b := x_a + spacing
			_add_sampled_terrain_vertex(surface, x_a, z_a, row_a[x_index])
			_add_sampled_terrain_vertex(surface, x_a, z_b, row_b[x_index])
			_add_sampled_terrain_vertex(surface, x_b, z_a, row_a[x_index + 1])
			_add_sampled_terrain_vertex(surface, x_b, z_a, row_a[x_index + 1])
			_add_sampled_terrain_vertex(surface, x_a, z_b, row_b[x_index])
			_add_sampled_terrain_vertex(surface, x_b, z_b, row_b[x_index + 1])
		row_a = row_b
	surface.index()
	surface.generate_normals()
	grid_node.mesh = surface.commit()

func set_hex_overlay_visible(enabled: bool) -> void:
	if outline_node == null:
		return
	outline_node.visible = enabled
	if enabled:
		_rebuild_grid_outlines()

func _rebuild_grid_outlines() -> void:
	if outline_node == null or not outline_node.visible:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for row in range(HexGrid.ROWS):
		for column in range(HexGrid.COLUMNS):
			var cell := Vector2i(column, row)
			var center := data.world_center(cell)
			for corner in range(6):
				var next_corner := (corner + 1) % 6
				var angle_a := deg_to_rad(30.0 + 60.0 * corner)
				var angle_b := deg_to_rad(30.0 + 60.0 * next_corner)
				var a := Vector3(center.x + cos(angle_a) * EDGE_RADIUS, 0.0, center.z + sin(angle_a) * EDGE_RADIUS)
				var b := Vector3(center.x + cos(angle_b) * EDGE_RADIUS, 0.0, center.z + sin(angle_b) * EDGE_RADIUS)
				a.y = _surface_height_at(a.x, a.z) + 0.018
				b.y = _surface_height_at(b.x, b.z) + 0.018
				surface.add_vertex(a)
				surface.add_vertex(b)
	outline_node.mesh = surface.commit()

func _queue_terrain_surface_update(cell: Vector2i, elevation_changed: bool) -> void:
	_surface_dirty_cells[data.index_of(cell)] = cell
	for edge in range(6):
		var neighbor := data.neighbor_for_edge(cell, edge)
		if data.contains(neighbor):
			_surface_dirty_cells[data.index_of(neighbor)] = neighbor
	_surface_heights_dirty = _surface_heights_dirty or elevation_changed
	if _surface_update_queued:
		return
	_surface_update_queued = true
	call_deferred("_flush_terrain_surface_update")

func _flush_terrain_surface_update() -> void:
	_surface_update_queued = false
	if _refreshing_all:
		return
	_rebuild_terrain_surface()
	_rebuild_grid_outlines()
	if _surface_heights_dirty:
		_rebuild_cliffs()
		if displayed_elevations.size() != data.elevations.size():
			displayed_elevations = data.elevations.duplicate()
		for index in _surface_dirty_cells:
			displayed_elevations[index] = data.elevation_at(_surface_dirty_cells[index])
	for cell in _surface_dirty_cells.values():
		_refresh_grass_cell(cell, data.index_of(cell))
	_surface_dirty_cells.clear()
	_surface_heights_dirty = false
	_update_selection()

func _build_water_instances() -> void:
	water_instances = MultiMesh.new()
	water_instances.transform_format = MultiMesh.TRANSFORM_3D
	water_instances.mesh = _make_water_hex_mesh(water_subdivisions)
	water_instances.instance_count = HexGrid.COLUMNS * HexGrid.ROWS
	water_node = MultiMeshInstance3D.new()
	water_node.name = "AnimatedWaterHexes"
	water_node.multimesh = water_instances
	water_shader_material = ShaderMaterial.new()
	water_shader_material.shader = load("res://assets/materials/water_surface.gdshader") as Shader
	water_shader_material.set_shader_parameter("flow_direction", water_flow_direction)
	water_node.material_override = water_shader_material
	water_node.visible = false
	add_child(water_node)

func _refresh_water_cell(cell: Vector2i, index: int, center: Vector3) -> void:
	if water_instances == null:
		return
	var transform := Transform3D(Basis.IDENTITY, center)
	if data.terrain_at(cell) == HexGrid.Terrain.WATER:
		transform.origin.y += CAP_HEIGHT * 0.5 + 0.014
	else:
		transform.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
	water_instances.set_instance_transform(index, transform)

func set_water_subdivisions(value: int) -> void:
	var bounded := clampi(value, 2, 6)
	if bounded == water_subdivisions and water_instances != null:
		return
	water_subdivisions = bounded
	if water_instances != null:
		water_instances.mesh = _make_water_hex_mesh(water_subdivisions)

func set_water_flow_direction(direction: Vector2) -> void:
	if direction.length_squared() < 0.001:
		return
	water_flow_direction = direction.normalized()
	if water_shader_material != null:
		water_shader_material.set_shader_parameter("flow_direction", water_flow_direction)
	if terrain_shader_material != null:
		terrain_shader_material.set_shader_parameter("water_flow_direction", water_flow_direction)
	if shoreline_shader_material != null:
		shoreline_shader_material.set_shader_parameter("flow_direction", water_flow_direction)

func _build_shoreline_node() -> void:
	shoreline_node = MeshInstance3D.new()
	shoreline_node.name = "WaterGroundShoreline"
	shoreline_shader_material = ShaderMaterial.new()
	shoreline_shader_material.shader = load("res://assets/materials/water_shoreline.gdshader") as Shader
	shoreline_shader_material.set_shader_parameter("flow_direction", water_flow_direction)
	shoreline_node.material_override = shoreline_shader_material
	shoreline_node.visible = false
	add_child(shoreline_node)

func _refresh_shorelines_around(cell: Vector2i) -> void:
	_refresh_shoreline_cell(cell)
	for edge in range(6):
		var neighbor := data.neighbor_for_edge(cell, edge)
		if data.contains(neighbor):
			_refresh_shoreline_cell(neighbor)

func _refresh_shoreline_cell(cell: Vector2i) -> void:
	if shoreline_node == null or not data.contains(cell):
		return
	var index := data.index_of(cell)
	var is_water := data.terrain_at(cell) == HexGrid.Terrain.WATER
	var changed := false
	for edge in range(6):
		var neighbor := data.neighbor_for_edge(cell, edge)
		var meets_ground := not data.contains(neighbor) or data.terrain_at(neighbor) != HexGrid.Terrain.WATER
		var instance_index := index * 6 + edge
		var is_shore := is_water and meets_ground
		if is_shore and not shoreline_edges.has(instance_index):
			shoreline_edges[instance_index] = true
			changed = true
		elif not is_shore and shoreline_edges.has(instance_index):
			shoreline_edges.erase(instance_index)
			changed = true
	if changed and not _refreshing_all:
		_queue_shoreline_rebuild()

func _queue_shoreline_rebuild() -> void:
	if _shoreline_rebuild_queued:
		return
	_shoreline_rebuild_queued = true
	call_deferred("_rebuild_shoreline_mesh")

func _rebuild_shoreline_mesh() -> void:
	_shoreline_rebuild_queued = false
	if shoreline_node == null:
		return
	if shoreline_edges.is_empty():
		shoreline_node.mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for instance_index in shoreline_edges:
		var cell_index := floori(float(instance_index) / 6.0)
		var edge := int(instance_index) % 6
		_append_shoreline_edge(surface, data.cell_from_index(cell_index), edge)
	surface.generate_normals()
	shoreline_node.mesh = surface.commit()

func _append_shoreline_edge(surface: SurfaceTool, cell: Vector2i, edge: int) -> void:
	var center := data.world_center(cell)
	var angle_a := deg_to_rad(30.0 + 60.0 * edge)
	var angle_b := deg_to_rad(30.0 + 60.0 * ((edge + 1) % 6))
	var edge_a := Vector3(center.x + cos(angle_a) * EDGE_RADIUS, 0.0, center.z + sin(angle_a) * EDGE_RADIUS)
	var edge_b := Vector3(center.x + cos(angle_b) * EDGE_RADIUS, 0.0, center.z + sin(angle_b) * EDGE_RADIUS)
	var middle_angle := deg_to_rad(60.0 + 60.0 * edge)
	var inward := Vector3(-cos(middle_angle), 0.0, -sin(middle_angle))
	var top_y := data.elevation_at(cell) * STEP_HEIGHT + CAP_HEIGHT * 0.5 + 0.026
	edge_a.y = top_y
	edge_b.y = top_y
	var inner_a := edge_a + inward * 0.135
	var inner_b := edge_b + inward * 0.135
	var outer_a := edge_a + inward * 0.012
	var outer_b := edge_b + inward * 0.012
	_add_shoreline_triangle(surface, outer_a, outer_b, inner_b, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0))
	_add_shoreline_triangle(surface, outer_a, inner_b, inner_a, Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))

func _add_shoreline_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	surface.set_normal(Vector3.UP)
	surface.set_uv(uv_a)
	surface.add_vertex(a)
	surface.set_normal(Vector3.UP)
	surface.set_uv(uv_b)
	surface.add_vertex(b)
	surface.set_normal(Vector3.UP)
	surface.set_uv(uv_c)
	surface.add_vertex(c)

func _make_water_hex_mesh(subdivisions: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_y := 0.0
	var corners: Array[Vector3] = []
	for edge in range(6):
		var angle := deg_to_rad(30.0 + 60.0 * edge)
		corners.append(Vector3(cos(angle) * EDGE_RADIUS, top_y, sin(angle) * EDGE_RADIUS))
	var center := Vector3.ZERO
	for edge in range(6):
		var corner_b := corners[edge]
		var corner_c := corners[(edge + 1) % 6]
		for row in range(subdivisions):
			for column in range(row + 1):
				var p1 := _water_slice_point(center, corner_b, corner_c, row, column, subdivisions)
				var p2 := _water_slice_point(center, corner_b, corner_c, row + 1, column, subdivisions)
				var p3 := _water_slice_point(center, corner_b, corner_c, row + 1, column + 1, subdivisions)
				_add_water_triangle(surface, p1, p2, p3)
				if column > 0:
					var p4 := _water_slice_point(center, corner_b, corner_c, row, column - 1, subdivisions)
					_add_water_triangle(surface, p1, p4, p2)
	return surface.commit()

func _water_slice_point(a: Vector3, b: Vector3, c: Vector3, row: int, column: int, subdivisions: int) -> Vector3:
	if row == 0:
		return a
	var row_ratio := float(row) / float(subdivisions)
	var column_ratio := float(column) / float(row)
	var edge_b := a.lerp(b, row_ratio)
	var edge_c := a.lerp(c, row_ratio)
	return edge_b.lerp(edge_c, column_ratio)

func _add_water_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.y < 0.0:
		var swap := b
		b = c
		c = swap
	var uv_scale := 1.0 / (EDGE_RADIUS * 2.0)
	for point in [a, b, c]:
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(point.x * uv_scale + 0.5, point.z * uv_scale + 0.5))
		surface.add_vertex(point)

func _build_grass_instances() -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = _make_grass_tuft_mesh()
	instances.instance_count = HexGrid.COLUMNS * HexGrid.ROWS * GRASS_TUFTS_PER_HEX
	var node := MultiMeshInstance3D.new()
	node.name = "GrassTufts"
	node.multimesh = instances
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	add_child(node)
	grass_node = node
	grass_instances = instances

func _make_grass_tuft_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade_colors: Array[Color] = [Color("557d38"), Color("719644"), Color("91ad50"), Color("63863a"), Color("819e48"), Color("a0b65b")]
	for blade in range(9):
		var angle := TAU * float(blade) / 9.0 + float(blade % 2) * 0.19
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var height := 0.26 + float((blade * 7) % 6) * 0.048
		var width := 0.036 + float(blade % 4) * 0.009
		var base_left := -side * width
		var base_right := side * width
		var middle := direction * 0.07 + Vector3.UP * height * 0.48
		var tip := direction * (0.12 + float(blade % 3) * 0.025) + Vector3.UP * height
		var color := blade_colors[blade % blade_colors.size()]
		_add_colored_triangle(surface, base_left, base_right, middle, color.darkened(0.12), color.darkened(0.08), color)
		_add_colored_triangle(surface, base_right, tip, middle, color.darkened(0.08), color.lightened(0.06), color)
	surface.generate_normals()
	return surface.commit()

func _add_colored_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color) -> void:
	for vertex in [[a, color_a], [b, color_b], [c, color_c]]:
		surface.set_color(vertex[1])
		surface.add_vertex(vertex[0])

func _surface_height_at(world_x: float, world_z: float) -> float:
	return _sample_terrain(world_x, world_z).x

func _refresh_grass_cell(cell: Vector2i, index: int) -> void:
	var is_grass := data.terrain_at(cell) == HexGrid.Terrain.GRASS
	var base_index := index * GRASS_TUFTS_PER_HEX
	var center := data.world_center(cell)
	for tuft_index in range(GRASS_TUFTS_PER_HEX):
		var instance_index := base_index + tuft_index
		var rng := RandomNumberGenerator.new()
		rng.seed = int(index * 92821 + tuft_index * 17431 + 3719)
		if not is_grass or rng.randf() > 0.58:
			grass_instances.set_instance_transform(instance_index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
			grass_instances.set_instance_color(instance_index, Color.WHITE)
			continue
		var tuft_center := center
		tuft_center.x += rng.randf_range(-0.48, 0.48)
		tuft_center.z += rng.randf_range(-0.42, 0.42)
		tuft_center.y = _surface_height_at(tuft_center.x, tuft_center.z) + 0.006
		var scale := rng.randf_range(0.72, 1.42)
		var rotation := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, rotation).scaled(Vector3(scale, scale, scale))
		grass_instances.set_instance_transform(instance_index, Transform3D(basis, tuft_center))
		var tint := rng.randf_range(0.80, 1.12)
		grass_instances.set_instance_color(instance_index, Color(tint, tint, tint, 1.0))

func _build_selection_outline() -> void:
	selection_node = MeshInstance3D.new()
	selection_node.name = "SelectedHexOutline"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = SELECT_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	selection_node.material_override = material
	selection_node.visible = false
	add_child(selection_node)

func refresh_all() -> void:
	_refreshing_all = true
	_surface_update_queued = false
	_surface_heights_dirty = false
	_surface_dirty_cells.clear()
	shoreline_edges.clear()
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		refresh_cell(data.cell_from_index(index))
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		_refresh_shoreline_cell(data.cell_from_index(index))
	_refreshing_all = false
	displayed_elevations = data.elevations.duplicate()
	_rebuild_terrain_surface()
	_rebuild_grid_outlines()
	_rebuild_shoreline_mesh()
	_rebuild_cliffs()
	_update_selection()

func refresh_cell(cell: Vector2i) -> void:
	if not data.contains(cell):
		return
	var index := data.index_of(cell)
	var center := data.world_center(cell)
	center.y = data.elevation_at(cell) * STEP_HEIGHT
	_refresh_grass_cell(cell, index)
	_refresh_water_cell(cell, index, center)
	if not _refreshing_all:
		var elevation_changed := displayed_elevations.size() != data.elevations.size() or displayed_elevations[index] != data.elevation_at(cell)
		_queue_terrain_surface_update(cell, elevation_changed)
		_refresh_shorelines_around(cell)
	if cell == selected_cell:
		_update_selection()

func set_selected(cell: Vector2i) -> void:
	selected_cell = cell if data.contains(cell) else Vector2i(-1, -1)
	_update_selection()

func _update_selection() -> void:
	if selection_node == null or not data.contains(selected_cell):
		return
	var center := data.world_center(selected_cell)
	center.y = float(data.elevation_at(selected_cell)) * STEP_HEIGHT + CAP_HEIGHT * 0.5
	selection_node.position = center
	selection_node.mesh = _make_selection_outline_mesh(selected_cell)
	selection_node.visible = true

func _make_selection_outline_mesh(cell: Vector2i) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINE_STRIP)
	var center := data.world_center(cell)
	var center_y := _surface_height_at(center.x, center.z)
	for corner in range(7):
		var corner_index := corner % 6
		var angle := deg_to_rad(30.0 + 60.0 * corner_index)
		var local_x := cos(angle) * 1.01
		var local_z := sin(angle) * 1.01
		var corner_y := _surface_height_at(center.x + local_x, center.z + local_z)
		surface.add_vertex(Vector3(local_x, corner_y - center_y + 0.025, local_z))
	return surface.commit()

func _rebuild_cliffs() -> void:
	if cliff_node != null:
		cliff_node.queue_free()
		cliff_node = null
	if data == null:
		return

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_count := 0
	for row in range(HexGrid.ROWS):
		for column in range(HexGrid.COLUMNS):
			var cell := Vector2i(column, row)
			var high_level := data.elevation_at(cell)
			for edge in range(6):
				var neighbor := data.neighbor_for_edge(cell, edge)
				var low_level := data.elevation_at(neighbor) if data.contains(neighbor) else 0
				# Only expose true escarpments. One-step terrain transitions stay soft.
				if high_level - low_level < 2:
					continue
				var center := data.world_center(cell)
				var angle_a := deg_to_rad(30.0 + 60.0 * edge)
				var angle_b := deg_to_rad(30.0 + 60.0 * ((edge + 1) % 6))
				var top_a := Vector3(center.x + cos(angle_a) * EDGE_RADIUS, float(high_level) * STEP_HEIGHT + CAP_HEIGHT * 0.5, center.z + sin(angle_a) * EDGE_RADIUS)
				var top_b := Vector3(center.x + cos(angle_b) * EDGE_RADIUS, float(high_level) * STEP_HEIGHT + CAP_HEIGHT * 0.5, center.z + sin(angle_b) * EDGE_RADIUS)
				var bottom_a := Vector3(top_a.x, float(low_level) * STEP_HEIGHT + CAP_HEIGHT * 0.5, top_a.z)
				var bottom_b := Vector3(top_b.x, float(low_level) * STEP_HEIGHT + CAP_HEIGHT * 0.5, top_b.z)
				_add_cliff_wall(surface, top_a, top_b, bottom_a, bottom_b)
				face_count += 1
	if face_count == 0:
		cliff_shader_material = null
		return
	surface.index()
	surface.generate_normals()
	cliff_node = MeshInstance3D.new()
	cliff_node.name = "RockyElevationCliffs"
	cliff_node.mesh = surface.commit()
	cliff_shader_material = ShaderMaterial.new()
	cliff_shader_material.shader = load("res://assets/materials/cliff_rock_texture.gdshader") as Shader
	cliff_shader_material.set_shader_parameter("rock_detail", cliff_detail_strength)
	cliff_node.material_override = cliff_shader_material
	cliff_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(cliff_node)

func _add_cliff_wall(surface: SurfaceTool, top_a: Vector3, top_b: Vector3, bottom_a: Vector3, bottom_b: Vector3) -> void:
	const VERTICAL_STEPS := 7
	const EDGE_STEPS := 10
	var edge_tangent := (top_b - top_a).normalized()
	var wall_normal := Vector3.UP.cross(edge_tangent).normalized()
	for vertical_step in range(VERTICAL_STEPS):
		var t0 := float(vertical_step) / VERTICAL_STEPS
		var t1 := float(vertical_step + 1) / VERTICAL_STEPS
		for edge_step in range(EDGE_STEPS):
			var s0 := float(edge_step) / EDGE_STEPS
			var s1 := float(edge_step + 1) / EDGE_STEPS
			var a0 := _cliff_vertex(top_a, top_b, bottom_a, bottom_b, s0, t0, wall_normal)
			var b0 := _cliff_vertex(top_a, top_b, bottom_a, bottom_b, s1, t0, wall_normal)
			var a1 := _cliff_vertex(top_a, top_b, bottom_a, bottom_b, s0, t1, wall_normal)
			var b1 := _cliff_vertex(top_a, top_b, bottom_a, bottom_b, s1, t1, wall_normal)
			if (edge_step + vertical_step) % 2 == 0:
				_add_triangle(surface, a0, b0, a1, Color.WHITE)
				_add_triangle(surface, b0, b1, a1, Color.WHITE)
			else:
				_add_triangle(surface, a0, b0, b1, Color.WHITE)
				_add_triangle(surface, a0, b1, a1, Color.WHITE)

func _cliff_vertex(top_a: Vector3, top_b: Vector3, bottom_a: Vector3, bottom_b: Vector3, edge_ratio: float, vertical_ratio: float, wall_normal: Vector3) -> Vector3:
	var top := top_a.lerp(top_b, edge_ratio)
	top.y = _surface_height_at(top.x, top.z)
	var bottom := bottom_a.lerp(bottom_b, edge_ratio)
	var point := top.lerp(bottom, vertical_ratio)
	# Dense curved sections break the hex outline into a continuous rock run.
	# The middle swells and the cap and toe remain joined to the ground surface.
	var edge_envelope := sin(edge_ratio * PI)
	var vertical_envelope := sin(vertical_ratio * PI)
	var broad_noise := cliff_noise.get_noise_3d(point.x * 0.36, point.y * 0.28, point.z * 0.36)
	var detail_noise := cliff_noise.get_noise_3d(point.x * 1.8 + 21.0, point.y * 0.8, point.z * 1.8 - 14.0)
	var ledge := sin(vertical_ratio * PI * 2.6 + broad_noise * 1.5) * 0.12
	point += wall_normal * edge_envelope * vertical_envelope * (broad_noise * 0.48 + detail_noise * 0.12 + ledge) * cliff_detail_strength
	point.y += vertical_envelope * detail_noise * 0.13 * cliff_detail_strength
	return point

func set_surface_detail(value: float) -> void:
	surface_detail_strength = clampf(value, 0.0, 1.0)
	if terrain_shader_material != null:
		terrain_shader_material.set_shader_parameter("surface_detail", surface_detail_strength)

func set_cliff_detail(value: float) -> void:
	cliff_detail_strength = clampf(value, 0.0, 1.0)
	if cliff_shader_material != null:
		cliff_shader_material.set_shader_parameter("rock_detail", cliff_detail_strength)

func refresh_cliffs() -> void:
	_rebuild_cliffs()

func _add_gradient_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color) -> void:
	for vertex in [[a, color_a], [b, color_b], [c, color_c]]:
		surface.set_color(vertex[1])
		surface.add_vertex(vertex[0])

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.add_vertex(c)
