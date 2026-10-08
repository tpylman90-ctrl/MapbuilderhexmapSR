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

	var object := editor.call("_place_active_object", cell, false, "pine", 45.0, 1.25) as Node3D
	if object == null:
		_fail("Could not place the procedural pine stamp")
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
	if placed_objects.size() != 1:
		_fail("Map round-trip did not restore its placed object")
		return
	var restored := placed_objects[0] as Node3D
	if not restored.visible or str(restored.get_meta("map_object_type")) != "pine":
		_fail("Restored object metadata is incorrect")
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

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("Map builder round-trip, object history, and island generation passed.")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
