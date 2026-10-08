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
var ledge_node: MeshInstance3D
var selection_node: MeshInstance3D
var selected_cell := Vector2i(-1, -1)
var cliff_noise := FastNoiseLite.new()

func initialize(grid_data: HexGrid) -> void:
	data = grid_data
	cliff_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	cliff_noise.frequency = 0.42
	cliff_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	cliff_noise.fractal_octaves = 3
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
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/terrain_surface.gdshader") as Shader
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
	if ledge_node != null:
		ledge_node.queue_free()
		ledge_node = null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ledge_surface := SurfaceTool.new()
	ledge_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
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
				_append_organic_cliff_face(surface, ledge_surface, cell, edge, low_level, high_level)
				cliff_count += 1
	if cliff_count == 0:
		return
	surface.generate_normals()
	cliff_node = MeshInstance3D.new()
	cliff_node.name = "AutoCliffFaces"
	cliff_node.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/cliff_rock_texture.gdshader") as Shader
	cliff_node.material_override = material
	add_child(cliff_node)

	ledge_surface.generate_normals()
	ledge_node = MeshInstance3D.new()
	ledge_node.name = "TerrainCliffLips"
	ledge_node.mesh = ledge_surface.commit()
	var ledge_material := ShaderMaterial.new()
	ledge_material.shader = load("res://assets/materials/terrain_surface.gdshader") as Shader
	ledge_node.material_override = ledge_material
	add_child(ledge_node)

