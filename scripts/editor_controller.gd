extends Node3D

enum EditMode { ELEVATION, GROUND, PLACEABLE }
enum ElevationTool { RAISE, LOWER, FLATTEN, SMOOTH, HILL, RIDGE }

const INVALID_CELL := Vector2i(-1, -1)
const CAP_HALF_HEIGHT: float = 0.09
const HOUSE_MODEL_PATH := "res://assets/models/cartoon_house.glb"
const HOUSE_MODEL_SCALE: float = 0.38
const HOUSE_MODEL_BOTTOM_Y: float = -1.166189

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
var zoom_slider: HSlider
var tilt_slider: HSlider
var orbit_slider: HSlider
var camera_distance: float = 235.0
var camera_tilt_degrees: float = 52.0
var camera_yaw_degrees: float = 42.0
var _syncing_camera_controls: bool = false
var fill_dialog: ConfirmationDialog
var _last_stroke_cell := INVALID_CELL
var _flatten_level: int = 0
var _sculpt_group := ButtonGroup.new()
var _terrain_group := ButtonGroup.new()
var _object_group := ButtonGroup.new()
var _sculpt_buttons: Array[Button] = []
var _terrain_buttons: Array[Button] = []
var _sample_button: Button
var _placeable_button: Button
var _object_buttons: Array[Button] = []
var _placed_objects: Array[Node3D] = []
var _marker_label_input: LineEdit
var _export_dialog: FileDialog
var _editor_layer: CanvasLayer
var _active_object_type := "house"
var _object_rotation_degrees := 0.0
var _object_scale := 1.0
var _generation_preset := "island"
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _load_confirmation: ConfirmationDialog
var _pending_load_path := ""
var _new_map_dialog: ConfirmationDialog
var _generation_dialog: ConfirmationDialog
var _outline_node: MeshInstance3D
var _grass_node: MultiMeshInstance3D
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
	_apply_camera_pose()
	board_view = HexBoardView.new()
	board_view.name = "BoardView"
	add_child(board_view)
	board_view.initialize(grid)
	_outline_node = board_view.outline_node
	_grass_node = board_view.grass_node
	board_view.set_selected(selected_cell)
	_build_editor_ui()
	_update_readout()

