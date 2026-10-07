extends Node3D

enum EditMode { ELEVATION, GROUND }

const INVALID_CELL := Vector2i(-1, -1)
const CAP_HALF_HEIGHT: float = 0.09

var grid := HexGrid.new()
var board_view: HexBoardView
var camera_pivot: Node3D
var camera: Camera3D
var mode: EditMode = EditMode.ELEVATION
var elevation_delta: int = 1
var active_terrain: int = HexGrid.Terrain.GRASS
var brush_size: int = 1
var selected_cell := Vector2i(32, 64)
var readout: Label
var undo_button: Button
var redo_button: Button
var pan_button: Button
var pan_mode: bool = false
var _pointer_active: bool = false
var _pointer_pan: bool = false
var _last_pointer := Vector2.ZERO
var _stroke_before: Dictionary = {}
var _stroke_visited: Dictionary = {}
var _undo_history: Array[Dictionary] = []
var _redo_history: Array[Dictionary] = []

func _ready() -> void:
	camera_pivot = get_node("CameraPivot")
	camera = get_node("CameraPivot/Camera3D") as Camera3D
	camera.look_at(camera_pivot.global_position, Vector3.UP)
	board_view = HexBoardView.new()
	board_view.name = "BoardView"
	add_child(board_view)
	board_view.initialize(grid)
	board_view.set_selected(selected_cell)
	_build_editor_ui()
	_update_readout()

func _build_editor_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "EditorPanel"
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = 252.0
	panel.offset_bottom = -8.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.065, 0.058, 0.96)
	panel_style.border_color = Color("806f50")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)

	var title := Label.new()
	title.text = "HEX FOUNDRY"
	title.add_theme_color_override("font_color", Color("e1ca91"))
	title.add_theme_font_size_override("font_size", 19)
	content.add_child(title)
	var board_label := Label.new()
	board_label.text = "64 × 128  •  8,192 hexes"
	content.add_child(board_label)
	content.add_child(HSeparator.new())

	var mode_label := Label.new()
	mode_label.text = "ELEVATION"
	mode_label.add_theme_color_override("font_color", Color("c7b785"))
	content.add_child(mode_label)
	var elevation_row := HBoxContainer.new()
	content.add_child(elevation_row)
	_make_button(elevation_row, "Raise +1", func(): _set_elevation_tool(1))
	_make_button(elevation_row, "Lower −1", func(): _set_elevation_tool(-1))

	var brush_label := Label.new()
	brush_label.text = "BRUSH SIZE"
	brush_label.add_theme_color_override("font_color", Color("c7b785"))
	content.add_child(brush_label)
	var brush_picker := OptionButton.new()
	brush_picker.custom_minimum_size.y = 42.0
	for size in range(1, 6):
		brush_picker.add_item(str(size) + (" hex" if size == 1 else " hexes"), size)
	brush_picker.select(0)
	brush_picker.item_selected.connect(func(index: int): brush_size = index + 1)
	content.add_child(brush_picker)

	content.add_child(HSeparator.new())
	var terrain_label := Label.new()
	terrain_label.text = "GROUND TYPE"
	terrain_label.add_theme_color_override("font_color", Color("c7b785"))
	content.add_child(terrain_label)
	var terrain_grid := GridContainer.new()
	terrain_grid.columns = 2
	terrain_grid.add_theme_constant_override("h_separation", 6)
	terrain_grid.add_theme_constant_override("v_separation", 6)
	content.add_child(terrain_grid)
	for terrain in range(HexGrid.TERRAIN_NAMES.size()):
		var terrain_id := terrain
		_make_button(terrain_grid, HexGrid.TERRAIN_NAMES[terrain], func(): _set_ground_tool(terrain_id))

	var camera_label := Label.new()
	camera_label.text = "VIEW"
	camera_label.add_theme_color_override("font_color", Color("c7b785"))
	content.add_child(camera_label)
	var camera_row := HBoxContainer.new()
	content.add_child(camera_row)
	_make_button(camera_row, "−", func(): _zoom_camera(1.18))
	_make_button(camera_row, "+", func(): _zoom_camera(0.85))
	pan_button = Button.new()
	pan_button.text = "Pan view"
	pan_button.toggle_mode = true
	pan_button.custom_minimum_size.y = 42.0
	pan_button.toggled.connect(func(enabled: bool): pan_mode = enabled)
	camera_row.add_child(pan_button)

	var history_row := HBoxContainer.new()
	content.add_child(history_row)
	undo_button = _make_button(history_row, "Undo", _undo)
	undo_button.disabled = true
	redo_button = _make_button(history_row, "Redo", _redo)
	redo_button.disabled = true
	content.add_child(HSeparator.new())
	readout = Label.new()
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(readout)
	var help := Label.new()
	help.text = "Tap or drag on hexes to edit. Select Pan view before dragging to move around the board."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("a7ada5"))
	content.add_child(help)

func _make_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _set_elevation_tool(delta: int) -> void:
	mode = EditMode.ELEVATION
	elevation_delta = delta
	_update_readout()

func _set_ground_tool(terrain: int) -> void:
	mode = EditMode.GROUND
	active_terrain = terrain
	_update_readout()