func _append_organic_cliff_face(surface: SurfaceTool, ledge_surface: SurfaceTool, cell: Vector2i, edge: int, low_level: int, high_level: int) -> void:
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
	var edge_length := edge_a.distance_to(edge_b)

	# Seed each edge from its cell so sculpting and undo rebuild the same rock.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cell.x * 73856093) ^ int(cell.y * 19349663) ^ int(edge * 83492791)
	# A subdivided, eroded backing wall fills the gaps behind the larger rock ribs.
	# It keeps the face continuous while preserving the deep seams between facets.
	var backing_depth := outward * 0.035
	var base_a := edge_a + backing_depth
	var base_b := edge_b + backing_depth
	_append_cliff_backing_grid(surface, base_a, base_b, bottom_y, top_y, center, outward)

	var rock_colors: Array[Color] = [
		Color("3d403c"), Color("4a4c46"), Color("5d5b52"),
		Color("383b37"), Color("706b60"), Color("515149"),
		Color("625e53"), Color("444740"), Color("565147")
	]
	# Build long, broken vertical buttresses. Each band shifts and changes width,
	# then a raised inner ridge splits it into additional angular facets. Gaps
	# between the buttresses reveal the dark backing as deep seams.
	# Two wide, offset rock ribs read as fractured mountain masses instead of
	# a row of narrow basalt-like columns.
	var buttress_count := 2
	var vertical_segments := clampi(ceili(wall_height / 0.40), 6, 14)
	var centers: Array[float] = []
	var widths: Array[float] = []
	var depths: Array[float] = []
	for buttress in range(buttress_count):
		centers.append((float(buttress) + 0.5) / buttress_count + rng.randf_range(-0.075, 0.075))
		widths.append(rng.randf_range(0.19, 0.27))
		depths.append(rng.randf_range(0.28, 0.48))
	for buttress in range(buttress_count):
		var previous_center: float = centers[buttress]
		var previous_width: float = widths[buttress]
		var previous_depth: float = depths[buttress]
		for segment in range(vertical_segments):
			var segment_low := bottom_y + wall_height * float(segment) / vertical_segments
			var segment_high := bottom_y + wall_height * float(segment + 1) / vertical_segments
			var next_center := clampf(previous_center + rng.randf_range(-0.10, 0.10), 0.08, 0.92)
			var next_width := clampf(previous_width + rng.randf_range(-0.065, 0.065), 0.13, 0.31)
			var next_depth := clampf(previous_depth + rng.randf_range(-0.16, 0.16), 0.16, 0.58)
			var left_bottom := edge_a.lerp(edge_b, clampf(previous_center - previous_width, 0.01, 0.99))
			var right_bottom := edge_a.lerp(edge_b, clampf(previous_center + previous_width, 0.01, 0.99))
			var left_top := edge_a.lerp(edge_b, clampf(next_center - next_width, 0.01, 0.99))
			var right_top := edge_a.lerp(edge_b, clampf(next_center + next_width, 0.01, 0.99))
			left_bottom.y = segment_low
			right_bottom.y = segment_low
			left_top.y = segment_high
			right_top.y = segment_high
			# Keep the wall's top edge flush to the hex cap, then let lower rock
			# sections bulge and break away from the regular hex outline.
			var bottom_fade := clampf((top_y - segment_low) / maxf(STEP_HEIGHT * 1.2, 0.08), 0.0, 1.0)
			var top_fade := clampf((top_y - segment_high) / maxf(STEP_HEIGHT * 1.2, 0.08), 0.0, 1.0)
			var ridge_fade := (bottom_fade + top_fade) * 0.5
			# A raised ridge gives each long buttress several broad, readable planes.
			var ridge := edge_a.lerp(edge_b, (previous_center + next_center) * 0.5 + rng.randf_range(-0.075, 0.075))
			ridge.y = (segment_low + segment_high) * 0.5 + rng.randf_range(-0.12, 0.12) * ridge_fade
			ridge += outward * (maxf(previous_depth, next_depth) + rng.randf_range(-0.10, 0.12)) * ridge_fade
			left_bottom += outward * (previous_depth + rng.randf_range(-0.085, 0.085)) * bottom_fade
			right_bottom += outward * (previous_depth * rng.randf_range(0.72, 1.12) + rng.randf_range(-0.085, 0.085)) * bottom_fade
			left_top += outward * (next_depth * rng.randf_range(0.72, 1.12) + rng.randf_range(-0.085, 0.085)) * top_fade
			right_top += outward * (next_depth + rng.randf_range(-0.085, 0.085)) * top_fade
			left_bottom.y += rng.randf_range(-0.07, 0.07) * bottom_fade
			right_bottom.y += rng.randf_range(-0.07, 0.07) * bottom_fade
			left_top.y += rng.randf_range(-0.07, 0.07) * top_fade
			right_top.y += rng.randf_range(-0.07, 0.07) * top_fade
			# Coherent radial breakup gives the large facets a natural rock profile.
			# The fade locks the upper rim to the hex top so adjacent caps still meet.
			left_bottom += _cliff_vertex_breakup(left_bottom, center, outward, bottom_fade)
			right_bottom += _cliff_vertex_breakup(right_bottom, center, outward, bottom_fade)
			left_top += _cliff_vertex_breakup(left_top, center, outward, top_fade)
			right_top += _cliff_vertex_breakup(right_top, center, outward, top_fade)
			ridge += _cliff_vertex_breakup(ridge, center, outward, ridge_fade)
			var facet_colors: Array[Color] = []
			for facet in range(4):
				var facet_color: Color = rock_colors[rng.randi_range(0, rock_colors.size() - 1)]
				if segment == vertical_segments - 1 and facet % 2 == 0:
					facet_color = facet_color.lightened(0.08)
				facet_colors.append(facet_color)
			_add_side_triangle(surface, left_bottom, right_bottom, ridge, facet_colors[0])
			_add_side_triangle(surface, right_bottom, right_top, ridge, facet_colors[1])
			_add_side_triangle(surface, right_top, left_top, ridge, facet_colors[2])
			_add_side_triangle(surface, left_top, left_bottom, ridge, facet_colors[3])
			previous_center = next_center
			previous_width = next_width
			previous_depth = next_depth

	# Moss stays sparse and close to the upper ledge, like growth in the rock seams.
	var moss_colors: Array[Color] = [Color("4d6038"), Color("687748"), Color("78834d")]
	var moss_count := clampi(ceili(edge_length * wall_height / 2.0), 1, 2)
	for moss_index in range(moss_count):
		var moss_t := rng.randf_range(0.12, 0.88)
		var moss_width := rng.randf_range(0.035, 0.085)
		var moss_y := top_y - rng.randf_range(0.04, minf(0.22, wall_height * 0.32))
		var moss_a := edge_a.lerp(edge_b, moss_t - moss_width) + outward * 0.28
		var moss_b := edge_a.lerp(edge_b, moss_t + moss_width) + outward * 0.28
		var moss_tip := edge_a.lerp(edge_b, moss_t + rng.randf_range(-0.025, 0.025)) + outward * 0.29
		moss_a.y = moss_y
		moss_b.y = moss_y + rng.randf_range(-0.025, 0.025)
		moss_tip.y = minf(top_y + 0.02, moss_y + rng.randf_range(0.05, 0.13))
		_add_side_triangle(surface, moss_a, moss_b, moss_tip, moss_colors[rng.randi_range(0, moss_colors.size() - 1)])

	# Tapered dark cracks cross the plates at irregular intervals.
	var fissure_count := clampi(ceili(wall_height / 2.8), 1, 3)
	for fissure in range(fissure_count):
		var t_center := rng.randf_range(0.16, 0.84)
		var crack_length := minf(rng.randf_range(0.55, 1.35), wall_height * 0.82)
		var crack_bottom := rng.randf_range(bottom_y, maxf(bottom_y, top_y - crack_length))
		var crack_top := crack_bottom + crack_length
		var drift := rng.randf_range(-0.14, 0.14)
		var crack_width := rng.randf_range(0.022, 0.042)
		var depth := outward * 0.34
		var left_bottom := edge_a.lerp(edge_b, t_center - crack_width) + depth
		var right_bottom := edge_a.lerp(edge_b, t_center + crack_width) + depth
		var left_top := edge_a.lerp(edge_b, t_center + drift - crack_width * 0.35) + depth
		var right_top := edge_a.lerp(edge_b, t_center + drift + crack_width * 0.35) + depth
		left_bottom.y = crack_bottom
		right_bottom.y = crack_bottom
		left_top.y = crack_top
		right_top.y = crack_top
		_add_side_triangle(surface, left_bottom, right_bottom, left_top, Color("30312c"))
		_add_side_triangle(surface, right_bottom, right_top, left_top, Color("282923"))

	_append_cliff_lip(
		ledge_surface,
		edge_a,
		edge_b,
		outward,
		top_y,
		HexGrid.TERRAIN_COLORS[data.terrain_at(cell)],
		rng
	)