func _build_editor_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	_editor_layer = layer
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "EditorPanel"
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = 270.0
	panel.offset_bottom = -8.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.065, 0.058, 0.97)
	panel_style.border_color = Color("806f50")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 9.0
	panel_style.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 236.0
	content.add_theme_constant_override("separation", 7)
	scroll.add_child(content)

	var title := Label.new()
	title.text = "HEX FOUNDRY"
	title.add_theme_color_override("font_color", Color("e1ca91"))
	title.add_theme_font_size_override("font_size", 19)
	content.add_child(title)
	var board_label := Label.new()
	board_label.text = "64 × 128  •  8,192 hexes"
	board_label.add_theme_color_override("font_color", Color("e0e3da"))
	content.add_child(board_label)
	content.add_child(HSeparator.new())

	var tabs := TabContainer.new()
	tabs.name = "ToolSections"
	tabs.custom_minimum_size = Vector2(236.0, 420.0)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(tabs)

	var terrain_page := VBoxContainer.new()
	terrain_page.name = "Terrain"
	terrain_page.add_theme_constant_override("separation", 7)
	tabs.add_child(terrain_page)
	_add_section_title(terrain_page, "SCULPT")
	var sculpt_grid := GridContainer.new()
	sculpt_grid.columns = 2
	sculpt_grid.add_theme_constant_override("h_separation", 6)
	sculpt_grid.add_theme_constant_override("v_separation", 6)
	terrain_page.add_child(sculpt_grid)
	_sculpt_buttons.clear()
	_sculpt_group.allow_unpress = false
	_terrain_group.allow_unpress = false
	_object_group.allow_unpress = false
	_add_sculpt_button(sculpt_grid, "Raise", ElevationTool.RAISE)
	_add_sculpt_button(sculpt_grid, "Lower", ElevationTool.LOWER)
	_add_sculpt_button(sculpt_grid, "Flatten", ElevationTool.FLATTEN)
	_add_sculpt_button(sculpt_grid, "Smooth", ElevationTool.SMOOTH)
	_add_sculpt_button(sculpt_grid, "Hill", ElevationTool.HILL)
	_add_sculpt_button(sculpt_grid, "Ridge", ElevationTool.RIDGE)

	_add_section_title(terrain_page, "BRUSH SIZE")
	var brush_picker := OptionButton.new()
	brush_picker.custom_minimum_size.y = 40.0
	for size in range(1, 9):
		brush_picker.add_item(str(size) + (" hex" if size == 1 else " hexes"), size)
	brush_picker.select(0)
	brush_picker.item_selected.connect(func(index: int): brush_size = index + 1)
	terrain_page.add_child(brush_picker)

	_add_section_title(terrain_page, "GROUND PALETTE")
	var terrain_grid := GridContainer.new()
	terrain_grid.columns = 2
	terrain_grid.add_theme_constant_override("h_separation", 6)
	terrain_grid.add_theme_constant_override("v_separation", 6)
	terrain_page.add_child(terrain_grid)
	_terrain_buttons.clear()
	for terrain in range(HexGrid.TERRAIN_NAMES.size()):
		var terrain_id := terrain
		var terrain_button := _make_button(terrain_grid, HexGrid.TERRAIN_NAMES[terrain], func(): _set_ground_tool(terrain_id))
		terrain_button.toggle_mode = true
		terrain_button.button_group = _terrain_group
		terrain_button.toggled.connect(func(pressed: bool):
			if pressed:
				_set_ground_tool(terrain_id)
		)
		_style_terrain_button(terrain_button, terrain_id)
		_terrain_buttons.append(terrain_button)
	_terrain_buttons[HexGrid.Terrain.GRASS].button_pressed = true

	var ground_actions := HBoxContainer.new()
	terrain_page.add_child(ground_actions)
	_sample_button = _make_button(ground_actions, "Sample", func(): _set_sample_tool())
	_sample_button.toggle_mode = true
	_sample_button.button_group = _terrain_group
	_sample_button.toggled.connect(func(pressed: bool):
		if pressed:
			_set_sample_tool()
	)
	_make_button(ground_actions, "Fill all…", _confirm_fill_ground)

	var objects_page := VBoxContainer.new()
	objects_page.name = "Objects"
	objects_page.add_theme_constant_override("separation", 7)
	tabs.add_child(objects_page)
	_add_section_title(objects_page, "OBJECT STAMPS")
	var object_grid := GridContainer.new()
	object_grid.columns = 2
	object_grid.add_theme_constant_override("h_separation", 6)
	object_grid.add_theme_constant_override("v_separation", 6)
	objects_page.add_child(object_grid)
	_object_buttons.clear()
	_add_object_button(object_grid, "House", "house")
	_add_object_button(object_grid, "Cottage", "cottage")
	_add_object_button(object_grid, "Stone Keep", "castle")
	_add_object_button(object_grid, "Bridge", "bridge")
	_add_object_button(object_grid, "Stone Wall", "wall")
	_add_object_button(object_grid, "Wood Fence", "fence")
	_add_object_button(object_grid, "Oak Tree", "oak")
	_add_object_button(object_grid, "Pine", "pine")
	_add_object_button(object_grid, "Boulder", "boulder")
	_add_object_button(object_grid, "Marker / Label", "marker")
	_add_object_button(object_grid, "Erase Object", "erase")
	_add_section_title(objects_page, "LOCATION LABEL")
	_marker_label_input = LineEdit.new()
	_marker_label_input.text = "Landmark"
	_marker_label_input.placeholder_text = "Settlement, dungeon, or landmark"
	_marker_label_input.max_length = 36
	_marker_label_input.text_changed.connect(func(_text: String): _update_tool_status())
	objects_page.add_child(_marker_label_input)
	_add_section_title(objects_page, "STAMP TRANSFORM")
	var transform_row := HBoxContainer.new()
	objects_page.add_child(transform_row)
	_make_button(transform_row, "Rotate −", func(): _rotate_stamp(-30.0))
	_make_button(transform_row, "Rotate +", func(): _rotate_stamp(30.0))
	var scale_row := HBoxContainer.new()
	objects_page.add_child(scale_row)
	_make_button(scale_row, "Scale −", func(): _scale_stamp(0.85))
	_make_button(scale_row, "Scale +", func(): _scale_stamp(1.18))
	var object_help := Label.new()
	object_help.text = "Choose a stamp, then tap a hex to place it. Name and place map labels for settlements, dungeons, or landmarks. Rotate and scale apply to the next stamp."
	object_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	object_help.add_theme_color_override("font_color", Color("a7ada5"))
	objects_page.add_child(object_help)

	var map_page := VBoxContainer.new()
	map_page.name = "Map"
	map_page.add_theme_constant_override("separation", 7)
	tabs.add_child(map_page)
	_add_section_title(map_page, "MAP FILE")
	var file_row := HBoxContainer.new()
	map_page.add_child(file_row)
	_make_button(file_row, "Save…", _open_save_dialog)
	_make_button(file_row, "Load…", _open_load_dialog)
	_make_button(map_page, "Export Current View as PNG…", _open_export_dialog)
	var file_help := Label.new()
	file_help.text = "Save the full map, terrain, elevation, and object stamps as a portable .hexmap file."
	file_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	file_help.add_theme_color_override("font_color", Color("a7ada5"))
	map_page.add_child(file_help)

	_add_section_title(map_page, "WORLD GENERATION")
	_make_button(map_page, "Generate Island", func(): _confirm_generation("island"))
	_make_button(map_page, "Generate Highlands", func(): _confirm_generation("highlands"))
	_make_button(map_page, "Generate Kingdom", func(): _confirm_generation("kingdom"))
	_make_button(map_page, "New Blank Map…", func(): _new_map_dialog.popup_centered())

	_add_section_title(map_page, "SURFACE MATERIALS")
	var surface_label := Label.new()
	surface_label.text = "Ground texture detail"
	surface_label.add_theme_color_override("font_color", Color("a7ada5"))
	map_page.add_child(surface_label)
	var surface_slider := HSlider.new()
	surface_slider.min_value = 0.0
	surface_slider.max_value = 1.0
	surface_slider.step = 0.05
	surface_slider.value = 0.78
	surface_slider.value_changed.connect(func(value: float): board_view.set_surface_detail(value))
	map_page.add_child(surface_slider)
	var cliff_label := Label.new()
	cliff_label.text = "Cliff rock detail"
	cliff_label.add_theme_color_override("font_color", Color("a7ada5"))
	map_page.add_child(cliff_label)
	var cliff_slider := HSlider.new()
	cliff_slider.min_value = 0.0
	cliff_slider.max_value = 1.0
	cliff_slider.step = 0.05
	cliff_slider.value = 0.82
	cliff_slider.value_changed.connect(func(value: float): board_view.set_cliff_detail(value))
	map_page.add_child(cliff_slider)

	_add_section_title(map_page, "WATER")
	var water_label := Label.new()
	water_label.text = "Wave mesh detail"
	water_label.add_theme_color_override("font_color", Color("a7ada5"))
	map_page.add_child(water_label)
	var water_detail := OptionButton.new()
	water_detail.add_item("Low · 2 subdivisions", 2)
	water_detail.add_item("Balanced · 4 subdivisions", 4)
	water_detail.add_item("High · 6 subdivisions", 6)
	water_detail.select(1)
	water_detail.item_selected.connect(func(item: int):
		board_view.set_water_subdivisions(water_detail.get_item_id(item))
	)
	map_page.add_child(water_detail)

	var flow_label := Label.new()
	flow_label.text = "Water flow direction"
	flow_label.add_theme_color_override("font_color", Color("a7ada5"))
	map_page.add_child(flow_label)
	var flow_direction := OptionButton.new()
	var flow_names := ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
	var flow_vectors: Array[Vector2] = [
		Vector2(0.0, -1.0), Vector2(0.707107, -0.707107), Vector2(1.0, 0.0), Vector2(0.707107, 0.707107),
		Vector2(0.0, 1.0), Vector2(-0.707107, 0.707107), Vector2(-1.0, 0.0), Vector2(-0.707107, -0.707107)
	]
	for flow_name in flow_names:
		flow_direction.add_item(flow_name)
	flow_direction.select(3)
	flow_direction.item_selected.connect(func(item: int):
		board_view.set_water_flow_direction(flow_vectors[item])
	)
	map_page.add_child(flow_direction)

	_add_section_title(map_page, "DISPLAY")
	var grid_toggle := CheckButton.new()
	grid_toggle.text = "Hex outlines"
	grid_toggle.button_pressed = false
	grid_toggle.toggled.connect(func(enabled: bool):
		board_view.set_hex_overlay_visible(enabled)
	)
	map_page.add_child(grid_toggle)
	var grass_toggle := CheckButton.new()
	grass_toggle.text = "Grass detail"
	grass_toggle.button_pressed = true
	grass_toggle.toggled.connect(func(enabled: bool):
		if _grass_node != null:
			_grass_node.visible = enabled
	)
	map_page.add_child(grass_toggle)
	var haze_toggle := CheckButton.new()
	haze_toggle.text = "Distant haze"
	haze_toggle.button_pressed = true
	haze_toggle.toggled.connect(func(enabled: bool): board_view.set_distant_haze(enabled))
	map_page.add_child(haze_toggle)

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

	fill_dialog = ConfirmationDialog.new()
	fill_dialog.title = "Fill ground layer"
	fill_dialog.confirmed.connect(_fill_ground)
	layer.add_child(fill_dialog)
	_new_map_dialog = ConfirmationDialog.new()
	_new_map_dialog.title = "Create a blank map"
	_new_map_dialog.dialog_text = "Clear the terrain, elevations, and placed objects? This starts a new blank map."
	_new_map_dialog.confirmed.connect(_new_blank_map)
	layer.add_child(_new_map_dialog)
	_generation_dialog = ConfirmationDialog.new()
	_generation_dialog.title = "Generate terrain"
	_generation_dialog.confirmed.connect(_generate_map)
	layer.add_child(_generation_dialog)
	_save_dialog = _make_map_file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	_save_dialog.file_selected.connect(_save_map_file)
	layer.add_child(_save_dialog)
	_load_dialog = _make_map_file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	_load_dialog.file_selected.connect(_request_load_map)
	layer.add_child(_load_dialog)
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_USERDATA
	_export_dialog.current_dir = "user://"
	_export_dialog.current_file = "HexFoundry.png"
	_export_dialog.filters = PackedStringArray(["*.png ; PNG Image"])
	_export_dialog.size = Vector2(640.0, 480.0)
	_export_dialog.file_selected.connect(_export_map_png)
	layer.add_child(_export_dialog)
	_load_confirmation = ConfirmationDialog.new()
	_load_confirmation.title = "Load map"
	_load_confirmation.confirmed.connect(func(): _load_map_file(_pending_load_path))
	layer.add_child(_load_confirmation)
	_build_camera_hud(layer)
	_update_tool_status()
	_update_history_buttons()

func _add_section_title(parent: Control, title_text: String) -> void:
	var label := Label.new()
	label.text = title_text
	label.add_theme_color_override("font_color", Color("c7b785"))
	parent.add_child(label)

func _add_object_button(parent: Control, button_text: String, object_kind: String) -> void:
	var button := _make_button(parent, button_text, func(): _set_object_tool(object_kind))
	button.toggle_mode = true
	button.button_group = _object_group
	button.set_meta("object_kind", object_kind)
	button.toggled.connect(func(pressed: bool):
		if pressed:
			_set_object_tool(object_kind)
	)
	_object_buttons.append(button)

