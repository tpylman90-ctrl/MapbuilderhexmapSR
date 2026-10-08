class_name HexBoardView
extends Node3D

const CAP_HEIGHT: float = 0.18
const EDGE_RADIUS: float = HexGrid.HEX_RADIUS * 0.99
const STEP_HEIGHT: float = HexGrid.HEIGHT_PER_LEVEL
const GRASS_TUFTS_PER_HEX: int = 4
const SELECT_COLOR := Color("efcf78")

var data: HexGrid
var world_environment: WorldEnvironment
var tile_instances: MultiMesh
var grid_node: MultiMeshInstance3D
var grass_instances: MultiMesh
var grass_node: MultiMeshInstance3D
var water_instances: MultiMesh
var water_node: MultiMeshInstance3D
var water_shader_material: ShaderMaterial
var water_subdivisions: int = 4
var water_flow_direction := Vector2(0.707107, 0.707107)
var shoreline_instances: MultiMesh
var shoreline_node: MultiMeshInstance3D
var shoreline_shader_material: ShaderMaterial
var _refreshing_all := false
var terrain_shader_material: ShaderMaterial
var cliff_shader_material: ShaderMaterial
var surface_detail_strength: float = 0.78
var cliff_detail_strength: float = 0.82
var outline_instances: MultiMesh
var outline_node: MultiMeshInstance3D
var cliff_node: MeshInstance3D
var selection_node: MeshInstance3D
var selected_cell := Vector2i(-1, -1)
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
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("98aaa2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c7c9b3")
	environment.ambient_light_energy = 0.43
	environment.tonemap_exposure = 0.95
	environment.fog_enabled = true
	environment.fog_light_color = Color("a9bdb1")
	environment.fog_light_energy = 0.78
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

func _make_hex_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_y := CAP_HEIGHT * 0.5
	var bottom_y := -CAP_HEIGHT * 0.5
	for edge in range(6):
		var angle_a := deg_to_rad(30.0 + 60.0 * edge)
		var angle_b := deg_to_rad(30.0 + 60.0 * ((edge + 1) % 6))
		var top_a := Vector3(cos(angle_a) * EDGE_RADIUS, top_y, sin(angle_a) * EDGE_RADIUS)
		var top_b := Vector3(cos(angle_b) * EDGE_RADIUS, top_y, sin(angle_b) * EDGE_RADIUS)
		var bottom_a := Vector3(cos(angle_a) * EDGE_RADIUS, bottom_y, sin(angle_a) * EDGE_RADIUS)
		var bottom_b := Vector3(cos(angle_b) * EDGE_RADIUS, bottom_y, sin(angle_b) * EDGE_RADIUS)
		# Winding is explicitly upward so the top remains visible in mobile renderers.
		_add_top_triangle(surface, Vector3(0.0, top_y, 0.0), top_b, top_a, Color.WHITE)
		_add_triangle(surface, bottom_a, bottom_b, top_b, Color("b7b7b7"))
		_add_triangle(surface, bottom_a, top_b, top_a, Color("b7b7b7"))
	surface.generate_normals()
	return surface.commit()

func _add_top_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var scale := 1.0 / (EDGE_RADIUS * 2.0)
	for point in [a, b, c]:
		surface.set_color(color)
		surface.set_uv(Vector2(point.x * scale + 0.5, point.z * scale + 0.5))
		surface.add_vertex(point)

func _make_grid_outline_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer_radius := HexGrid.HEX_RADIUS * 1.005
	var inner_radius := HexGrid.HEX_RADIUS * 0.975
	var y := CAP_HEIGHT * 0.5 + 0.008
	for edge in range(6):
		var angle_a := deg_to_rad(30.0 + 60.0 * edge)
		var angle_b := deg_to_rad(30.0 + 60.0 * ((edge + 1) % 6))
		var outer_a := Vector3(cos(angle_a) * outer_radius, y, sin(angle_a) * outer_radius)
		var outer_b := Vector3(cos(angle_b) * outer_radius, y, sin(angle_b) * outer_radius)
		var inner_a := Vector3(cos(angle_a) * inner_radius, y, sin(angle_a) * inner_radius)
		var inner_b := Vector3(cos(angle_b) * inner_radius, y, sin(angle_b) * inner_radius)
		_add_triangle(surface, outer_a, outer_b, inner_b, Color.WHITE)
		_add_triangle(surface, outer_a, inner_b, inner_a, Color.WHITE)
	surface.generate_normals()
	return surface.commit()

