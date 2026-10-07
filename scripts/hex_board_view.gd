class_name HexBoardView
extends Node3D

const CAP_HEIGHT: float = 0.18
const EDGE_RADIUS: float = HexGrid.HEX_RADIUS * 0.99
const STEP_HEIGHT: float = HexGrid.HEIGHT_PER_LEVEL
const SELECT_COLOR := Color("efcf78")

var data: HexGrid
var tile_instances: MultiMesh
var grid_node: MultiMeshInstance3D
var outline_instances: MultiMesh
var outline_node: MultiMeshInstance3D
var cliff_node: MeshInstance3D
var selection_node: MeshInstance3D
var selected_cell := Vector2i(-1, -1)

func initialize(grid_data: HexGrid) -> void:
	data = grid_data
	_build_backing()
	_build_tile_mesh()
	_build_selection_outline()
	refresh_all()

func _build_backing() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101813")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c6a2")
	environment.ambient_light_energy = 0.55
	world.environment = environment
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
		_add_triangle(surface, Vector3(0.0, top_y, 0.0), top_b, top_a, Color.WHITE)
		_add_triangle(surface, bottom_a, bottom_b, top_b, Color("b7b7b7"))
		_add_triangle(surface, bottom_a, top_b, top_a, Color("b7b7b7"))
	surface.generate_normals()
	return surface.commit()

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
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	grid_node.material_override = material
	add_child(grid_node)

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
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		refresh_cell(data.cell_from_index(index))
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
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cliff_count := 0
	for row in range(HexGrid.ROWS):
		for column in range(HexGrid.COLUMNS):
			var cell := Vector2i(column, row)
			var cell_level := data.elevation_at(cell)
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
	surface.generate_normals()
	cliff_node = MeshInstance3D.new()
	cliff_node.name = "AutoCliffFaces"
	cliff_node.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.98
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cliff_node.material_override = material
	add_child(cliff_node)

func _append_organic_cliff_face(surface: SurfaceTool, cell: Vector2i, edge: int, low_level: int, high_level: int) -> void:
	var center := data.world_center(cell)
	var angle_a := deg_to_rad(30.0 + 60.0 * edge)
	var angle_b := deg_to_rad(30.0 + 60.0 * ((edge + 1) % 6))
	var edge_a := Vector3(center.x + cos(angle_a) * EDGE_RADIUS, 0.0, center.z + sin(angle_a) * EDGE_RADIUS)
	var edge_b := Vector3(center.x + cos(angle_b) * EDGE_RADIUS, 0.0, center.z + sin(angle_b) * EDGE_RADIUS)
	var middle_angle := deg_to_rad(60.0 + 60.0 * edge)
	var outward := Vector3(cos(middle_angle), 0.0, sin(middle_angle))
	var bottom_y := low_level * STEP_HEIGHT + CAP_HEIGHT * 0.5
	var top_y := high_level * STEP_HEIGHT + CAP_HEIGHT * 0.5
	var wall_height := top_y - bottom_y

	# Seed each edge from its cell so sculpting and undo rebuild the same rock.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cell.x * 73856093) ^ int(cell.y * 19349663) ^ int(edge * 83492791)
	var horizontal_segments := 3
	var vertical_segments := clampi(ceili(wall_height / 0.9), 2, 10)
	var points: Array = []
	for vertical in range(vertical_segments + 1):
		var row_points: Array[Vector3] = []
		var row_ratio := float(vertical) / vertical_segments
		var row_y := lerpf(bottom_y, top_y, row_ratio)
		for horizontal in range(horizontal_segments + 1):
			var t := float(horizontal) / horizontal_segments
			var boundary := horizontal == 0 or horizontal == horizontal_segments
			if not boundary:
				t = clampf(t + rng.randf_range(-0.055, 0.055), 0.0, 1.0)
			var point := edge_a.lerp(edge_b, t)
			if not boundary:
				point += outward * rng.randf_range(0.015, 0.19)
			point.y = row_y
			if not boundary and vertical > 0 and vertical < vertical_segments:
				point.y += rng.randf_range(-0.11, 0.11)
			elif not boundary and vertical == vertical_segments:
				# Broken stone teeth peek through the grass line along the rim.
				point.y += rng.randf_range(-0.025, 0.13)
			row_points.append(point)
		points.append(row_points)

	var rock_colors: Array[Color] = [
		Color("55564f"), Color("66665d"), Color("777265"),
		Color("484941"), Color("858070"), Color("5c5a50")
	]
	for vertical in range(vertical_segments):
		for horizontal in range(horizontal_segments):
			var p00: Vector3 = points[vertical][horizontal]
			var p01: Vector3 = points[vertical][horizontal + 1]
			var p10: Vector3 = points[vertical + 1][horizontal]
			var p11: Vector3 = points[vertical + 1][horizontal + 1]
			var rock: Color = rock_colors[rng.randi_range(0, rock_colors.size() - 1)]
			if rng.randf() < 0.5:
				_add_triangle(surface, p00, p10, p11, rock)
				_add_triangle(surface, p00, p11, p01, rock.darkened(rng.randf_range(0.02, 0.12)))
			else:
				_add_triangle(surface, p00, p10, p01, rock.lightened(rng.randf_range(0.01, 0.08)))
				_add_triangle(surface, p10, p11, p01, rock.darkened(rng.randf_range(0.03, 0.13)))

	# A few tapered fissures break up the broad faces without making a tiled pattern.
	var fissure_count := clampi(ceili(wall_height / 1.8), 1, 4)
	for fissure in range(fissure_count):
		var t_center := rng.randf_range(0.16, 0.84)
		var crack_length := minf(rng.randf_range(0.28, 0.78), wall_height * 0.82)
		var crack_bottom := rng.randf_range(bottom_y, maxf(bottom_y, top_y - crack_length))
		var crack_top := crack_bottom + crack_length
		var drift := rng.randf_range(-0.055, 0.055)
		var crack_width := rng.randf_range(0.018, 0.042)
		var depth := outward * 0.22
		var left_bottom := edge_a.lerp(edge_b, t_center - crack_width) + depth
		var right_bottom := edge_a.lerp(edge_b, t_center + crack_width) + depth
		var left_top := edge_a.lerp(edge_b, t_center + drift - crack_width * 0.35) + depth
		var right_top := edge_a.lerp(edge_b, t_center + drift + crack_width * 0.35) + depth
		left_bottom.y = crack_bottom
		right_bottom.y = crack_bottom
		left_top.y = crack_top
		right_top.y = crack_top
		_add_triangle(surface, left_bottom, right_bottom, left_top, Color("30312c"))
		_add_triangle(surface, right_bottom, right_top, left_top, Color("282923"))

func refresh_cliffs() -> void:
	_rebuild_cliffs()

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.add_vertex(c)