func _make_map_file_dialog(mode_value: int) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode_value
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.current_dir = "user://"
	dialog.filters = PackedStringArray(["*.hexmap ; Hex Foundry Map"])
	dialog.size = Vector2(640.0, 480.0)
	return dialog

func _open_save_dialog() -> void:
	_save_dialog.current_file = "MyMap.hexmap"
	_save_dialog.popup_centered()

func _open_load_dialog() -> void:
	_load_dialog.popup_centered()

func _open_export_dialog() -> void:
	_export_dialog.popup_centered()

func _request_load_map(path: String) -> void:
	_pending_load_path = path
	_load_confirmation.dialog_text = "Replace the current board with %s? Save the current map first if you want to keep it." % path.get_file()
	_load_confirmation.popup_centered()

func _export_map_png(path: String) -> void:
	var ui_was_visible := _editor_layer.visible
	_editor_layer.visible = false
	await get_tree().create_timer(0.15).timeout
	var viewport_texture := get_viewport().get_texture()
	_editor_layer.visible = ui_was_visible
	if viewport_texture == null:
		tool_status.text = "PNG export is unavailable in this renderer"
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		tool_status.text = "PNG export could not capture the current view"
		return
	var final_path := path if path.get_extension().to_lower() == "png" else path + ".png"
	var error := image.save_png(final_path)
	if error != OK:
		tool_status.text = "PNG export failed: %s" % error_string(error)
		return
	tool_status.text = "Exported current view to %s" % final_path.get_file()
	_update_readout()

func _build_camera_hud(layer: CanvasLayer) -> void:
	var hud := PanelContainer.new()
	hud.name = "CameraHUD"
	hud.anchor_left = 1.0
	hud.anchor_right = 1.0
	hud.offset_left = -258.0
	hud.offset_right = -10.0
	hud.offset_top = 10.0
	hud.offset_bottom = 258.0
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.055, 0.065, 0.058, 0.96)
	hud_style.border_color = Color("806f50")
	hud_style.set_border_width_all(1)
	hud_style.set_corner_radius_all(10)
	hud_style.content_margin_left = 10.0
	hud_style.content_margin_right = 10.0
	hud_style.content_margin_top = 8.0
	hud_style.content_margin_bottom = 8.0
	hud.add_theme_stylebox_override("panel", hud_style)
	layer.add_child(hud)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	hud.add_child(controls)
	var title := Label.new()
	title.text = "CAMERA"
	title.add_theme_color_override("font_color", Color("e1ca91"))
	controls.add_child(title)

	var button_row := HBoxContainer.new()
	controls.add_child(button_row)
	_make_button(button_row, "−", func(): _zoom_camera(1.15))
	_make_button(button_row, "+", func(): _zoom_camera(0.87))
	pan_button = Button.new()
	pan_button.text = "Slide"
	pan_button.toggle_mode = true
	pan_button.custom_minimum_size.y = 42.0
	pan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pan_button.toggled.connect(func(enabled: bool): pan_mode = enabled)
	button_row.add_child(pan_button)
	_make_button(button_row, "Home", _reset_camera)

	var zoom_label := Label.new()
	zoom_label.text = "Zoom"
	zoom_label.add_theme_color_override("font_color", Color("a7ada5"))
	controls.add_child(zoom_label)
	zoom_slider = _make_camera_slider(controls, 7.0, 360.0, camera_distance, _on_zoom_slider_changed)
	var tilt_label := Label.new()
	tilt_label.text = "Tilt"
	tilt_label.add_theme_color_override("font_color", Color("a7ada5"))
	controls.add_child(tilt_label)
	tilt_slider = _make_camera_slider(controls, 20.0, 84.0, camera_tilt_degrees, _on_tilt_slider_changed)
	var orbit_label := Label.new()
	orbit_label.text = "Orbit"
	orbit_label.add_theme_color_override("font_color", Color("a7ada5"))
	controls.add_child(orbit_label)
	orbit_slider = _make_camera_slider(controls, 0.0, 360.0, camera_yaw_degrees, _on_orbit_slider_changed)

