extends Node3D

enum EditMode { ELEVATION, GROUND }
enum ElevationTool { RAISE, LOWER, FLATTEN, SMOOTH, HILL, RIDGE }

const INVALID_CELL := Vector2i(-1, -1)
const CAP_HALF_HEIGHT: float = 0.09

var grid := HexGrid.new()
var board_view: HexBoardView
var camera_pivot: Node3D
var camera: Camera3D
var mode: EditMode = EditMode.ELEVATION
var elevation_tool: int = ElevationTool.RAISE
var elevation_delta: int = 1
var active_terrain: int = HexGrid.Terrain.GRASS
var brush_size: int = 1
var selected_cell := Vector2i(32, 64)
var readout: Label
var tool_status: Label
var undo_button: Button
var redo_button: Button
var pan_button: Button
var fill_dialog: ConfirmationDialog
var _last_stroke_cell := INVALID_CELL
var _flatten_level: int = 0
var _tool_group := ButtonGroup.new()
var _sculpt_buttons: Array[Button] = []
var _terrain_buttons: Array[Button] = []
var _sample_button: Button
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 214.0
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	var title := Label.new()
	title.text = "HEX FOUNDRY"
	title.add_theme_color_override("font_color", Color("e1ca91"))
	title.add_theme_font_size_override("font_size", 19)
	content.add_child(title)
	var board_label := Label.new()
	board_label.text = "64 × 128  •  8,192 hexes"
	content.add_child(board_label)
	content.add_child(HSeparator.new())

	var sculpt_label := Label.new()
	sculpt_label.text = "SCULPT"
	sculpt_label.add_theme_color_override("font_color", Color("c7b785"))
	content.add_child(sculpt_label)
	var sculpt_grid := GridContainer.new()
	sculpt_grid.columns = 2
	sculpt_grid.add_theme_constant_override("h_separation", 6)
	sculpt_grid.add_theme_constant_override("v_separation", 6)
	content.add_child(sculpt_grid)
	_sculpt_buttons.clear()
	_tool_group.allow_unpress = false
	_add_sculpt_button(sculpt_grid, "Raise", ElevationTool.RAISE)
	_add_sculpt_button(sculpt_grid, "Lower", ElevationTool.LOWER)
	_add_sculpt_button(sculpt_grid, "Flatten", ElevationTool.FLATTEN)
	_add_sculpt_button(sculpt_grid, "Smooth", ElevationTool.SMOOTH)
	_add_sculpt_button(sculpt_grid, "Hill", ElevationTool.HILL)
	_add_sculpt_button(sculpt_grid, "Ridge", ElevationTool.RIDGE)

	var brush_label := Label.new()
	brush_label.text = "BRUSH SIZE"
	brush_label.add_theme_color_override("font_color", Color("c7b785"))
	content.add_child(brush_label)
	var brush_picker := OptionButton.new()
	brush_picker.custom_minimum_size.y = 42.0
	for size in range(1, 9):
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
	_terrain_buttons.clear()
	for terrain in range(HexGrid.TERRAIN_NAMES.size()):
		var terrain_id := terrain
		var terrain_button := _make_button(terrain_grid, HexGrid.TERRAIN_NAMES[terrain], func(): _set_ground_tool(terrain_id))
		terrain_button.toggle_mode = true
		terrain_button.button_group = _tool_group
		terrain_button.toggled.connect(func(pressed: bool):
			if pressed:
				_set_ground_tool(terrain_id)
		)
		_style_terrain_button(terrain_button, terrain_id)
		_terrain_buttons.append(terrain_button)
	_terrain_buttons[HexGrid.Terrain.GRASS].button_pressed = true
	var ground_actions := HBoxContainer.new()
	content.add_child(ground_actions)
	_sample_button = _make_button(ground_actions, "Sample", func(): _set_sample_tool())
	_sample_button.toggle_mode = true
	_sample_button.button_group = _tool_group
	_sample_button.toggled.connect(func(pressed: bool):
		if pressed:
			_set_sample_tool()
	)
	_make_button(ground_actions, "Fill board…", func(): _confirm_fill_ground())

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
	tool_status = Label.new()
	tool_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_status.add_theme_color_override("font_color", Color("a7ada5"))
	content.add_child(tool_status)

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
	help.text = "Raise and lower sculpted ground. Hills and ridges build landforms; Smooth softens them. Paint ground types or sample a hex."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("a7ada5"))
	content.add_child(help)
	fill_dialog = ConfirmationDialog.new()
	fill_dialog.title = "Fill ground layer"
	fill_dialog.confirmed.connect(_fill_ground)
	layer.add_child(fill_dialog)
	_update_tool_status()