func _build_tile_mesh() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _make_hex_mesh()
	multi.instance_count = HexGrid.COLUMNS * HexGrid.ROWS
	tile_instances = multi
	grid_node = MultiMeshInstance3D.new()
	grid_node.name = "HexGrid64x128"
	grid_node.multimesh = tile_instances
	terrain_shader_material = ShaderMaterial.new()
	terrain_shader_material.shader = load("res://assets/materials/terrain_surface.gdshader") as Shader
	terrain_shader_material.set_shader_parameter("surface_detail", surface_detail_strength)
	grid_node.material_override = terrain_shader_material
	add_child(grid_node)
	_build_grass_instances()
	_build_water_instances()
	_build_shoreline_instances()

	var outlines := MultiMesh.new()
	outlines.transform_format = MultiMesh.TRANSFORM_3D
	outlines.mesh = _make_grid_outline_mesh()
	outlines.instance_count = HexGrid.COLUMNS * HexGrid.ROWS
	outline_instances = outlines
	outline_node = MultiMeshInstance3D.new()
	outline_node.name = "HexGridLines"
	outline_node.multimesh = outline_instances
	var outline_material := StandardMaterial3D.new()
	outline_material.albedo_color = Color("536649")
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	outline_node.material_override = outline_material
	add_child(outline_node)

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
	if shoreline_shader_material != null:
		shoreline_shader_material.set_shader_parameter("flow_direction", water_flow_direction)

func _build_shoreline_instances() -> void:
	shoreline_instances = MultiMesh.new()
	shoreline_instances.transform_format = MultiMesh.TRANSFORM_3D
	shoreline_instances.mesh = _make_shoreline_strip_mesh()
	shoreline_instances.instance_count = HexGrid.COLUMNS * HexGrid.ROWS * 6
	shoreline_node = MultiMeshInstance3D.new()
	shoreline_node.name = "WaterGroundShoreline"
	shoreline_node.multimesh = shoreline_instances
	shoreline_shader_material = ShaderMaterial.new()
	shoreline_shader_material.shader = load("res://assets/materials/water_shoreline.gdshader") as Shader
	shoreline_shader_material.set_shader_parameter("flow_direction", water_flow_direction)
	shoreline_node.material_override = shoreline_shader_material
	add_child(shoreline_node)