func _make_camera_slider(parent: Control, minimum: float, maximum: float, initial_value: float, callback: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1.0
	slider.value = initial_value
	slider.custom_minimum_size.y = 24.0
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	return slider

func _add_sculpt_button(parent: Control, button_text: String, tool: int) -> void:
	var button := _make_button(parent, button_text, func(): _set_elevation_tool(tool))
	button.toggle_mode = true
	button.button_group = _sculpt_group
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

func _set_house_place_tool() -> void:
	_set_object_tool("house")

func _set_object_tool(object_kind: String) -> void:
	mode = EditMode.PLACEABLE
	_active_object_type = object_kind
	for button in _object_buttons:
		if button.get_meta("object_kind", "") == object_kind and not button.button_pressed:
			button.button_pressed = true
	_update_tool_status()
	_update_readout()

func _rotate_stamp(delta_degrees: float) -> void:
	_object_rotation_degrees = fposmod(_object_rotation_degrees + delta_degrees, 360.0)
	_update_tool_status()
	_update_readout()

func _scale_stamp(factor: float) -> void:
	_object_scale = clampf(_object_scale * factor, 0.55, 2.4)
	_update_tool_status()
	_update_readout()

func _object_label(object_kind: String) -> String:
	match object_kind:
		"house": return "Cartoon House"
		"cottage": return "Village Cottage"
		"castle": return "Stone Keep"
		"bridge": return "Stone Bridge"
		"wall": return "Stone Wall"
		"fence": return "Wood Fence"
		"oak": return "Oak Tree"
		"pine": return "Pine"
		"boulder": return "Boulder"
		"marker": return "Map Label"
		"erase": return "Erase Object"
		_: return object_kind.capitalize()

func _update_tool_status() -> void:
	if tool_status == null:
		return
	if mode == EditMode.PLACEABLE:
		if _active_object_type == "erase":
			tool_status.text = "Tap a placed object to erase it"
		elif _active_object_type == "marker":
			var label_text := _marker_label_input.text.strip_edges() if _marker_label_input != null else "Landmark"
			tool_status.text = "Place map label: %s" % (label_text if not label_text.is_empty() else "Landmark")
		else:
			tool_status.text = "Stamp: %s  •  %d°  •  %d%%" % [_object_label(_active_object_type), roundi(_object_rotation_degrees), roundi(_object_scale * 100.0)]
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
	if event is InputEventMagnifyGesture:
		_zoom_camera(1.0 / maxf(event.factor, 0.1))
	elif event is InputEventPanGesture:
		_pan_camera(event.delta)
	elif event is InputEventScreenTouch:
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
	elif mode != EditMode.PLACEABLE:
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
	if mode == EditMode.PLACEABLE:
		_place_active_object(cell)
		_last_stroke_cell = cell
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

func _place_active_object(cell: Vector2i, record_history: bool = true, object_kind: String = "", rotation_degrees: float = -1.0, object_scale: float = -1.0, object_label: String = "") -> Node3D:
	var kind := _active_object_type if object_kind.is_empty() else object_kind
	if kind == "erase":
		_erase_object_at(cell)
		return null
	var node := _create_placeable_node(kind)
	if node == null:
		return null
	var rotation := _object_rotation_degrees if rotation_degrees < 0.0 else rotation_degrees
	var scale_factor := _object_scale if object_scale < 0.0 else object_scale
	var center := grid.world_center(cell)
	var surface_y := board_view._surface_height_at(center.x, center.z)
	if kind == "house":
		node.scale = Vector3.ONE * HOUSE_MODEL_SCALE * scale_factor
		surface_y -= HOUSE_MODEL_BOTTOM_Y * HOUSE_MODEL_SCALE * scale_factor
	elif kind == "castle":
		# One movement cell is approximately 20 feet across; the keep occupies a
		# substantial 8-cell footprint instead of reading like a tiny token.
		node.scale = Vector3(2.35, 1.35, 2.35) * scale_factor
	else:
		node.scale = Vector3.ONE * scale_factor
	node.position = Vector3(center.x, surface_y, center.z)
	node.rotation.y = deg_to_rad(rotation)
	node.set_meta("map_object_type", kind)
	node.set_meta("map_cell", cell)
	node.set_meta("map_footprint_cells", _object_footprint_cells(kind, cell))
	node.set_meta("map_object_scale", scale_factor)
	node.set_meta("map_object_rotation", rotation)
	if kind == "marker":
		var label_text := object_label.strip_edges()
		if label_text.is_empty() and _marker_label_input != null:
			label_text = _marker_label_input.text.strip_edges()
		if label_text.is_empty():
			label_text = "Landmark"
		node.set_meta("map_object_label", label_text)
		var marker_label := node.get_node_or_null("MarkerLabel") as Label3D
		if marker_label != null:
			marker_label.text = label_text
	board_view.add_child(node)
	_placed_objects.append(node)
	if record_history:
		_commit_undo({"_object_action": "place", "_object_node": node})
	return node

func _create_placeable_node(kind: String) -> Node3D:
	if kind == "house":
		var packed_scene := load(HOUSE_MODEL_PATH) as PackedScene
		if packed_scene == null:
			tool_status.text = "Could not load cartoon_house.glb"
			return null
		var house := packed_scene.instantiate() as Node3D
		if house == null:
			tool_status.text = "House model root must be a Node3D"
			return null
		house.name = "PlacedCartoonHouse_%d" % (_placed_objects.size() + 1)
		_set_placeable_materials(house)
		return house

	var root := Node3D.new()
	root.name = "Placed" + _object_label(kind).replace(" ", "")
	match kind:
		"cottage":
			var plaster := BoxMesh.new()
			plaster.size = Vector3(1.36, 0.92, 1.18)
			_add_object_mesh(root, plaster, Vector3(0.0, 0.48, 0.0), Color("b79b70"))
			var roof := PrismMesh.new()
			roof.size = Vector3(1.62, 1.18, 1.42)
			_add_object_mesh(root, roof, Vector3(0.0, 1.38, 0.0), Color("594038"))
			var door := BoxMesh.new()
			door.size = Vector3(0.28, 0.58, 0.07)
			_add_object_mesh(root, door, Vector3(0.0, 0.29, 0.62), Color("493528"))
			var window_mesh := BoxMesh.new()
			window_mesh.size = Vector3(0.22, 0.24, 0.06)
			_add_object_mesh(root, window_mesh, Vector3(-0.42, 0.58, 0.62), Color("61757a"))
			_add_object_mesh(root, window_mesh, Vector3(0.42, 0.58, 0.62), Color("61757a"))
			var chimney := CylinderMesh.new()
			chimney.top_radius = 0.11
			chimney.bottom_radius = 0.13
			chimney.height = 0.75
			chimney.radial_segments = 5
			_add_object_mesh(root, chimney, Vector3(0.42, 1.73, -0.24), Color("776957"))
		"castle":
			var curtain_wall := BoxMesh.new()
			curtain_wall.size = Vector3(5.3, 1.55, 0.42)
			_add_object_mesh(root, curtain_wall, Vector3(0.0, 1.05, -2.55), Color("77756b"))
			_add_object_mesh(root, curtain_wall, Vector3(-2.55, 1.05, 0.0), Color("716f66"), Vector3(0.16, 1.0, 1.0))
			_add_object_mesh(root, curtain_wall, Vector3(2.55, 1.05, 0.0), Color("716f66"), Vector3(0.16, 1.0, 1.0))
			var gate_left := BoxMesh.new()
			gate_left.size = Vector3(1.55, 1.55, 0.42)
			_add_object_mesh(root, gate_left, Vector3(-1.86, 1.05, 2.55), Color("77756b"))
			_add_object_mesh(root, gate_left, Vector3(1.86, 1.05, 2.55), Color("77756b"))
			var gatehouse := BoxMesh.new()
			gatehouse.size = Vector3(1.42, 2.3, 0.55)
			_add_object_mesh(root, gatehouse, Vector3(0.0, 1.25, 2.55), Color("857f72"))
			var keep := BoxMesh.new()
			keep.size = Vector3(2.45, 3.55, 2.15)
			_add_object_mesh(root, keep, Vector3(0.0, 1.80, -0.10), Color("8c887b"))
			var keep_roof := CylinderMesh.new()
			keep_roof.top_radius = 0.0
			keep_roof.bottom_radius = 1.55
			keep_roof.height = 1.25
			keep_roof.radial_segments = 4
			_add_object_mesh(root, keep_roof, Vector3(0.0, 4.18, -0.10), Color("59463d"), Vector3(1.0, 1.0, 0.78))
			for side in range(4):
				var tower := CylinderMesh.new()
				tower.top_radius = 0.48
				tower.bottom_radius = 0.58
				tower.height = 2.75
				tower.radial_segments = 8
				var tx := -2.48 if side < 2 else 2.48
				var tz := -2.48 if side % 2 == 0 else 2.48
				_add_object_mesh(root, tower, Vector3(tx, 1.40, tz), Color("858174"))
				var tower_roof := CylinderMesh.new()
				tower_roof.top_radius = 0.0
				tower_roof.bottom_radius = 0.62
				tower_roof.height = 0.90
				tower_roof.radial_segments = 8
				_add_object_mesh(root, tower_roof, Vector3(tx, 3.20, tz), Color("58443b"))
			var merlon := BoxMesh.new()
			merlon.size = Vector3(0.34, 0.40, 0.42)
			for crenel in range(12):
				var offset := -2.35 + float(crenel) * 0.43
				_add_object_mesh(root, merlon, Vector3(offset, 2.00, -2.55), Color("969184"))
				if crenel < 4 or crenel > 7:
					_add_object_mesh(root, merlon, Vector3(offset, 2.00, 2.55), Color("969184"))
			var side_merlon := BoxMesh.new()
			side_merlon.size = Vector3(0.42, 0.40, 0.34)
			for crenel in range(10):
				var offset := -1.95 + float(crenel) * 0.43
				_add_object_mesh(root, side_merlon, Vector3(-2.55, 2.00, offset), Color("969184"))
				_add_object_mesh(root, side_merlon, Vector3(2.55, 2.00, offset), Color("969184"))
		"wall":
			var wall_body := BoxMesh.new()
			wall_body.size = Vector3(2.45, 1.15, 0.34)
			_add_object_mesh(root, wall_body, Vector3(0.0, 0.62, 0.0), Color("77776d"))
			var wall_cap := BoxMesh.new()
			wall_cap.size = Vector3(2.58, 0.16, 0.43)
			_add_object_mesh(root, wall_cap, Vector3(0.0, 1.27, 0.0), Color("989286"))
			for merlon_index in range(5):
				var merlon := BoxMesh.new()
				merlon.size = Vector3(0.30, 0.30, 0.40)
				_add_object_mesh(root, merlon, Vector3(-0.98 + float(merlon_index) * 0.49, 1.49, 0.0), Color("a19b8f"))
		"fence":
			var rail := BoxMesh.new()
			rail.size = Vector3(2.10, 0.12, 0.10)
			_add_object_mesh(root, rail, Vector3(0.0, 0.48, 0.0), Color("765237"))
			_add_object_mesh(root, rail, Vector3(0.0, 0.88, 0.0), Color("8b6540"))
			var fence_post := BoxMesh.new()
			fence_post.size = Vector3(0.16, 1.05, 0.16)
			for post_index in range(4):
				_add_object_mesh(root, fence_post, Vector3(-1.0 + float(post_index) * 0.67, 0.54, 0.0), Color("63462f"))
		"bridge":
			var deck := BoxMesh.new()
			deck.size = Vector3(7.8, 0.24, 1.75)
			_add_object_mesh(root, deck, Vector3(0.0, 0.34, 0.0), Color("72563a"))
			var plank := BoxMesh.new()
			plank.size = Vector3(0.13, 0.08, 1.34)
			for plank_index in range(27):
				var x_offset := -3.72 + float(plank_index) * 0.285
				_add_object_mesh(root, plank, Vector3(x_offset, 0.48, 0.0), Color("92704a"))
			var rail := BoxMesh.new()
			rail.size = Vector3(7.8, 0.14, 0.12)
			_add_object_mesh(root, rail, Vector3(0.0, 0.96, -0.88), Color("634b35"))
			_add_object_mesh(root, rail, Vector3(0.0, 0.96, 0.88), Color("634b35"))
			var post := BoxMesh.new()
			post.size = Vector3(0.14, 0.60, 0.14)
			for post_index in range(13):
				var x_offset := -3.72 + float(post_index) * 0.62
				_add_object_mesh(root, post, Vector3(x_offset, 0.78, -0.88), Color("634b35"))
				_add_object_mesh(root, post, Vector3(x_offset, 0.78, 0.88), Color("634b35"))
		"oak":
			var oak_trunk := CylinderMesh.new()
			oak_trunk.top_radius = 0.07
			oak_trunk.bottom_radius = 0.11
			oak_trunk.height = 0.86
			oak_trunk.radial_segments = 6
			_add_object_mesh(root, oak_trunk, Vector3(0.0, 0.43, 0.0), Color("765338"))
			var crown := SphereMesh.new()
			crown.radius = 0.43
			crown.height = 0.78
			crown.radial_segments = 6
			crown.rings = 3
			_add_object_mesh(root, crown, Vector3(0.0, 1.05, 0.0), Color("47753c"), Vector3(1.0, 0.86, 1.0))
			_add_object_mesh(root, crown, Vector3(-0.24, 0.98, 0.08), Color("588642"), Vector3(0.70, 0.72, 0.70))
			_add_object_mesh(root, crown, Vector3(0.23, 1.12, -0.10), Color("64934a"), Vector3(0.66, 0.68, 0.66))
		"pine":
			var pine_trunk := CylinderMesh.new()
			pine_trunk.top_radius = 0.055
			pine_trunk.bottom_radius = 0.09
			pine_trunk.height = 1.48
			pine_trunk.radial_segments = 6
			_add_object_mesh(root, pine_trunk, Vector3(0.0, 0.74, 0.0), Color("74513a"))
			for tier in range(3):
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.43 - float(tier) * 0.055
				cone.height = 0.78
				cone.radial_segments = 7
				_add_object_mesh(root, cone, Vector3(0.0, 0.64 + float(tier) * 0.34, 0.0), [Color("315f3e"), Color("3d7544"), Color("4a8248")][tier])
		"boulder":
			var rock := SphereMesh.new()
			rock.radius = 0.48
			rock.height = 0.78
			rock.radial_segments = 5
			rock.rings = 3
			_add_object_mesh(root, rock, Vector3(0.0, 0.30, 0.0), Color("77776d"), Vector3(1.25, 0.78, 0.92))
		"marker":
			var pin := CylinderMesh.new()
			pin.top_radius = 0.0
			pin.bottom_radius = 0.13
			pin.height = 0.34
			pin.radial_segments = 7
			_add_object_mesh(root, pin, Vector3(0.0, 0.17, 0.0), Color("d9a94f"))
			var pin_head := SphereMesh.new()
			pin_head.radius = 0.18
			pin_head.height = 0.31
			pin_head.radial_segments = 8
			pin_head.rings = 4
			_add_object_mesh(root, pin_head, Vector3(0.0, 0.40, 0.0), Color("e5c873"))
			var place_label := Label3D.new()
			place_label.name = "MarkerLabel"
			place_label.text = "Landmark"
			place_label.position = Vector3(0.0, 0.68, 0.0)
			place_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			place_label.no_depth_test = true
			place_label.font_size = 36
			place_label.pixel_size = 0.006
			place_label.modulate = Color("f6e8c3")
			place_label.outline_modulate = Color("29332b")
			place_label.outline_size = 10
			root.add_child(place_label)
		_:
			root.free()
			return null
	return root

func _add_object_mesh(parent: Node3D, mesh: Mesh, local_position: Vector3, color: Color, local_scale: Vector3 = Vector3.ONE) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = local_position
	instance.scale = local_scale
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)