func _add_sculpt_button(parent: Control, button_text: String, tool: int) -> void:
	var button := _make_button(parent, button_text, func(): _set_elevation_tool(tool))
	button.toggle_mode = true
	button.button_group = _tool_group
	button.toggled.connect(func(pressed: bool):
		if pressed:
			_set_elevation_tool(tool)
	)
	_sculpt_buttons.append(button)
	if tool == elevation_tool:
		button.button_pressed = true

func _style_terrain_button(button: Button, terrain: int) -> void:
	var base_color: Color = HexGrid.TERRAIN_COLORS[terrain].darkened(0.38)
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.set_corner_radius_all(5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = base_color.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = base_color.lightened(0.22)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("f1efe6"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)

func _make_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _set_elevation_tool(tool: int) -> void:
	mode = EditMode.ELEVATION
	elevation_tool = tool
	elevation_delta = -1 if tool == ElevationTool.LOWER else 1
	if tool < _sculpt_buttons.size() and not _sculpt_buttons[tool].button_pressed:
		_sculpt_buttons[tool].button_pressed = true
	_update_tool_status()
	_update_readout()

func _set_ground_tool(terrain: int) -> void:
	mode = EditMode.GROUND
	active_terrain = terrain
	if terrain < _terrain_buttons.size() and not _terrain_buttons[terrain].button_pressed:
		_terrain_buttons[terrain].button_pressed = true
	_update_tool_status()
	_update_readout()

func _set_sample_tool() -> void:
	mode = EditMode.GROUND
	if _sample_button != null and not _sample_button.button_pressed:
		_sample_button.button_pressed = true
	_update_tool_status()
	_update_readout()

func _update_tool_status() -> void:
	if tool_status == null:
		return
	if mode == EditMode.GROUND:
		tool_status.text = "Sample ground" if _sample_button != null and _sample_button.button_pressed else "Paint: " + HexGrid.TERRAIN_NAMES[active_terrain]
		return
	var tool_names := ["Raise +1", "Lower −1", "Flatten", "Smooth", "Hill", "Ridge"]
	tool_status.text = "Sculpt: " + tool_names[elevation_tool]

func _update_readout() -> void:
	if readout == null:
		return
	var terrain_name := HexGrid.TERRAIN_NAMES[grid.terrain_at(selected_cell)]
	var operation := tool_status.text
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
	_last_stroke_cell = INVALID_CELL
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
		_commit_undo(_stroke_before)
		if mode == EditMode.ELEVATION:
			board_view.refresh_cliffs()
		_update_readout()

func _apply_at_screen(screen_position: Vector2) -> void:
	var cell := _pick_cell(screen_position)
	if not grid.contains(cell):
		return
	selected_cell = cell
	board_view.set_selected(cell)
	if mode == EditMode.GROUND and _sample_button.button_pressed:
		active_terrain = grid.terrain_at(cell)
		_terrain_buttons[active_terrain].button_pressed = true
		mode = EditMode.GROUND
		_update_tool_status()
		_update_readout()
		return
	if _last_stroke_cell == INVALID_CELL:
		if elevation_tool == ElevationTool.FLATTEN:
			_flatten_level = grid.elevation_at(cell)
		_apply_brush_at(cell)
	else:
		for path_cell in grid.line_cells(_last_stroke_cell, cell):
			_apply_brush_at(path_cell)
	_last_stroke_cell = cell
	_update_readout()

func _apply_brush_at(center: Vector2i) -> void:
	var cells := grid.brush_cells(center, brush_size)
	if mode == EditMode.GROUND:
		for cell in cells:
			_apply_cell(cell, grid.elevation_at(cell), active_terrain)
		return
	if elevation_tool == ElevationTool.SMOOTH:
		var targets: Dictionary = {}
		for cell in cells:
			var total := grid.elevation_at(cell)
			var count := 1
			for edge in range(6):
				var neighbor := grid.neighbor_for_edge(cell, edge)
				if grid.contains(neighbor):
					total += grid.elevation_at(neighbor)
					count += 1
			targets[cell] = roundi(float(total) / count)
		for cell in cells:
			_apply_cell(cell, int(targets[cell]), grid.terrain_at(cell))
		return
	if elevation_tool == ElevationTool.HILL:
		var radius := maxi(1, brush_size - 1)
		var center_axial := grid.axial_coordinates(center)
		for cell in cells:
			var axial := grid.axial_coordinates(cell)
			var distance := maxi(absi(axial.x - center_axial.x), maxi(absi(axial.y - center_axial.y), absi(axial.x + axial.y - center_axial.x - center_axial.y)))
			var rise := maxi(1, roundi(4.0 * (1.0 - float(distance) / float(radius + 1))))
			_apply_cell(cell, grid.elevation_at(cell) + rise, grid.terrain_at(cell))
		return
	if elevation_tool == ElevationTool.RIDGE:
		for cell in cells:
			_apply_cell(cell, grid.elevation_at(cell) + 2, grid.terrain_at(cell))
			for edge in range(6):
				var neighbor := grid.neighbor_for_edge(cell, edge)
				if grid.contains(neighbor):
					_apply_cell(neighbor, grid.elevation_at(neighbor) + 1, grid.terrain_at(neighbor))
		return
	for cell in cells:
		var next_level := _flatten_level if elevation_tool == ElevationTool.FLATTEN else grid.elevation_at(cell) + elevation_delta
		_apply_cell(cell, next_level, grid.terrain_at(cell))

func _apply_cell(cell: Vector2i, next_elevation: int, next_terrain: int) -> void:
	if not grid.contains(cell):
		return
	var index := grid.index_of(cell)
	if _stroke_visited.has(index):
		return
	var old_elevation := grid.elevation_at(cell)
	var old_terrain := grid.terrain_at(cell)
	var bounded_elevation := clampi(next_elevation, HexGrid.MIN_ELEVATION, HexGrid.MAX_ELEVATION)
	if old_elevation == bounded_elevation and old_terrain == next_terrain:
		return
	_stroke_visited[index] = true
	_stroke_before[index] = {"elevation": old_elevation, "terrain": old_terrain}
	grid.set_elevation(cell, bounded_elevation)
	grid.set_terrain(cell, next_terrain)
	board_view.refresh_cell(cell)

func _commit_undo(change_set: Dictionary) -> void:
	_undo_history.append(change_set.duplicate(true))
	_redo_history.clear()
	if _undo_history.size() > 100:
		_undo_history.pop_front()
	undo_button.disabled = _undo_history.is_empty()
	redo_button.disabled = true

func _confirm_fill_ground() -> void:
	_set_ground_tool(active_terrain)
	fill_dialog.dialog_text = "Paint all %s hexes as %s? This can be undone." % ["8,192", HexGrid.TERRAIN_NAMES[active_terrain]]
	fill_dialog.popup_centered()

func _fill_ground() -> void:
	var change_set: Dictionary = {}
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		var cell := grid.cell_from_index(index)
		var old_terrain := grid.terrain_at(cell)
		if old_terrain == active_terrain:
			continue
		change_set[index] = {"elevation": grid.elevation_at(cell), "terrain": old_terrain}
		grid.set_terrain(cell, active_terrain)
		board_view.refresh_cell(cell)
	if change_set.is_empty():
		return
	_commit_undo(change_set)
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