func _make_shoreline_strip_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_length := EDGE_RADIUS * 0.5
	var apothem := EDGE_RADIUS * cos(PI / 6.0)
	var outer_z := -apothem + 0.012
	var inner_z := -apothem + 0.135
	var a := Vector3(-half_length, 0.0, outer_z)
	var b := Vector3(half_length, 0.0, outer_z)
	var c := Vector3(half_length, 0.0, inner_z)
	var d := Vector3(-half_length, 0.0, inner_z)
	_add_shoreline_triangle(surface, a, b, c, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0))
	_add_shoreline_triangle(surface, a, c, d, Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
	return surface.commit()

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

func _refresh_shorelines_around(cell: Vector2i) -> void:
	_refresh_shoreline_cell(cell)
	for edge in range(6):
		var neighbor := data.neighbor_for_edge(cell, edge)
		if data.contains(neighbor):
			_refresh_shoreline_cell(neighbor)

func _refresh_shoreline_cell(cell: Vector2i) -> void:
	if shoreline_instances == null or not data.contains(cell):
		return
	var index := data.index_of(cell)
	var center := data.world_center(cell)
	center.y = data.elevation_at(cell) * STEP_HEIGHT + CAP_HEIGHT * 0.5 + 0.026
	var is_water := data.terrain_at(cell) == HexGrid.Terrain.WATER
	for edge in range(6):
		var neighbor := data.neighbor_for_edge(cell, edge)
		var meets_ground := not data.contains(neighbor) or data.terrain_at(neighbor) != HexGrid.Terrain.WATER
		var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), center)
		if is_water and meets_ground:
			var middle_angle := deg_to_rad(60.0 + 60.0 * edge)
			transform.basis = Basis(Vector3.UP, PI * 0.5 - middle_angle)
		shoreline_instances.set_instance_transform(index * 6 + edge, transform)

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
	var blade_colors: Array[Color] = [Color("65983e"), Color("82b247"), Color("a4c95b"), Color("719d3e"), Color("90b94b")]
	for blade in range(7):
		var angle := TAU * float(blade) / 7.0 + float(blade % 2) * 0.19
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var height := 0.30 + float((blade * 7) % 5) * 0.045
		var width := 0.048 + float(blade % 3) * 0.012
		var base_left := -side * width
		var base_right := side * width
		var middle := direction * 0.09 + Vector3.UP * height * 0.52
		var tip := direction * 0.16 + Vector3.UP * height
		var color := blade_colors[blade % blade_colors.size()]
		_add_colored_triangle(surface, base_left, base_right, middle, color.darkened(0.12), color.darkened(0.08), color)
		_add_colored_triangle(surface, base_right, tip, middle, color.darkened(0.08), color.lightened(0.06), color)
	surface.generate_normals()
	return surface.commit()

func _add_colored_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color) -> void:
	for vertex in [[a, color_a], [b, color_b], [c, color_c]]:
		surface.set_color(vertex[1])
		surface.add_vertex(vertex[0])

func _refresh_grass_cell(cell: Vector2i, index: int) -> void:
	var is_grass := data.terrain_at(cell) == HexGrid.Terrain.GRASS
	var base_index := index * GRASS_TUFTS_PER_HEX
	var center := data.world_center(cell)
	center.y = data.elevation_at(cell) * STEP_HEIGHT + CAP_HEIGHT * 0.5 + 0.004
	for tuft_index in range(GRASS_TUFTS_PER_HEX):
		var instance_index := base_index + tuft_index
		var rng := RandomNumberGenerator.new()
		rng.seed = int(index * 92821 + tuft_index * 17431 + 3719)
		if not is_grass or rng.randf() > 0.64:
			grass_instances.set_instance_transform(instance_index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
			grass_instances.set_instance_color(instance_index, Color.WHITE)
			continue
		var tuft_center := center
		tuft_center.x += rng.randf_range(-0.48, 0.48)
		tuft_center.z += rng.randf_range(-0.42, 0.42)
		var scale := rng.randf_range(0.84, 1.38)
		var rotation := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, rotation).scaled(Vector3(scale, scale, scale))
		grass_instances.set_instance_transform(instance_index, Transform3D(basis, tuft_center))
		var tint := rng.randf_range(0.80, 1.12)
		grass_instances.set_instance_color(instance_index, Color(tint, tint, tint, 1.0))

func _build_selection_outline() -> void:
	var outline := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = SELECT_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	outline.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for corner in range(7):
		var angle := deg_to_rad(30.0 + 60.0 * (corner % 6))
		outline.surface_add_vertex(Vector3(cos(angle) * 1.01, 0.015, sin(angle) * 1.01))
	outline.surface_end()
	selection_node = MeshInstance3D.new()
	selection_node.name = "SelectedHexOutline"
	selection_node.mesh = outline
	selection_node.visible = false
	add_child(selection_node)

func refresh_all() -> void:
	_refreshing_all = true
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		refresh_cell(data.cell_from_index(index))
	_refreshing_all = false
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		_refresh_shoreline_cell(data.cell_from_index(index))
	_rebuild_cliffs()
	_update_selection()