func _object_footprint_radius(kind: String) -> int:
	match kind:
		"castle": return 4
		"bridge": return 2
		"wall", "fence": return 0
		_: return 0

func _object_footprint_cells(kind: String, anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor]
	var radius := _object_footprint_radius(kind)
	if radius == 0:
		return cells
	var visited: Dictionary = {grid.index_of(anchor): true}
	var frontier: Array[Vector2i] = [anchor]
	for distance in range(radius):
		var next_frontier: Array[Vector2i] = []
		for current in frontier:
			for edge in range(6):
				var neighbor := grid.neighbor_for_edge(current, edge)
				if not grid.contains(neighbor):
					continue
				var index := grid.index_of(neighbor)
				if visited.has(index):
					continue
				visited[index] = true
				cells.append(neighbor)
				next_frontier.append(neighbor)
		frontier = next_frontier
	return cells

func _erase_object_at(cell: Vector2i) -> void:
	for object_index in range(_placed_objects.size() - 1, -1, -1):
		var node := _placed_objects[object_index]
		if not is_instance_valid(node) or not node.visible:
			continue
		var footprint: Array = node.get_meta("map_footprint_cells", [node.get_meta("map_cell", INVALID_CELL)])
		if footprint.has(cell):
			node.visible = false
			_commit_undo({"_object_action": "erase", "_object_node": node})
			tool_status.text = "Erased %s" % _object_label(str(node.get_meta("map_object_type", "object")))
			_update_readout()
			return
	tool_status.text = "No object on hex %d, %d" % [cell.x, cell.y]

func _refresh_objects_on_cell(cell: Vector2i) -> void:
	for node in _placed_objects:
		if not is_instance_valid(node) or not node.visible:
			continue
		var anchor: Vector2i = node.get_meta("map_cell", INVALID_CELL)
		var footprint: Array = node.get_meta("map_footprint_cells", [anchor])
		if not footprint.has(cell):
			continue
		var total_height := 0.0
		var samples := 0
		for footprint_cell in footprint:
			if not grid.contains(footprint_cell):
				continue
			var center := grid.world_center(footprint_cell)
			total_height += board_view._surface_height_at(center.x, center.z)
			samples += 1
		if samples == 0:
			continue
		var surface_y := total_height / float(samples)
		var kind := str(node.get_meta("map_object_type", ""))
		if kind == "house":
			var object_scale := float(node.get_meta("map_object_scale", 1.0))
			surface_y -= HOUSE_MODEL_BOTTOM_Y * HOUSE_MODEL_SCALE * object_scale
		node.position.y = surface_y

func _resnap_all_objects() -> void:
	for node in _placed_objects:
		if is_instance_valid(node) and node.visible:
			_refresh_objects_on_cell(node.get_meta("map_cell", INVALID_CELL))

func _set_placeable_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.92
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_set_placeable_materials(child)

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
		_apply_cell(center, grid.elevation_at(center) + 2, grid.terrain_at(center))
		for support_cell in cells:
			if support_cell != center:
				_apply_cell(support_cell, grid.elevation_at(support_cell) + 1, grid.terrain_at(support_cell))
		for edge in range(6):
			var neighbor := grid.neighbor_for_edge(center, edge)
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
	if _undo_history.size() > 20:
		_undo_history.pop_front()
	_update_history_buttons()

