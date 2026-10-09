extends SceneTree

const TEST_PATH := "user://mapbuilder_roundtrip_test.hexmap"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Could not load the main editor scene")
		return
	var editor := packed.instantiate()
	root.add_child(editor)
	await process_frame

	var grid := editor.get("grid") as HexGrid
	if grid == null:
		_fail("Editor did not create its hex grid")
		return
	var cell := Vector2i(20, 40)
	grid.set_elevation(cell, 4)
	grid.set_terrain(cell, HexGrid.Terrain.DIRT)
	var board_view := editor.get("board_view") as HexBoardView
	board_view.refresh_cell(cell)
	board_view.set_distant_haze(false)
	if board_view.world_environment.environment.fog_enabled:
		_fail("Map display could not disable distant haze")
		return
	board_view.set_distant_haze(true)
	if not board_view.world_environment.environment.fog_enabled:
		_fail("Map display could not restore distant haze")
		return

	var object := editor.call("_place_active_object", cell, false, "pine", 45.0, 1.25) as Node3D
	if object == null:
		_fail("Could not place the procedural pine stamp")
		return
	var marker_cell := Vector2i(22, 40)
	var marker := editor.call("_place_active_object", marker_cell, false, "marker", 0.0, 1.0, "Crossroads") as Node3D
	if marker == null or str(marker.get_meta("map_object_label", "")) != "Crossroads":
		_fail("Could not place a named map marker")
		return
	editor.call("_save_map_file", TEST_PATH)
	if not FileAccess.file_exists(TEST_PATH):
		_fail("Map save did not create a file")
		return

	editor.call("_new_blank_map")
	await process_frame
	editor.call("_load_map_file", TEST_PATH)
	await process_frame
	if grid.elevation_at(cell) != 4 or grid.terrain_at(cell) != HexGrid.Terrain.DIRT:
		_fail("Map round-trip lost terrain or elevation data")
		return
	var placed_objects: Array = editor.get("_placed_objects")
	if placed_objects.size() != 2:
		_fail("Map round-trip did not restore the object stamp and marker")
		return
	var restored := placed_objects[0] as Node3D
	if not restored.visible or str(restored.get_meta("map_object_type")) != "pine":
		_fail("Restored object metadata is incorrect")
		return
	var restored_marker := placed_objects[1] as Node3D
	var restored_label := restored_marker.get_node_or_null("MarkerLabel") as Label3D
	if restored_label == null or restored_label.text != "Crossroads":
		_fail("Map round-trip did not preserve the location label")
		return

	editor.call("_erase_object_at", cell)
	if restored.visible:
		_fail("Erase Object did not hide the placed stamp")
		return
	editor.call("_undo")
	if not restored.visible:
		_fail("Undo did not restore an erased object")
		return
	editor.call("_redo")
	if restored.visible:
		_fail("Redo did not erase the object again")
		return

	var water_cell := Vector2i(21, 40)
	grid.set_terrain(water_cell, HexGrid.Terrain.WATER)
	board_view.refresh_cell(water_cell)
	board_view.set_water_subdivisions(2)
	var water_instances := board_view.get("water_instances") as MultiMesh
	if water_instances == null or water_instances.get_instance_transform(grid.index_of(water_cell)).basis.get_scale().length() < 1.0:
		_fail("Water terrain did not enable its animated water instance")
		return
	board_view.set_water_flow_direction(Vector2.LEFT)
	var flow_material := board_view.get("water_shader_material") as ShaderMaterial
	if flow_material == null:
		_fail("Water shader material was not created")
		return
	var applied_flow: Vector2 = flow_material.get_shader_parameter("flow_direction")
	if applied_flow.distance_to(Vector2.LEFT) > 0.001:
		_fail("Water flow direction was not applied to the wave material")
		return
	var shoreline_edge := 0
	var shore_neighbor := grid.neighbor_for_edge(water_cell, shoreline_edge)
	grid.set_terrain(shore_neighbor, HexGrid.Terrain.GRASS)
	board_view.refresh_cell(water_cell)
	var shoreline_edges: Dictionary = board_view.get("shoreline_edges")
	var shoreline_index := grid.index_of(water_cell) * 6 + shoreline_edge
	if not shoreline_edges.has(shoreline_index):
		_fail("Water-ground edge did not receive a shoreline highlight")
		return
	grid.set_terrain(shore_neighbor, HexGrid.Terrain.WATER)
	board_view.refresh_cell(shore_neighbor)
	if shoreline_edges.has(shoreline_index):
		_fail("Internal water-water edges should not render shoreline foam")
		return
	var low_vertex_count := (water_instances.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	board_view.set_water_subdivisions(6)
	var high_vertex_count := (water_instances.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if high_vertex_count <= low_vertex_count:
		_fail("Water mesh detail did not add wave vertices")
		return

	editor.call("_new_blank_map")
	editor.set("_generation_preset", "island")
	editor.call("_generate_map")
	var water_count := 0
	var raised_count := 0
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		var sample_cell := grid.cell_from_index(index)
		if grid.terrain_at(sample_cell) == HexGrid.Terrain.WATER:
			water_count += 1
		if grid.elevation_at(sample_cell) > 0:
			raised_count += 1
	if water_count == 0 or raised_count == 0:
		_fail("Island generator did not create both water and raised land")
		return
	editor.call("_undo")
	if grid.elevation_at(Vector2i(32, 64)) != 0:
		_fail("Undo did not restore the blank terrain before generation")
		return

	editor.set("_generation_preset", "ashenreach")
	editor.call("_generate_map")
	var ash_count := 0
	var lava_count := 0
	var basalt_count := 0
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		var sample_cell := grid.cell_from_index(index)
		match grid.terrain_at(sample_cell):
			HexGrid.Terrain.ASH:
				ash_count += 1
			HexGrid.Terrain.LAVA:
				lava_count += 1
			HexGrid.Terrain.STONE:
				basalt_count += 1
	if ash_count == 0 or lava_count == 0 or basalt_count == 0:
		_fail("Ashenreach did not create ash flats, lava, and basalt terrain")
		return
	var ashen_objects: Array = editor.get("_placed_objects")
	var object_types: Dictionary = {}
	for ashen_object in ashen_objects:
		if is_instance_valid(ashen_object) and ashen_object.visible:
			object_types[str(ashen_object.get_meta("map_object_type", ""))] = true
	if not object_types.has("ashen_keep") or not object_types.has("ash_tree") or not object_types.has("lava_vent"):
		_fail("Ashenreach is missing its Citadel, charred trees, or lava vents")
		return
	editor.call("_save_map_file", TEST_PATH)
	editor.call("_undo")
	if grid.terrain_at(Vector2i(41, 27)) == HexGrid.Terrain.LAVA:
		_fail("Undo did not restore terrain before Ashenreach generation")
		return
	editor.call("_new_blank_map")
	editor.call("_load_map_file", TEST_PATH)
	await process_frame
	if grid.terrain_at(Vector2i(41, 27)) != HexGrid.Terrain.LAVA:
		_fail("Ashenreach map round-trip did not preserve lava terrain")
		return
	var loaded_types: Dictionary = {}
	for loaded_object in editor.get("_placed_objects"):
		if is_instance_valid(loaded_object) and loaded_object.visible:
			loaded_types[str(loaded_object.get_meta("map_object_type", ""))] = true
	if not loaded_types.has("ashen_keep") or not loaded_types.has("lava_vent"):
		_fail("Ashenreach map round-trip did not restore volcanic objects")
		return
	var region_noise := FastNoiseLite.new()
	region_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	region_noise.frequency = 0.21
	var territory_presets: Array[String] = ["ravenwood", "blighted_marsh", "cursed_mire", "shadowfen", "frostpeaks", "drakeshard", "iron_plains", "veiled_sea", "ember_coast", "stormcrown"]
	for territory in territory_presets:
		var landmark: Vector2i = editor.call("_territory_landmark_cell", territory)
		var profile: Dictionary = editor.call("_territory_landscape", territory, landmark, 0.13, region_noise)
		var profile_terrain := int(profile.get("terrain", -1))
		if profile.is_empty() or profile_terrain < HexGrid.Terrain.GRASS or profile_terrain > HexGrid.Terrain.LAVA:
			_fail("Territory terrain profile failed for %s" % territory)
			return
		if str(editor.call("_generation_preset_title", territory)).is_empty():
			_fail("Territory preset is missing its display name: %s" % territory)
			return

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("Map builder round-trip, object history, all territory profiles, Ashenreach generation, and save/load passed.")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