func refresh_cell(cell: Vector2i) -> void:
	if not data.contains(cell):
		return
	var index := data.index_of(cell)
	var center := data.world_center(cell)
	center.y = data.elevation_at(cell) * STEP_HEIGHT
	tile_instances.set_instance_transform(index, Transform3D(Basis.IDENTITY, center))
	outline_instances.set_instance_transform(index, Transform3D(Basis.IDENTITY, center))
	tile_instances.set_instance_color(index, HexGrid.TERRAIN_COLORS[data.terrain_at(cell)])
	_refresh_grass_cell(cell, index)
	_refresh_water_cell(cell, index, center)
	if not _refreshing_all:
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
	center.y = data.elevation_at(selected_cell) * STEP_HEIGHT + CAP_HEIGHT * 0.5
	selection_node.position = center
	selection_node.visible = true

func _rebuild_cliffs() -> void:
	if cliff_node != null:
		cliff_node.queue_free()
		cliff_node = null
	cliff_shader_material = null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cliff_count := 0
	for row in range(HexGrid.ROWS):
		for column in range(HexGrid.COLUMNS):
			var cell := Vector2i(column, row)
			var cell_level := data.elevation_at(cell)
			# Emit only high-to-low boundary edges into this shared surface. Equal- or
			# higher-level neighbors omit their shared edge, leaving no interior walls.
			for edge in range(6):
				var neighbor := data.neighbor_for_edge(cell, edge)
				var high_level: int
				var low_level: int
				if data.contains(neighbor):
					var neighbor_level := data.elevation_at(neighbor)
					if cell_level <= neighbor_level:
						continue
					high_level = cell_level
					low_level = neighbor_level
				else:
					if cell_level == 0:
						continue
					high_level = maxi(cell_level, 0)
					low_level = mini(cell_level, 0)
				_append_organic_cliff_face(surface, cell, edge, low_level, high_level)
				cliff_count += 1
	if cliff_count == 0:
		return
	# Keep the triangulated rock planes flat shaded for a hand-cut low-poly look.
	surface.generate_normals()
	cliff_node = MeshInstance3D.new()
	cliff_node.name = "AutoCliffFaces"
	cliff_node.mesh = surface.commit()
	cliff_shader_material = ShaderMaterial.new()
	cliff_shader_material.shader = load("res://assets/materials/cliff_rock_texture.gdshader") as Shader
	cliff_shader_material.set_shader_parameter("rock_detail", cliff_detail_strength)
	cliff_node.material_override = cliff_shader_material
	add_child(cliff_node)