func _update_history_buttons() -> void:
	if undo_button != null:
		undo_button.disabled = _undo_history.is_empty()
	if redo_button != null:
		redo_button.disabled = _redo_history.is_empty()

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
	if change_set.has("_object_action"):
		var node := change_set["_object_node"] as Node3D
		if is_instance_valid(node):
			node.visible = str(change_set["_object_action"]) == "erase"
		_redo_history.append(change_set)
		_update_history_buttons()
		_update_readout()
		return
	if change_set.has("_map_generation"):
		_apply_map_generation_snapshot(change_set, false)
		_redo_history.append(change_set)
		_update_history_buttons()
		_update_readout()
		return
	var redo_set: Dictionary = {}
	for index_variant in change_set.keys():
		var index := int(index_variant)
		var cell := grid.cell_from_index(index)
		var values: Dictionary = change_set[index]
		redo_set[index] = {"elevation": grid.elevation_at(cell), "terrain": grid.terrain_at(cell)}
		grid.set_elevation(cell, int(values["elevation"]))
		grid.set_terrain(cell, int(values["terrain"]))
		board_view.refresh_cell(cell)
		_refresh_objects_on_cell(cell)
	board_view.refresh_cliffs()
	_redo_history.append(redo_set)
	_update_history_buttons()
	_update_readout()

func _redo() -> void:
	if _redo_history.is_empty():
		return
	var change_set: Dictionary = _redo_history.pop_back()
	if change_set.has("_object_action"):
		var node := change_set["_object_node"] as Node3D
		if is_instance_valid(node):
			node.visible = str(change_set["_object_action"]) == "place"
		_undo_history.append(change_set)
		_update_history_buttons()
		_update_readout()
		return
	if change_set.has("_map_generation"):
		_apply_map_generation_snapshot(change_set, true)
		_undo_history.append(change_set)
		_update_history_buttons()
		_update_readout()
		return
	var undo_set: Dictionary = {}
	for index_variant in change_set.keys():
		var index := int(index_variant)
		var cell := grid.cell_from_index(index)
		var values: Dictionary = change_set[index]
		undo_set[index] = {"elevation": grid.elevation_at(cell), "terrain": grid.terrain_at(cell)}
		grid.set_elevation(cell, int(values["elevation"]))
		grid.set_terrain(cell, int(values["terrain"]))
		board_view.refresh_cell(cell)
		_refresh_objects_on_cell(cell)
	_undo_history.append(undo_set)
	board_view.refresh_cliffs()
	_update_history_buttons()
	_update_readout()

func _apply_map_generation_snapshot(snapshot: Dictionary, use_generated_state: bool) -> void:
	for node in _placed_objects:
		if is_instance_valid(node):
			node.visible = false
	var object_key := "after_objects" if use_generated_state else "before_objects"
	for node_variant in snapshot.get(object_key, []):
		var node := node_variant as Node3D
		if is_instance_valid(node):
			node.visible = true
	var terrain_key := "after_terrain" if use_generated_state else "before_terrain"
	var terrain_state: Dictionary = snapshot.get(terrain_key, {})
	for index_variant in terrain_state:
		var index := int(index_variant)
		var cell := grid.cell_from_index(index)
		var values: Dictionary = terrain_state[index_variant]
		grid.set_elevation(cell, int(values["elevation"]))
		grid.set_terrain(cell, int(values["terrain"]))
	board_view.refresh_all()
	_resnap_all_objects()
	board_view.set_selected(selected_cell)

func _confirm_generation(preset: String) -> void:
	_generation_preset = preset
	var preset_name := "island" if preset == "island" else ("highlands" if preset == "highlands" else "kingdom")
	var extra := " It also places the keep, bridge, cottages, roads, and forests." if preset == "kingdom" else ""
	_generation_dialog.dialog_text = "Replace the current terrain with a generated %s? Undo will restore the previous map.%s" % [preset_name, extra]
	_generation_dialog.popup_centered()

func _generate_map() -> void:
	var broad := FastNoiseLite.new()
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX
	broad.seed = randi()
	broad.frequency = 0.52
	broad.fractal_type = FastNoiseLite.FRACTAL_FBM
	broad.fractal_octaves = 4
	var ridge_noise := FastNoiseLite.new()
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_noise.seed = broad.seed + 9187
	ridge_noise.frequency = 0.7
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridge_noise.fractal_octaves = 3

	var is_kingdom := _generation_preset == "kingdom"
	var before_objects: Array[Node3D] = []
	if is_kingdom:
		for node in _placed_objects:
			if is_instance_valid(node) and node.visible:
				before_objects.append(node)
				node.visible = false

	var before_terrain: Dictionary = {}
	var after_terrain: Dictionary = {}
	for index in range(HexGrid.COLUMNS * HexGrid.ROWS):
		var cell := grid.cell_from_index(index)
		var nx := (float(cell.x) / float(HexGrid.COLUMNS - 1) - 0.5) * 2.0
		var nz := (float(cell.y) / float(HexGrid.ROWS - 1) - 0.5) * 2.0
		var broad_value := broad.get_noise_2d(float(cell.x) * 0.055, float(cell.y) * 0.055)
		var level: int
		var terrain: int
		if _generation_preset == "island":
			var distance := Vector2(nx, nz).length()
			level = roundi((1.04 - distance) * 13.0 + broad_value * 3.2 - 1.8)
			if level < 0:
				terrain = HexGrid.Terrain.WATER
			elif level <= 1:
				terrain = HexGrid.Terrain.SAND
			elif level >= 8:
				terrain = HexGrid.Terrain.STONE
			else:
				terrain = HexGrid.Terrain.GRASS
		elif _generation_preset == "kingdom":
			var city_distance := _kingdom_hex_distance(cell, Vector2i(20, 24))
			var river_distance := absf(float(cell.x) - _kingdom_river_x(float(cell.y)))
			var ridge_center := 49.0 + sin(float(cell.y) * 0.055) * 5.0 + sin(float(cell.y) * 0.11) * 1.6
			var ridge_distance := absf(float(cell.x) - ridge_center)
			var fields := cell.x >= 35 and cell.x <= 60 and cell.y >= 78 and cell.y <= 117
			level = roundi(1.0 + broad_value * 1.8)
			if ridge_distance < 4.2 and cell.y > 9 and cell.y < 104:
				level += roundi((1.0 - ridge_distance / 4.2) * 7.0 + ridge_noise.get_noise_2d(float(cell.x) * 0.2, float(cell.y) * 0.11) * 2.0)
			if city_distance <= 4:
				level = maxi(level, 6)
			elif city_distance <= 9:
				level = maxi(level, roundi(6.0 - float(city_distance - 4) * 0.85))
			if fields:
				level = clampi(roundi(0.7 + broad_value * 0.7), 0, 2)

			if river_distance <= 1.05:
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif river_distance <= 2.25:
				terrain = HexGrid.Terrain.SAND
				level = mini(level, 1)
			elif fields and ((floori(float(cell.x - 35) / 5.0) + floori(float(cell.y - 78) / 8.0)) % 2 == 0):
				terrain = HexGrid.Terrain.DIRT
			elif ridge_distance < 4.0 and level >= 5:
				terrain = HexGrid.Terrain.STONE
			elif broad_value < -0.38:
				terrain = HexGrid.Terrain.DIRT
			else:
				terrain = HexGrid.Terrain.GRASS

			var road_x := _kingdom_road_x(float(cell.y))
			if absf(float(cell.x) - road_x) <= 0.58 and river_distance > 1.05:
				terrain = HexGrid.Terrain.ROAD
				level = mini(level, 2)
		else:
			var ridge := 1.0 - absf(ridge_noise.get_noise_2d(float(cell.x + 91) * 0.045, float(cell.y - 43) * 0.045))
			level = roundi(2.0 + broad_value * 4.0 + ridge * 5.0)
			if level < 0:
				terrain = HexGrid.Terrain.WATER
			elif level <= 1:
				terrain = HexGrid.Terrain.DIRT
			elif level >= 7:
				terrain = HexGrid.Terrain.STONE
			else:
				terrain = HexGrid.Terrain.GRASS

		var old_elevation := grid.elevation_at(cell)
		var old_terrain := grid.terrain_at(cell)
		var bounded_level := clampi(level, HexGrid.MIN_ELEVATION, HexGrid.MAX_ELEVATION)
		if old_elevation == bounded_level and old_terrain == terrain:
			continue
		before_terrain[index] = {"elevation": old_elevation, "terrain": old_terrain}
		grid.set_elevation(cell, bounded_level)
		grid.set_terrain(cell, terrain)
		if is_kingdom:
			after_terrain[index] = {"elevation": bounded_level, "terrain": terrain}

	board_view.refresh_all()
	var generated_objects: Array[Node3D] = []
	if is_kingdom:
		generated_objects = _populate_kingdom_objects(broad.seed)
	_resnap_all_objects()
	_last_stroke_cell = INVALID_CELL
	if is_kingdom:
		_commit_undo({
			"_map_generation": true,
			"before_terrain": before_terrain,
			"after_terrain": after_terrain,
			"before_objects": before_objects,
			"after_objects": generated_objects
		})
	elif not before_terrain.is_empty():
		_commit_undo(before_terrain)
	var preset_name := "island" if _generation_preset == "island" else ("highlands" if _generation_preset == "highlands" else "kingdom")
	tool_status.text = "Generated %s • Undo to restore" % preset_name
	_update_readout()