func _cliff_vertex_breakup(point: Vector3, center: Vector3, outward: Vector3, fade: float) -> Vector3:
	var radial := Vector3(point.x - center.x, 0.0, point.z - center.z).normalized()
	# Higher horizontal sampling and a stretched vertical axis form broken strata.
	var broad_noise := cliff_noise.get_noise_3d(point.x * 3.5, point.y * 8.75, point.z * 3.5)
	var fine_noise := cliff_noise.get_noise_3d((point.x + 19.7) * 6.0, (point.y - 3.1) * 12.0, (point.z - 8.3) * 6.0)
	return (radial * broad_noise * 0.18 + outward * fine_noise * 0.08) * fade

func _append_cliff_backing_grid(surface: SurfaceTool, edge_a: Vector3, edge_b: Vector3, bottom_y: float, top_y: float, center: Vector3, outward: Vector3) -> void:
	var horizontal_segments := 8
	var vertical_segments := clampi(ceili((top_y - bottom_y) / 0.38), 6, 14)
	for y_step in range(vertical_segments):
		var low_ratio := float(y_step) / vertical_segments
		var high_ratio := float(y_step + 1) / vertical_segments
		var low_y := lerpf(bottom_y, top_y, low_ratio)
		var high_y := lerpf(bottom_y, top_y, high_ratio)
		var low_fade := clampf((top_y - low_y) / maxf(STEP_HEIGHT * 1.2, 0.08), 0.0, 1.0)
		var high_fade := clampf((top_y - high_y) / maxf(STEP_HEIGHT * 1.2, 0.08), 0.0, 1.0)
		for x_step in range(horizontal_segments):
			var left_ratio := float(x_step) / horizontal_segments
			var right_ratio := float(x_step + 1) / horizontal_segments
			var low_left := edge_a.lerp(edge_b, left_ratio)
			var low_right := edge_a.lerp(edge_b, right_ratio)
			var high_left := edge_a.lerp(edge_b, left_ratio)
			var high_right := edge_a.lerp(edge_b, right_ratio)
			low_left.y = low_y
			low_right.y = low_y
			high_left.y = high_y
			high_right.y = high_y
			low_left += _cliff_vertex_breakup(low_left, center, outward, low_fade)
			low_right += _cliff_vertex_breakup(low_right, center, outward, low_fade)
			high_left += _cliff_vertex_breakup(high_left, center, outward, high_fade)
			high_right += _cliff_vertex_breakup(high_right, center, outward, high_fade)
			var shade := 0.90 + cliff_noise.get_noise_3d(low_left.x * 1.7, low_y, low_left.z * 1.7) * 0.10
			var rock_color := Color("343832").darkened(1.0 - shade)
			_add_side_triangle(surface, low_left, high_left, high_right, rock_color)
			_add_side_triangle(surface, low_left, high_right, low_right, rock_color.darkened(0.07))

func _add_side_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Side UVs tile across the wall and rise with elevation, avoiding one stretched
	# hex-wide mapping on tall cliffs. The shader can use this for vertical strata.
	for point in [a, b, c]:
		surface.set_color(color)
		surface.set_uv(Vector2((point.x + point.z) * 0.65, point.y * 0.55))
		surface.add_vertex(point)

func _append_cliff_lip(surface: SurfaceTool, edge_a: Vector3, edge_b: Vector3, outward: Vector3, top_y: float, color: Color, rng: RandomNumberGenerator) -> void:
	var divisions := 5
	var previous_outer := Vector3.ZERO
	for segment in range(divisions + 1):
		var edge_t := float(segment) / divisions
		var width := rng.randf_range(0.22, 0.34)
		var drop := tan(deg_to_rad(27.0)) * width
		var inner := edge_a.lerp(edge_b, edge_t)
		inner.y = top_y + 0.006
		var outer := inner + outward * width
		outer.y = top_y - drop + rng.randf_range(-0.018, 0.018)
		if segment > 0:
			var previous_inner := edge_a.lerp(edge_b, float(segment - 1) / divisions)
			previous_inner.y = top_y + 0.006
			_add_triangle(surface, previous_inner, inner, outer, color)
			_add_triangle(surface, previous_inner, outer, previous_outer, color)
		previous_outer = outer

func refresh_cliffs() -> void:
	_rebuild_cliffs()

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.add_vertex(c)