func _update_readout() -> void:
	if readout == null:
		return
	var terrain_name := HexGrid.TERRAIN_NAMES[grid.terrain_at(selected_cell)]
	var operation := ("Raise +1" if elevation_delta > 0 else "Lower −1") if mode == EditMode.ELEVATION else "Paint " + HexGrid.TERRAIN_NAMES[active_terrain]
	readout.text = "Hex %d, %d  •  Level %d  •  %s\nTool: %s" % [selected_cell.x, selected_cell.y, grid.elevation_at(selected_cell), terrain_name, operation]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer()
	elif event is InputEventScreenDrag:
		_move_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer()
	elif event is InputEventMouseMotion and _pointer_active:
		_move_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_camera(0.9)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_camera(1.1)

func _begin_pointer(screen_position: Vector2) -> void:
	_pointer_active = true
	_pointer_pan = pan_mode
	_last_pointer = screen_position
	if _pointer_pan:
		return
	_stroke_before.clear()
	_stroke_visited.clear()
	_apply_at_screen(screen_position)

func _move_pointer(screen_position: Vector2) -> void:
	if not _pointer_active:
		return
	if _pointer_pan:
		_pan_camera(screen_position - _last_pointer)
	else:
		_apply_at_screen(screen_position)
	_last_pointer = screen_position

func _end_pointer() -> void:
	if not _pointer_active:
		return
	_pointer_active = false
	if not _pointer_pan and not _stroke_before.is_empty():
		_undo_history.append(_stroke_before.duplicate(true))
		_redo_history.clear()
		undo_button.disabled = false
		redo_button.disabled = true
		if _undo_history.size() > 100:
			_undo_history.pop_front()
		board_view.refresh_cliffs()
		_update_readout()

func _apply_at_screen(screen_position: Vector2) -> void:
	var cell := _pick_cell(screen_position)
	if not grid.contains(cell):
		return
	selected_cell = cell
	board_view.set_selected(cell)
	for brush_cell in grid.brush_cells(cell, brush_size):
		var index := grid.index_of(brush_cell)
		if _stroke_visited.has(index):
			continue
		_stroke_visited[index] = true
		var old_elevation := grid.elevation_at(brush_cell)
		var old_terrain := grid.terrain_at(brush_cell)
		if not _stroke_before.has(index):
			_stroke_before[index] = {"elevation": old_elevation, "terrain": old_terrain}
		if mode == EditMode.ELEVATION:
			grid.set_elevation(brush_cell, old_elevation + elevation_delta)
		else:
			grid.set_terrain(brush_cell, active_terrain)
		board_view.refresh_cell(brush_cell)
	_update_readout()

func _pick_cell(screen_position: Vector2) -> Vector2i:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	for level in range(HexGrid.MAX_ELEVATION, HexGrid.MIN_ELEVATION - 1, -1):
		var surface_y := level * HexGrid.HEIGHT_PER_LEVEL + CAP_HALF_HEIGHT
		var intersection: Variant = Plane(Vector3.UP, surface_y).intersects_ray(ray_origin, ray_direction)
		if intersection == null:
			continue
		var point: Vector3 = intersection
		var cell := grid.world_to_cell(point.x, point.z)
		if grid.contains(cell) and grid.elevation_at(cell) == level:
			return cell
	return INVALID_CELL

func _undo() -> void:
	if _undo_history.is_empty():
		return
	var change_set: Dictionary = _undo_history.pop_back()
	var redo_set: Dictionary = {}
	for index_variant in change_set.keys():
		var index := int(index_variant)
		var cell := grid.cell_from_index(index)
		var values: Dictionary = change_set[index]
		redo_set[index] = {"elevation": grid.elevation_at(cell), "terrain": grid.terrain_at(cell)}
		grid.set_elevation(cell, int(values["elevation"]))
		grid.set_terrain(cell, int(values["terrain"]))
		board_view.refresh_cell(cell)
	_redo_history.append(redo_set)
	board_view.refresh_cliffs()
	undo_button.disabled = _undo_history.is_empty()
	redo_button.disabled = false
	_update_readout()

func _redo() -> void:
	if _redo_history.is_empty():
		return
	var change_set: Dictionary = _redo_history.pop_back()
	var undo_set: Dictionary = {}
	for index_variant in change_set.keys():
		var index := int(index_variant)
		var cell := grid.cell_from_index(index)
		var values: Dictionary = change_set[index]
		undo_set[index] = {"elevation": grid.elevation_at(cell), "terrain": grid.terrain_at(cell)}
		grid.set_elevation(cell, int(values["elevation"]))
		grid.set_terrain(cell, int(values["terrain"]))
		board_view.refresh_cell(cell)
	_undo_history.append(undo_set)
	board_view.refresh_cliffs()
	undo_button.disabled = false
	redo_button.disabled = _redo_history.is_empty()
	_update_readout()

func _zoom_camera(factor: float) -> void:
	var position := camera.position * factor
	var distance := clampf(position.length(), 45.0, 260.0)
	camera.position = position.normalized() * distance

func _pan_camera(screen_delta: Vector2) -> void:
	var viewport_height := maxf(1.0, get_viewport().get_visible_rect().size.y)
	var distance := camera.position.length()
	var world_per_pixel := 2.0 * distance * tan(deg_to_rad(camera.fov * 0.5)) / viewport_height
	var right := camera.global_transform.basis.x
	var forward := camera.global_transform.basis.z
	var horizontal_right := Vector3(right.x, 0.0, right.z).normalized()
	var horizontal_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	camera_pivot.position += (-horizontal_right * screen_delta.x + horizontal_forward * screen_delta.y) * world_per_pixel