func _append_organic_cliff_face(surface: SurfaceTool, cell: Vector2i, edge: int, low_level: int, high_level: int) -> void:
	var center := data.world_center(cell)
	var angle_a := deg_to_rad(30.0 + 60.0 * edge)
	var angle_b := deg_to_rad(30.0 + 60.0 * ((edge + 1) % 6))
	var edge_a := Vector3(center.x + cos(angle_a) * EDGE_RADIUS, 0.0, center.z + sin(angle_a) * EDGE_RADIUS)
	var edge_b := Vector3(center.x + cos(angle_b) * EDGE_RADIUS, 0.0, center.z + sin(angle_b) * EDGE_RADIUS)
	var middle_angle := deg_to_rad(60.0 + 60.0 * edge)
	var outward := Vector3(cos(middle_angle), 0.0, sin(middle_angle))
	var tangent := (edge_b - edge_a).normalized()
	var bottom_y := low_level * STEP_HEIGHT + CAP_HEIGHT * 0.5
	var top_y := high_level * STEP_HEIGHT + CAP_HEIGHT * 0.5
	var wall_height := top_y - bottom_y
	var edge_length := edge_a.distance_to(edge_b)
	cliff_blend_top_y = top_y
	cliff_blend_color = HexGrid.TERRAIN_COLORS[data.terrain_at(cell)].lightened(0.14)

	# A continuous noisy surface replaces the old pair of vertical buttress strips.
	# Shared top, bottom, and corner rows stay fixed so neighboring boundary faces meet.
	_append_cliff_backing_grid(surface, edge_a, edge_b, bottom_y, top_y, center, outward, tangent)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(cell.x * 73856093) ^ int(cell.y * 19349663) ^ int(edge * 83492791)
	# Sparse cracks and moss add scale cues without rebuilding the face as columns.
	var moss_colors: Array[Color] = [Color("4d6038"), Color("687748"), Color("78834d")]
	var moss_count := clampi(ceili(edge_length * wall_height / 2.3), 2, 4)
	for moss_index in range(moss_count):
		var moss_t := rng.randf_range(0.14, 0.86)
		var moss_width := rng.randf_range(0.055, 0.12)
		var moss_y := top_y - rng.randf_range(0.04, minf(0.24, wall_height * 0.34))
		var moss_a := edge_a.lerp(edge_b, moss_t - moss_width) + outward * 0.16
		var moss_b := edge_a.lerp(edge_b, moss_t + moss_width) + outward * 0.16
		var moss_tip := edge_a.lerp(edge_b, moss_t + rng.randf_range(-0.025, 0.025)) + outward * 0.18
		moss_a.y = moss_y
		moss_b.y = moss_y + rng.randf_range(-0.03, 0.03)
		moss_tip.y = minf(top_y + 0.02, moss_y + rng.randf_range(0.06, 0.14))
		_add_side_triangle(surface, moss_a, moss_b, moss_tip, moss_colors[rng.randi_range(0, moss_colors.size() - 1)])

	var fissure_count := clampi(ceili(wall_height / 2.6), 2, 4)
	for fissure in range(fissure_count):
		var t_center := rng.randf_range(0.15, 0.85)
		var crack_length := minf(rng.randf_range(0.7, 1.5), wall_height * 0.78)
		var crack_bottom := rng.randf_range(bottom_y, maxf(bottom_y, top_y - crack_length))
		var crack_top := crack_bottom + crack_length
		var drift := rng.randf_range(-0.18, 0.18)
		var crack_width := rng.randf_range(0.016, 0.034)
		var depth := outward * 0.19
		var left_bottom := edge_a.lerp(edge_b, t_center - crack_width) + depth
		var right_bottom := edge_a.lerp(edge_b, t_center + crack_width) + depth
		var left_top := edge_a.lerp(edge_b, t_center + drift - crack_width * 0.3) + depth
		var right_top := edge_a.lerp(edge_b, t_center + drift + crack_width * 0.3) + depth
		left_bottom.y = crack_bottom
		right_bottom.y = crack_bottom
		left_top.y = crack_top
		right_top.y = crack_top
		_add_side_triangle(surface, left_bottom, right_bottom, left_top, Color("30312c"))
		_add_side_triangle(surface, right_bottom, right_top, left_top, Color("282923"))


func _append_cliff_backing_grid(surface: SurfaceTool, edge_a: Vector3, edge_b: Vector3, bottom_y: float, top_y: float, center: Vector3, outward: Vector3, tangent: Vector3) -> void:
	var horizontal_segments := 12
	var vertical_segments := clampi(ceili((top_y - bottom_y) / 0.25), 10, 20)
	var rows: Array = []
	for y_step in range(vertical_segments + 1):
		var height_ratio := float(y_step) / vertical_segments
		var row := PackedVector3Array()
		for x_step in range(horizontal_segments + 1):
			var edge_ratio := float(x_step) / horizontal_segments
			var point := edge_a.lerp(edge_b, edge_ratio)
			point.y = lerpf(bottom_y, top_y, height_ratio)
			if y_step > 0 and y_step < vertical_segments and x_step > 0 and x_step < horizontal_segments:
				var mass_profile := lerpf(0.48, 1.0, pow(maxf(sin(PI * height_ratio), 0.0), 0.72))
				var shoulder_fade := maxf(pow(maxf(sin(PI * height_ratio), 0.0), 0.72), 0.42)
				var side_fade := clampf(minf(edge_ratio, 1.0 - edge_ratio) * 3.0, 0.0, 1.0)
				var displacement_fade := mass_profile * shoulder_fade * side_fade
				point += _cliff_vertex_breakup(point, center, outward, tangent, displacement_fade)
			row.append(point)
		rows.append(row)

	for y_step in range(vertical_segments):
		var lower: PackedVector3Array = rows[y_step]
		var upper: PackedVector3Array = rows[y_step + 1]
		for x_step in range(horizontal_segments):
			var low_left: Vector3 = lower[x_step]
			var low_right: Vector3 = lower[x_step + 1]
			var high_left: Vector3 = upper[x_step]
			var high_right: Vector3 = upper[x_step + 1]
			# Alternate diagonals to avoid the repeated triangular strip pattern.
			if (x_step + y_step) % 2 == 0:
				_add_organic_triangle(surface, low_left, high_left, high_right)
				_add_organic_triangle(surface, low_left, high_right, low_right)
			else:
				_add_organic_triangle(surface, low_left, high_left, low_right)
				_add_organic_triangle(surface, low_right, high_left, high_right)