func _kingdom_river_x(row: float) -> float:
	var progress := row / float(HexGrid.ROWS - 1)
	return 51.0 - 37.0 * progress + sin(progress * TAU * 1.65) * 6.0 + sin(progress * TAU * 3.2) * 1.5

func _kingdom_road_x(row: float) -> float:
	var progress := row / float(HexGrid.ROWS - 1)
	return 20.0 + 18.0 * progress + sin(progress * TAU * 1.25) * 4.0

func _kingdom_hex_distance(a: Vector2i, b: Vector2i) -> int:
	var axial_a := grid.axial_coordinates(a)
	var axial_b := grid.axial_coordinates(b)
	var dq := axial_a.x - axial_b.x
	var dr := axial_a.y - axial_b.y
	return maxi(absi(dq), maxi(absi(dr), absi(dq + dr)))

func _populate_kingdom_objects(seed_value: int) -> Array[Node3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spawned: Array[Node3D] = []
	var occupied: Dictionary = {}
	_spawn_kingdom_object("castle", Vector2i(20, 24), rng, occupied, spawned)
	# A ring of modular wall segments establishes the town's fortified center.
	var castle_center := Vector2i(20, 24)
	for row in range(maxi(0, castle_center.y - 6), mini(HexGrid.ROWS, castle_center.y + 7)):
		for column in range(maxi(0, castle_center.x - 6), mini(HexGrid.COLUMNS, castle_center.x + 7)):
			var candidate := Vector2i(column, row)
			if _kingdom_hex_distance(candidate, castle_center) == 6:
				var outward := grid.world_center(candidate) - grid.world_center(castle_center)
				var tangent_rotation := rad_to_deg(atan2(outward.z, outward.x)) + 90.0
				_spawn_kingdom_object("wall", candidate, rng, occupied, spawned, tangent_rotation)
	# Short fenced field plots make the agricultural district read at map scale.
	for field_origin in [Vector2i(36, 80), Vector2i(45, 80), Vector2i(54, 80), Vector2i(36, 94), Vector2i(54, 94), Vector2i(36, 108), Vector2i(45, 108), Vector2i(54, 108)]:
		for offset in range(5):
			var top_cell := field_origin + Vector2i(offset, 0)
			var bottom_cell := field_origin + Vector2i(offset, 6)
			var left_cell := field_origin + Vector2i(0, offset)
			var right_cell := field_origin + Vector2i(4, offset)
			for fence_cell in [top_cell, bottom_cell, left_cell, right_cell]:
				var outward_angle := atan2(float(fence_cell.y - field_origin.y - 3), float(fence_cell.x - field_origin.x - 2))
				var fence_rotation := rad_to_deg(outward_angle) + 90.0
				_spawn_kingdom_object("fence", fence_cell, rng, occupied, spawned, fence_rotation)
	var bridge_row := 63
	var bridge_column := clampi(roundi(_kingdom_river_x(float(bridge_row))), 0, HexGrid.COLUMNS - 1)
	_spawn_kingdom_object("bridge", Vector2i(bridge_column, bridge_row), rng, occupied, spawned)
	_scatter_kingdom_houses(Vector2i(20, 24), 5, 15, 60, rng, occupied, spawned)
	_scatter_kingdom_houses(Vector2i(44, 96), 2, 6, 24, rng, occupied, spawned)
	_scatter_kingdom_houses(Vector2i(11, 75), 2, 5, 14, rng, occupied, spawned)
	_scatter_kingdom_forest(Vector2i(51, 20), 10, 72, rng, occupied, spawned)
	_scatter_kingdom_forest(Vector2i(54, 61), 12, 96, rng, occupied, spawned)
	_scatter_kingdom_forest(Vector2i(14, 109), 10, 72, rng, occupied, spawned)
	for row in range(14, 102, 5):
		var ridge_column := clampi(roundi(49.0 + sin(float(row) * 0.055) * 5.0), 0, HexGrid.COLUMNS - 1)
		var boulder_cell := Vector2i(ridge_column, row)
		if grid.terrain_at(boulder_cell) == HexGrid.Terrain.STONE:
			_spawn_kingdom_object("boulder", boulder_cell, rng, occupied, spawned)
	return spawned

func _spawn_kingdom_object(kind: String, cell: Vector2i, rng: RandomNumberGenerator, occupied: Dictionary, spawned: Array[Node3D], fixed_rotation: float = -1.0) -> void:
	if not grid.contains(cell):
		return
	var index := grid.index_of(cell)
	var footprint := _object_footprint_cells(kind, cell)
	for footprint_cell in footprint:
		if occupied.has(grid.index_of(footprint_cell)):
			return
	var rotation := fixed_rotation if fixed_rotation >= 0.0 else (rng.randf_range(0.0, 360.0) if kind in ["cottage", "house", "oak", "pine", "boulder"] else 0.0)
	var scale_factor := rng.randf_range(0.78, 1.12) if kind not in ["castle", "bridge"] else 1.0
	var node := _place_active_object(cell, false, kind, rotation, scale_factor)
	if node == null:
		return
	for footprint_cell in footprint:
		occupied[grid.index_of(footprint_cell)] = true
	spawned.append(node)

func _scatter_kingdom_houses(center: Vector2i, inner_radius: int, outer_radius: int, desired_count: int, rng: RandomNumberGenerator, occupied: Dictionary, spawned: Array[Node3D]) -> void:
	var placed := 0
	for attempt in range(desired_count * 24):
		if placed >= desired_count:
			break
		var cell := Vector2i(rng.randi_range(maxi(0, center.x - outer_radius), mini(HexGrid.COLUMNS - 1, center.x + outer_radius)), rng.randi_range(maxi(0, center.y - outer_radius), mini(HexGrid.ROWS - 1, center.y + outer_radius)))
		var distance := _kingdom_hex_distance(cell, center)
		var index := grid.index_of(cell)
		var terrain := grid.terrain_at(cell)
		if distance < inner_radius or distance > outer_radius or occupied.has(index):
			continue
		if terrain == HexGrid.Terrain.WATER or terrain == HexGrid.Terrain.ROAD or terrain == HexGrid.Terrain.STONE:
			continue
		if absf(float(cell.x) - _kingdom_river_x(float(cell.y))) < 3.2:
			continue
		var kind := "cottage" if rng.randf() < 0.86 else "house"
		_spawn_kingdom_object(kind, cell, rng, occupied, spawned)
		if occupied.has(index):
			placed += 1

func _scatter_kingdom_forest(center: Vector2i, radius: int, desired_count: int, rng: RandomNumberGenerator, occupied: Dictionary, spawned: Array[Node3D]) -> void:
	var placed := 0
	for attempt in range(desired_count * 24):
		if placed >= desired_count:
			break
		var cell := Vector2i(rng.randi_range(maxi(0, center.x - radius), mini(HexGrid.COLUMNS - 1, center.x + radius)), rng.randi_range(maxi(0, center.y - radius), mini(HexGrid.ROWS - 1, center.y + radius)))
		var distance := _kingdom_hex_distance(cell, center)
		var index := grid.index_of(cell)
		var terrain := grid.terrain_at(cell)
		if distance > radius or distance < 3 or occupied.has(index):
			continue
		if terrain == HexGrid.Terrain.WATER or terrain == HexGrid.Terrain.ROAD or terrain == HexGrid.Terrain.STONE:
			continue
		if absf(float(cell.x) - _kingdom_river_x(float(cell.y))) < 3.8:
			continue
		if absf(float(cell.x) - _kingdom_road_x(float(cell.y)) ) < 1.8:
			continue
		if _kingdom_hex_distance(cell, Vector2i(20, 24)) < 13:
			continue
		var kind := "pine" if rng.randf() < 0.63 else "oak"
		_spawn_kingdom_object(kind, cell, rng, occupied, spawned)
		if occupied.has(index):
			placed += 1

func _new_blank_map() -> void:
	grid.elevations.fill(0)
	grid.terrain_ids.fill(HexGrid.Terrain.GRASS)
	for node in _placed_objects:
		if is_instance_valid(node):
			node.queue_free()
	_placed_objects.clear()
	_stroke_before.clear()
	_stroke_visited.clear()
	_undo_history.clear()
	_redo_history.clear()
	board_view.refresh_all()
	_update_history_buttons()
	_update_tool_status()
	_update_readout()

func _save_map_file(path: String) -> void:
	var object_records: Array[Dictionary] = []
	for node in _placed_objects:
		if not is_instance_valid(node) or not node.visible or not node.has_meta("map_object_type"):
			continue
		var cell: Vector2i = node.get_meta("map_cell", INVALID_CELL)
		if not grid.contains(cell):
			continue
		object_records.append({
			"type": str(node.get_meta("map_object_type", "house")),
			"x": cell.x,
			"y": cell.y,
			"rotation": float(node.get_meta("map_object_rotation", 0.0)),
			"scale": float(node.get_meta("map_object_scale", 1.0)),
			"label": str(node.get_meta("map_object_label", ""))
		})
	var payload := {
		"format_version": 1,
		"columns": HexGrid.COLUMNS,
		"rows": HexGrid.ROWS,
		"elevations": Array(grid.elevations),
		"terrain_ids": Array(grid.terrain_ids),
		"objects": object_records
	}
	var final_path := path if path.get_extension().to_lower() == "hexmap" else path + ".hexmap"
	var file := FileAccess.open(final_path, FileAccess.WRITE)
	if file == null:
		tool_status.text = "Save failed: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	tool_status.text = "Saved %s" % final_path.get_file()
	_update_readout()

func _load_map_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		tool_status.text = "Load failed: %s" % error_string(FileAccess.get_open_error())
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		tool_status.text = "That file is not a Hex Foundry map"
		return
	var map_data: Dictionary = parsed
	var elevations_value: Variant = map_data.get("elevations", [])
	var terrain_value: Variant = map_data.get("terrain_ids", [])
	if int(map_data.get("format_version", 0)) != 1 or int(map_data.get("columns", 0)) != HexGrid.COLUMNS or int(map_data.get("rows", 0)) != HexGrid.ROWS or typeof(elevations_value) != TYPE_ARRAY or typeof(terrain_value) != TYPE_ARRAY:
		tool_status.text = "Map size or data is not supported"
		return
	var count := HexGrid.COLUMNS * HexGrid.ROWS
	if elevations_value.size() != count or terrain_value.size() != count:
		tool_status.text = "Map file is incomplete"
		return

	grid.elevations = PackedInt32Array()
	grid.elevations.resize(count)
	grid.terrain_ids = PackedByteArray()
	grid.terrain_ids.resize(count)
	for index in range(count):
		grid.elevations[index] = clampi(int(elevations_value[index]), HexGrid.MIN_ELEVATION, HexGrid.MAX_ELEVATION)
		grid.terrain_ids[index] = clampi(int(terrain_value[index]), HexGrid.Terrain.GRASS, HexGrid.Terrain.ROAD)
	for node in _placed_objects:
		if is_instance_valid(node):
			node.queue_free()
	_placed_objects.clear()
	var objects_value: Variant = map_data.get("objects", [])
	if typeof(objects_value) == TYPE_ARRAY:
		for record_variant in objects_value:
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			var cell := Vector2i(int(record.get("x", -1)), int(record.get("y", -1)))
			var kind := str(record.get("type", ""))
			if not grid.contains(cell) or not ["house", "cottage", "castle", "bridge", "wall", "fence", "oak", "pine", "boulder", "marker"].has(kind):
				continue
			_place_active_object(
				cell,
				false,
				kind,
				float(record.get("rotation", 0.0)),
				clampf(float(record.get("scale", 1.0)), 0.55, 2.4),
				str(record.get("label", "Landmark"))
			)
	_stroke_before.clear()
	_stroke_visited.clear()
	_undo_history.clear()
	_redo_history.clear()
	board_view.refresh_all()
	_update_history_buttons()
	_update_tool_status()
	tool_status.text = "Loaded %s" % path.get_file()
	_update_readout()

func _zoom_camera(factor: float) -> void:
	camera_distance = clampf(camera_distance * factor, 7.0, 360.0)
	_sync_camera_controls()
	_apply_camera_pose()

func _apply_camera_pose() -> void:
	if camera == null or camera_pivot == null:
		return
	var tilt := deg_to_rad(camera_tilt_degrees)
	var yaw := deg_to_rad(camera_yaw_degrees)
	var horizontal_distance := camera_distance * cos(tilt)
	camera.position = Vector3(
		sin(yaw) * horizontal_distance,
		sin(tilt) * camera_distance,
		cos(yaw) * horizontal_distance
	)
	camera.look_at(camera_pivot.global_position, Vector3.UP)

func _on_zoom_slider_changed(value: float) -> void:
	if _syncing_camera_controls:
		return
	camera_distance = value
	_apply_camera_pose()

func _on_tilt_slider_changed(value: float) -> void:
	if _syncing_camera_controls:
		return
	camera_tilt_degrees = value
	_apply_camera_pose()

func _on_orbit_slider_changed(value: float) -> void:
	if _syncing_camera_controls:
		return
	camera_yaw_degrees = value
	_apply_camera_pose()

func _sync_camera_controls() -> void:
	if zoom_slider == null:
		return
	_syncing_camera_controls = true
	zoom_slider.value = camera_distance
	tilt_slider.value = camera_tilt_degrees
	orbit_slider.value = camera_yaw_degrees
	_syncing_camera_controls = false

func _reset_camera() -> void:
	camera_pivot.position = Vector3.ZERO
	camera_distance = 235.0
	camera_tilt_degrees = 52.0
	camera_yaw_degrees = 42.0
	_sync_camera_controls()
	_apply_camera_pose()

func _pan_camera(screen_delta: Vector2) -> void:
	var viewport_height := maxf(1.0, get_viewport().get_visible_rect().size.y)
	var distance := camera_distance
	var world_per_pixel := 2.0 * distance * tan(deg_to_rad(camera.fov * 0.5)) / viewport_height
	var right := camera.global_transform.basis.x
	var forward := camera.global_transform.basis.z
	var horizontal_right := Vector3(right.x, 0.0, right.z).normalized()
	var horizontal_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	camera_pivot.position += (-horizontal_right * screen_delta.x + horizontal_forward * screen_delta.y) * world_per_pixel