func _cliff_vertex_breakup(point: Vector3, center: Vector3, outward: Vector3, tangent: Vector3, fade: float) -> Vector3:
	# Broad cellular forms create bulges; smaller noise shifts them sideways and vertically.
	var broad := cliff_noise.get_noise_3d(point.x * 1.5, point.y * 0.8, point.z * 1.5)
	var detail := cliff_noise.get_noise_3d((point.x + 17.3) * 3.2, (point.y - 4.1) * 2.2, (point.z + 9.7) * 3.2)
	var chips := cliff_noise.get_noise_3d((point.x - 8.1) * 7.5, (point.y + 2.7) * 5.4, (point.z + 13.6) * 7.5)
	return (outward * (broad * 0.48 + detail * 0.28 + chips * 0.075) + tangent * (detail * 0.22 + chips * 0.10) + Vector3.UP * (broad * 0.12 + chips * 0.055)) * fade

func _add_organic_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var centroid := (a + b + c) / 3.0
	var facet_noise := cliff_noise.get_noise_3d((centroid.x + 31.0) * 2.1, (centroid.y - 6.0) * 2.3, (centroid.z - 11.0) * 2.1)
	var facet_step := roundf(clampf(0.5 + facet_noise * 0.52, 0.0, 1.0) * 5.0) / 5.0
	var facet_color := Color("57452f").lerp(Color("b49a6c"), facet_step)
	for point in [a, b, c]:
		var fleck := cliff_noise.get_noise_3d((point.x + 4.7) * 8.0, (point.y + 1.9) * 6.0, (point.z - 7.3) * 8.0)
		var stone_color := facet_color.lerp(Color("c1a578"), clampf(0.08 + fleck * 0.08, 0.0, 0.16))
		var edge_wobble := sin(point.x * 5.7 + point.z * 4.1) * 0.055
		var blend_depth := maxf(0.24, 0.36 + edge_wobble)
		var blend_t := clampf((cliff_blend_top_y - point.y) / blend_depth, 0.0, 1.0)
		blend_t = blend_t * blend_t * (3.0 - 2.0 * blend_t)
		var vertex_color := stone_color.lerp(cliff_blend_color, (1.0 - blend_t) * 0.84)
		surface.set_smooth_group(-1)
		surface.set_color(vertex_color)
		surface.set_uv(Vector2((point.x + point.z) * 0.65, point.y * 0.55))
		surface.add_vertex(point)

func _add_side_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for point in [a, b, c]:
		var edge_wobble := sin(point.x * 5.7 + point.z * 4.1) * 0.055
		var blend_depth := maxf(0.24, 0.36 + edge_wobble)
		var blend_t := clampf((cliff_blend_top_y - point.y) / blend_depth, 0.0, 1.0)
		blend_t = blend_t * blend_t * (3.0 - 2.0 * blend_t)
		var vertex_color := color.lerp(cliff_blend_color, (1.0 - blend_t) * 0.84)
		surface.set_smooth_group(-1)
		surface.set_color(vertex_color)
		surface.set_uv(Vector2((point.x + point.z) * 0.65, point.y * 0.55))
		surface.add_vertex(point)

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
