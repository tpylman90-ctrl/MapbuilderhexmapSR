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
	var catalog_tabs := TabContainer.new()
	catalog_tabs.name = "ObjectCatalog"
	catalog_tabs.custom_minimum_size = Vector2(236.0, 286.0)
	catalog_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objects_page.add_child(catalog_tabs)
	_object_buttons.clear()
	_add_catalog_group(catalog_tabs, "Buildings", [
		["Cottage · timber", "cottage"], ["Cottage · stone", "stone_house"],
		["Farmhouse", "farmhouse"], ["Manor", "manor"], ["Tavern", "tavern"],
		["Chapel", "chapel"], ["Watchtower", "watchtower"], ["Windmill", "windmill"],
		["Village house", "house"]
	])
	_add_catalog_group(catalog_tabs, "Walls", [
		["Blackthorn Keep", "blackthorn_keep"], ["Icehelm Hold", "icehelm_hold"],
		["Ironhold Forge", "ironhold_forge"], ["Stormcrown Keep", "stormcrown_keep"],
		["Ashenreach Citadel", "ashen_keep"], ["Basalt Wall", "basalt_wall"],
		["Grand keep", "castle"], ["Hill fort", "fortress"], ["Ruined fort", "castle_ruin"],
		["Stone wall", "wall"], ["Low field wall", "stone_wall_low"],
		["Timber palisade", "palisade"], ["Wood fence", "fence"],
		["Wood bridge", "bridge"], ["Stone bridge", "stone_bridge"], ["Gatehouse", "gatehouse"]
	])
	_add_catalog_group(catalog_tabs, "Nature", [
		["Broadleaf oak", "oak"], ["Tall pine", "pine"], ["Birch", "birch"],
		["Fruit tree", "fruit_tree"], ["Bog Willow", "marsh_tree"], ["Charred Ash Tree", "ash_tree"], ["Obsidian Spire", "basalt_spire"],
		["Boulder", "boulder"], ["Rock outcrop", "outcrop"],
		["Hay stack", "haystack"]
	])
	_add_catalog_group(catalog_tabs, "Details", [
		["Village well", "well"], ["Camp", "camp"], ["Silverkeep Lighthouse", "silverkeep_lighthouse"],
		["Harbor Dock", "harbor_dock"], ["Dragon Roost", "dragon_roost"], ["Lava Vent", "lava_vent"], ["Map label", "marker"], ["Erase object", "erase"]
	])
	_add_section_title(objects_page, "MOVEMENT SCALE")
	var scale_note := Label.new()
	scale_note.text = "1 movement cell ≈ 20 ft • keep spans about 11 cells • bridge about 5"
	scale_note.add_theme_color_override("font_color", Color("c7c7b8"))
	scale_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objects_page.add_child(scale_note)
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
	_make_button(map_page, "Generate Ashenreach", func(): _confirm_generation("ashenreach"))
	_add_section_title(map_page, "TERRITORY PRESETS")
	var territory_picker := OptionButton.new()
	territory_picker.name = "TerritoryPresetPicker"
	var territory_presets := [
		["Ravenwood • Blackthorn", "ravenwood"], ["Blighted Marsh", "blighted_marsh"],
		["Cursed Mire • Deadwind Hollow", "cursed_mire"], ["Shadowfen Forest", "shadowfen"],
		["Frostpeaks • Icehelm", "frostpeaks"], ["Drakeshard Range • Ironhold", "drakeshard"],
		["Iron Plains • Harrowstead", "iron_plains"], ["Veiled Sea • Silverkeep", "veiled_sea"],
		["Ember Coast • Dragon’s Rest", "ember_coast"], ["Stormcrown Keep", "stormcrown"]
	]
	for territory_entry in territory_presets:
		territory_picker.add_item(str(territory_entry[0]))
		territory_picker.set_item_metadata(territory_picker.item_count - 1, str(territory_entry[1]))
	territory_picker.select(0)
	map_page.add_child(territory_picker)
	_make_button(map_page, "Generate Territory", func():
		_confirm_generation(str(territory_picker.get_item_metadata(territory_picker.selected)))
	)
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

func _add_catalog_group(parent: TabContainer, group_name: String, entries: Array) -> void:
	var page := VBoxContainer.new()
	page.name = group_name
	page.add_theme_constant_override("separation", 6)
	parent.add_child(page)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	for entry in entries:
		_add_object_button(grid, str(entry[0]), str(entry[1]))

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
		"house": return "Village House"
		"cottage": return "Timber Cottage"
		"stone_house": return "Stone Cottage"
		"farmhouse": return "Farmhouse"
		"manor": return "Manor House"
		"tavern": return "Village Tavern"
		"chapel": return "Chapel"
		"watchtower": return "Watchtower"
		"windmill": return "Windmill"
		"blackthorn_keep": return "Blackthorn Keep"
		"icehelm_hold": return "Icehelm Hold"
		"ironhold_forge": return "Ironhold Forge"
		"stormcrown_keep": return "Stormcrown Keep"
		"marsh_tree": return "Bog Willow"
		"silverkeep_lighthouse": return "Silverkeep Lighthouse"
		"harbor_dock": return "Harbor Dock"
		"dragon_roost": return "Dragon Roost"
		"ashen_keep": return "Ashenreach Citadel"
		"basalt_wall": return "Basalt Wall"
		"ash_tree": return "Charred Ash Tree"
		"basalt_spire": return "Obsidian Spire"
		"lava_vent": return "Lava Vent"
		"castle": return "Grand Stone Keep"
		"fortress": return "Hill Fort"
		"castle_ruin": return "Ruined Fort"
		"gatehouse": return "Gatehouse"
		"bridge": return "Wood Bridge"
		"stone_bridge": return "Stone Bridge"
		"wall": return "Crenellated Wall"
		"stone_wall_low": return "Low Stone Wall"
		"palisade": return "Timber Palisade"
		"fence": return "Wood Fence"
		"oak": return "Broadleaf Oak"
		"pine": return "Tall Pine"
		"birch": return "Birch Tree"
		"fruit_tree": return "Fruit Tree"
		"boulder": return "Boulder"
		"outcrop": return "Rock Outcrop"
		"haystack": return "Hay Stack"
		"well": return "Village Well"
		"camp": return "Camp"
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
		# The irregular curtain wall spans about eleven movement cells.
		node.scale = Vector3(2.0, 1.35, 2.0) * scale_factor
	elif kind == "fortress":
		node.scale = Vector3(1.35, 1.12, 1.35) * scale_factor
	elif kind == "castle_ruin":
		node.scale = Vector3(1.30, 0.92, 1.30) * scale_factor
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
			_add_building_shell(root, Vector3(1.36, 0.92, 1.18), 0.52, Color("b79b70"), Color("594038"), Color("493528"))
			_add_building_chimney(root, Vector3(0.42, 1.85, -0.24))
		"stone_house":
			_add_building_shell(root, Vector3(1.48, 1.02, 1.32), 0.56, Color("aaa08d"), Color("58483c"), Color("42372c"))
			_add_building_chimney(root, Vector3(0.44, 1.92, -0.34))
		"farmhouse":
			_add_building_shell(root, Vector3(1.82, 1.18, 1.56), 0.66, Color("b29b73"), Color("60503a"), Color("49372a"))
			var shed := BoxMesh.new()
			shed.size = Vector3(0.92, 0.70, 1.06)
			_add_object_mesh(root, shed, Vector3(-1.02, 0.37, -0.10), Color("9b815c"))
			var shed_roof := PrismMesh.new()
			shed_roof.size = Vector3(1.08, 0.54, 1.18)
			_add_object_mesh(root, shed_roof, Vector3(-1.02, 0.99, -0.10), Color("635039"))
			_add_building_chimney(root, Vector3(0.58, 2.18, -0.40))
		"manor":
			_add_building_shell(root, Vector3(2.10, 1.48, 1.78), 0.76, Color("c0b296"), Color("51463e"), Color("493d32"))
			var upper_story := BoxMesh.new()
			upper_story.size = Vector3(1.42, 0.80, 1.36)
			_add_object_mesh(root, upper_story, Vector3(0.36, 1.88, -0.02), Color("aa9679"))
			var upper_roof := PrismMesh.new()
			upper_roof.size = Vector3(1.62, 0.82, 1.58)
			_add_object_mesh(root, upper_roof, Vector3(0.36, 2.70, -0.02), Color("4a3b34"))
			var porch := BoxMesh.new()
			porch.size = Vector3(1.75, 0.13, 0.58)
			_add_object_mesh(root, porch, Vector3(-0.20, 1.17, 1.10), Color("755a3c"))
			var porch_post := CylinderMesh.new()
			porch_post.top_radius = 0.055
			porch_post.bottom_radius = 0.075
			porch_post.height = 1.15
			porch_post.radial_segments = 6
			_add_object_mesh(root, porch_post, Vector3(-0.88, 0.57, 1.28), Color("564536"))
			_add_object_mesh(root, porch_post, Vector3(0.46, 0.57, 1.28), Color("564536"))
		"tavern":
			_add_building_shell(root, Vector3(1.70, 1.22, 1.46), 0.64, Color("aa8561"), Color("4d382e"), Color("3f2d25"))
			var sign_beam := BoxMesh.new()
			sign_beam.size = Vector3(0.55, 0.10, 0.10)
			_add_object_mesh(root, sign_beam, Vector3(0.76, 1.30, 0.93), Color("46382b"))
			var signboard := BoxMesh.new()
			signboard.size = Vector3(0.42, 0.38, 0.09)
			_add_object_mesh(root, signboard, Vector3(0.96, 1.08, 0.94), Color("c9a957"))
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.19
			barrel.bottom_radius = 0.16
			barrel.height = 0.42
			barrel.radial_segments = 12
			_add_object_mesh(root, barrel, Vector3(-1.05, 0.22, 0.76), Color("795638"), Vector3.ONE, 1)
			for hoop_y in [0.09, 0.34]:
				var hoop := TorusMesh.new()
				hoop.inner_radius = 0.172
				hoop.outer_radius = 0.192
				var hoop_node := _add_object_mesh(root, hoop, Vector3(-1.05, hoop_y, 0.76), Color("686b68"), Vector3.ONE, 4)
			var barrel_lid := CylinderMesh.new()
			barrel_lid.top_radius = 0.15
			barrel_lid.bottom_radius = 0.15
			barrel_lid.height = 0.025
			barrel_lid.radial_segments = 12
			_add_object_mesh(root, barrel_lid, Vector3(-1.05, 0.435, 0.76), Color("9b774e"), Vector3.ONE, 1)
		"chapel":
			_add_building_shell(root, Vector3(1.66, 1.46, 2.50), 0.48, Color("b3ab99"), Color("51453e"), Color("40352f"))
			var tower := BoxMesh.new()
			tower.size = Vector3(0.64, 1.58, 0.72)
			_add_object_mesh(root, tower, Vector3(0.0, 2.05, -0.82), Color("a69e8d"))
			var spire := CylinderMesh.new()
			spire.top_radius = 0.0
			spire.bottom_radius = 0.50
			spire.height = 0.98
			spire.radial_segments = 4
			_add_object_mesh(root, spire, Vector3(0.0, 3.30, -0.82), Color("463b34"))
			var cross_post := BoxMesh.new()
			cross_post.size = Vector3(0.08, 0.55, 0.08)
			_add_object_mesh(root, cross_post, Vector3(0.0, 4.05, -0.82), Color("c5b98e"))
			var cross_arm := BoxMesh.new()
			cross_arm.size = Vector3(0.34, 0.08, 0.08)
			_add_object_mesh(root, cross_arm, Vector3(0.0, 4.10, -0.82), Color("c5b98e"))
		"watchtower":
			var tower_base := CylinderMesh.new()
			tower_base.top_radius = 0.54
			tower_base.bottom_radius = 0.68
			tower_base.height = 2.35
			tower_base.radial_segments = 8
			_add_object_mesh(root, tower_base, Vector3(0.0, 1.17, 0.0), Color("918b7d"))
			var platform := CylinderMesh.new()
			platform.top_radius = 0.92
			platform.bottom_radius = 0.78
			platform.height = 0.30
			platform.radial_segments = 8
			_add_object_mesh(root, platform, Vector3(0.0, 2.44, 0.0), Color("71583d"))
			var watch_roof := CylinderMesh.new()
			watch_roof.top_radius = 0.0
			watch_roof.bottom_radius = 0.96
			watch_roof.height = 0.92
			watch_roof.radial_segments = 8
			_add_object_mesh(root, watch_roof, Vector3(0.0, 3.04, 0.0), Color("493b33"))
			var slit := BoxMesh.new()
			slit.size = Vector3(0.09, 0.42, 0.05)
			_add_object_mesh(root, slit, Vector3(0.0, 1.56, 0.65), Color("282a29"))
		"windmill":
			var mill_body := CylinderMesh.new()
			mill_body.top_radius = 0.38
			mill_body.bottom_radius = 0.68
			mill_body.height = 2.18
			mill_body.radial_segments = 8
			_add_object_mesh(root, mill_body, Vector3(0.0, 1.09, 0.0), Color("b8a27d"))
			var mill_roof := CylinderMesh.new()
			mill_roof.top_radius = 0.0
			mill_roof.bottom_radius = 0.52
			mill_roof.height = 0.62
			mill_roof.radial_segments = 8
			_add_object_mesh(root, mill_roof, Vector3(0.0, 2.48, 0.0), Color("514137"))
			var hub := SphereMesh.new()
			hub.radius = 0.16
			hub.height = 0.28
			hub.radial_segments = 8
			hub.rings = 4
			_add_object_mesh(root, hub, Vector3(0.0, 1.92, 0.53), Color("705438"))
			for blade_index in range(4):
				var blade_angle := TAU * float(blade_index) / 4.0
				var blade := BoxMesh.new()
				blade.size = Vector3(0.16, 1.12, 0.07)
				var blade_node := _add_object_mesh(root, blade, Vector3(0.0, 1.92, 0.58), Color("d4c29d"), Vector3.ONE, 1)
				blade_node.rotation.z = blade_angle
				var sail_panel := BoxMesh.new()
				sail_panel.size = Vector3(0.34, 0.52, 0.035)
				var sail_node := _add_object_mesh(root, sail_panel, Vector3(-sin(blade_angle) * 0.44, 1.92 + cos(blade_angle) * 0.44, 0.62), Color("e1d3b3"), Vector3.ONE, 3)
				sail_node.rotation.z = blade_angle
			var mill_door := BoxMesh.new()
			mill_door.size = Vector3(0.32, 0.62, 0.08)
			_add_object_mesh(root, mill_door, Vector3(0.0, 0.35, 0.64), Color("604833"), Vector3.ONE, 1)
			var door_lintel := BoxMesh.new()
			door_lintel.size = Vector3(0.48, 0.09, 0.12)
			_add_object_mesh(root, door_lintel, Vector3(0.0, 0.70, 0.65), Color("817052"), Vector3.ONE, 0)
		"fortress":
			var hill_ring := _castle_ring_points(4.35, 3.55, Vector2.ZERO, 0.12)
			_add_castle_wall_ring(root, hill_ring, 1.35, 1.82, 0.48, true, Color("77776d"))
			for tower_index in range(0, 12, 2):
				_add_castle_tower(root, hill_ring[tower_index], 2.65 + float(tower_index % 3) * 0.22, 0.48, Color("858174"))
			var hall := BoxMesh.new()
			hall.size = Vector3(2.35, 1.65, 1.82)
			_add_object_mesh(root, hall, Vector3(-0.55, 1.10, -0.54), Color("a7977e"))
			var hall_roof := PrismMesh.new()
			hall_roof.size = Vector3(2.58, 1.10, 2.03)
			_add_object_mesh(root, hall_roof, Vector3(-0.55, 2.48, -0.54), Color("514138"))
		"castle_ruin":
			var ruin_ring := _castle_ring_points(4.2, 3.45, Vector2.ZERO, 0.08)
			for wall_index in range(12):
				if wall_index % 4 == 1:
					continue
				var point_a: Vector2 = ruin_ring[wall_index]
				var point_b: Vector2 = ruin_ring[(wall_index + 1) % 12]
				var midpoint := (point_a + point_b) * 0.5
				var edge := point_b - point_a
				var broken_wall := BoxMesh.new()
				broken_wall.size = Vector3(edge.length(), 1.45 + float(wall_index % 3) * 0.42, 0.42)
				var broken_node := _add_object_mesh(root, broken_wall, Vector3(midpoint.x, broken_wall.size.y * 0.5, midpoint.y), Color("827c6e"))
				broken_node.rotation.y = atan2(-edge.y, edge.x)
			for tower_index in [0, 4, 8]:
				_add_castle_tower(root, ruin_ring[tower_index], 2.15, 0.52, Color("79766b"))
			for rubble_index in range(7):
				var rubble := BoxMesh.new()
				rubble.size = Vector3(0.45 + float(rubble_index % 3) * 0.12, 0.25 + float(rubble_index % 2) * 0.12, 0.38)
				var angle := TAU * float(rubble_index) / 7.0
				var debris := _add_object_mesh(root, rubble, Vector3(cos(angle) * 2.4, 0.16, sin(angle) * 1.9), Color("999182"))
				debris.rotation.y = angle
		"blackthorn_keep":
			var motte := CylinderMesh.new()
			motte.top_radius = 5.0
			motte.bottom_radius = 6.1
			motte.height = 1.05
			motte.radial_segments = 16
			_add_object_mesh(root, motte, Vector3(0.0, 0.48, 0.0), Color("66513b"))
			var timber_ring := _castle_ring_points(4.8, 4.0, Vector2.ZERO, 0.08)
			for wall_index in range(timber_ring.size()):
				var a: Vector2 = timber_ring[wall_index]
				var b: Vector2 = timber_ring[(wall_index + 1) % timber_ring.size()]
				var midpoint := (a + b) * 0.5
				if midpoint.y > 2.2 and absf(midpoint.x) < 1.35:
					continue
				var edge := b - a
				var palisade := BoxMesh.new()
				palisade.size = Vector3(edge.length() + 0.14, 1.75, 0.34)
				var palisade_node := _add_object_mesh(root, palisade, Vector3(midpoint.x, 1.76, midpoint.y), Color("49372b"))
				palisade_node.rotation.y = atan2(-edge.y, edge.x)
			for tower_index in [1, 4, 7, 10]:
				var point: Vector2 = timber_ring[tower_index]
				var tower := CylinderMesh.new()
				tower.top_radius = 0.44
				tower.bottom_radius = 0.60
				tower.height = 3.15
				tower.radial_segments = 7
				_add_object_mesh(root, tower, Vector3(point.x, 2.35, point.y), Color("624634"))
				var tower_cap := PrismMesh.new()
				tower_cap.size = Vector3(1.35, 0.75, 1.25)
				var cap_node := _add_object_mesh(root, tower_cap, Vector3(point.x, 4.25, point.y), Color("362821"))
				cap_node.rotation.y = PI * 0.25
			_add_building_shell(root, Vector3(3.0, 1.8, 2.5), 0.82, Color("82603e"), Color("514032"), Color("45342a"))
			var gate := BoxMesh.new()
			gate.size = Vector3(1.55, 2.15, 0.18)
			_add_object_mesh(root, gate, Vector3(0.0, 1.2, 4.04), Color("302a26"))
			var gate_beam := BoxMesh.new()
			gate_beam.size = Vector3(2.25, 0.24, 0.42)
			_add_object_mesh(root, gate_beam, Vector3(0.0, 2.38, 4.02), Color("775234"))
		"icehelm_hold":
			var glacier_ring := _castle_ring_points(5.7, 4.7, Vector2.ZERO, 0.04)
			_add_castle_wall_ring(root, glacier_ring, 1.15, 2.05, 0.68, true, Color("727b80"))
			var inner_glacier_ring := _castle_ring_points(3.3, 2.9, Vector2(-0.45, -0.2), 0.12)
			_add_castle_wall_ring(root, inner_glacier_ring, 2.82, 2.65, 0.72, true, Color("899497"))
			for tower_index in [0, 3, 6, 9]:
				_add_castle_tower(root, glacier_ring[tower_index], 3.65, 0.70, Color("8c989b"))
			var ice_hall := BoxMesh.new()
			ice_hall.size = Vector3(3.0, 3.2, 2.9)
			_add_object_mesh(root, ice_hall, Vector3(-0.45, 4.25, -0.25), Color("8c999b"))
			var ice_roof := PrismMesh.new()
			ice_roof.size = Vector3(3.45, 1.35, 3.3)
			_add_object_mesh(root, ice_roof, Vector3(-0.45, 6.55, -0.25), Color("55636b"))
			var banner := BoxMesh.new()
			banner.size = Vector3(0.12, 1.2, 0.08)
			_add_object_mesh(root, banner, Vector3(0.0, 7.45, -0.3), Color("6ca9ba"))
		"ironhold_forge":
			var forge_mound := CylinderMesh.new()
			forge_mound.top_radius = 5.2
			forge_mound.bottom_radius = 6.2
			forge_mound.height = 1.4
			forge_mound.radial_segments = 12
			_add_object_mesh(root, forge_mound, Vector3(0.0, 0.58, 0.0), Color("545653"))
			var forge_ring := _castle_ring_points(4.9, 3.9, Vector2.ZERO, 0.0)
			_add_castle_wall_ring(root, forge_ring, 1.45, 2.55, 0.82, true, Color("585a57"))
			for side in [-1.0, 1.0]:
				var gate_tower := CylinderMesh.new()
				gate_tower.top_radius = 0.64
				gate_tower.bottom_radius = 0.88
				gate_tower.height = 4.9
				gate_tower.radial_segments = 8
				_add_object_mesh(root, gate_tower, Vector3(side * 1.55, 2.75, 3.65), Color("666863"))
				var roof := PrismMesh.new()
				roof.size = Vector3(1.9, 1.25, 1.7)
				_add_object_mesh(root, roof, Vector3(side * 1.55, 5.62, 3.65), Color("383a38"))
			var gate := BoxMesh.new()
			gate.size = Vector3(2.35, 2.45, 0.30)
			_add_object_mesh(root, gate, Vector3(0.0, 1.54, 3.92), Color("211f1e"))
			for chimney_x in [-2.5, 2.5]:
				var chimney := CylinderMesh.new()
				chimney.top_radius = 0.24
				chimney.bottom_radius = 0.42
				chimney.height = 3.2
				chimney.radial_segments = 7
				_add_object_mesh(root, chimney, Vector3(chimney_x, 4.0, -0.7), Color("4a4c49"))
		"stormcrown_keep":
			var crown_ring := _castle_ring_points(5.75, 4.7, Vector2.ZERO, 0.05)
			_add_castle_wall_ring(root, crown_ring, 1.5, 2.25, 0.74, true, Color("676d70"))
			var upper_ring := _castle_ring_points(3.8, 3.05, Vector2(-0.25, -0.25), 0.16)
			_add_castle_wall_ring(root, upper_ring, 3.5, 2.6, 0.8, false, Color("777d7e"))
			for tower_index in range(0, 12, 2):
				_add_castle_tower(root, crown_ring[tower_index], 4.2 + float(tower_index % 4) * 0.3, 0.72, Color("7b8180"))
			_add_castle_tower(root, upper_ring[0], 8.6, 0.90, Color("8b9090"))
			var spire_mesh := CylinderMesh.new()
			spire_mesh.top_radius = 0.0
			spire_mesh.bottom_radius = 1.18
			spire_mesh.height = 2.0
			spire_mesh.radial_segments = 5
			_add_object_mesh(root, spire_mesh, Vector3(0.0, 9.2, -0.2), Color("50575d"))
			var beacon := OmniLight3D.new()
			beacon.position = Vector3(0.0, 10.2, -0.2)
			beacon.light_color = Color("b8d9e5")
			beacon.light_energy = 1.25
			beacon.omni_range = 13.0
			root.add_child(beacon)
		"marsh_tree":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.10
			trunk.bottom_radius = 0.34
			trunk.height = 2.7
			trunk.radial_segments = 6
			var trunk_node := _add_object_mesh(root, trunk, Vector3(0.0, 1.28, 0.0), Color("494136"))
			trunk_node.rotation.z = -0.18
			for root_index in range(5):
				var root_mesh := CylinderMesh.new()
				root_mesh.top_radius = 0.035
				root_mesh.bottom_radius = 0.12
				root_mesh.height = 1.15
				root_mesh.radial_segments = 5
				var root_angle := TAU * float(root_index) / 5.0
				var root_node := _add_object_mesh(root, root_mesh, Vector3(cos(root_angle) * 0.42, 0.26, sin(root_angle) * 0.42), Color("554735"))
				root_node.rotation.z = cos(root_angle) * 0.78
				root_node.rotation.x = sin(root_angle) * 0.78
			for branch_index in range(4):
				var branch := CylinderMesh.new()
				branch.top_radius = 0.02
				branch.bottom_radius = 0.085
				branch.height = 1.45
				branch.radial_segments = 5
				var angle := TAU * float(branch_index) / 4.0
				var branch_node := _add_object_mesh(root, branch, Vector3(cos(angle) * 0.35, 2.15, sin(angle) * 0.35), Color("4f4536"))
				branch_node.rotation.z = cos(angle) * 0.85
				branch_node.rotation.x = sin(angle) * 0.65
		"silverkeep_lighthouse":
			var lighthouse_base := CylinderMesh.new()
			lighthouse_base.top_radius = 0.65
			lighthouse_base.bottom_radius = 1.2
			lighthouse_base.height = 1.0
			lighthouse_base.radial_segments = 10
			_add_object_mesh(root, lighthouse_base, Vector3(0.0, 0.5, 0.0), Color("78756c"))
			for band_index in range(4):
				var shaft := CylinderMesh.new()
				shaft.top_radius = 0.46 - float(band_index) * 0.035
				shaft.bottom_radius = 0.58 - float(band_index) * 0.035
				shaft.height = 1.28
				shaft.radial_segments = 10
				_add_object_mesh(root, shaft, Vector3(0.0, 1.55 + float(band_index) * 1.22, 0.0), Color("d0c9b5") if band_index % 2 == 0 else Color("9a5142"))
			var lantern := BoxMesh.new()
			lantern.size = Vector3(1.15, 0.8, 1.15)
			_add_object_mesh(root, lantern, Vector3(0.0, 6.55, 0.0), Color("493f35"))
			var lamp_glass := SphereMesh.new()
			lamp_glass.radius = 0.34
			lamp_glass.height = 0.64
			lamp_glass.radial_segments = 8
			lamp_glass.rings = 4
			var light_glass_node := _add_object_mesh(root, lamp_glass, Vector3(0.0, 6.55, 0.0), Color("f3ce73"))
			var lighthouse_light := OmniLight3D.new()
			lighthouse_light.position = Vector3(0.0, 6.55, 0.0)
			lighthouse_light.light_color = Color("ffd884")
			lighthouse_light.light_energy = 2.0
			lighthouse_light.omni_range = 16.0
			root.add_child(lighthouse_light)
			var cap := PrismMesh.new()
			cap.size = Vector3(1.45, 0.72, 1.45)
			_add_object_mesh(root, cap, Vector3(0.0, 7.26, 0.0), Color("3b302a"))
		"harbor_dock":
			for plank_index in range(8):
				var plank := BoxMesh.new()
				plank.size = Vector3(3.2, 0.14, 0.42)
				_add_object_mesh(root, plank, Vector3(0.0, 0.42, -1.45 + float(plank_index) * 0.42), Color("76573a") if plank_index % 2 == 0 else Color("886746"))
			for pier_x in [-1.32, 1.32]:
				for pier_z in [-1.35, 0.0, 1.35]:
					var pile := CylinderMesh.new()
					pile.top_radius = 0.10
					pile.bottom_radius = 0.16
					pile.height = 0.88
					pile.radial_segments = 6
					_add_object_mesh(root, pile, Vector3(pier_x, 0.18, pier_z), Color("4d392b"))
			for post_x in [-1.25, 1.25]:
				var post := CylinderMesh.new()
				post.top_radius = 0.08
				post.bottom_radius = 0.10
				post.height = 0.8
				post.radial_segments = 6
				_add_object_mesh(root, post, Vector3(post_x, 0.78, 1.45), Color("573f2e"))
		"dragon_roost":
			var roost_ring := _castle_ring_points(3.35, 3.0, Vector2.ZERO, 0.12)
			for wall_index in range(roost_ring.size()):
				var a: Vector2 = roost_ring[wall_index]
				var b: Vector2 = roost_ring[(wall_index + 1) % roost_ring.size()]
				var midpoint := (a + b) * 0.5
				var edge := b - a
				var rim := BoxMesh.new()
				rim.size = Vector3(edge.length() + 0.15, 1.25, 0.72)
				var rim_node := _add_object_mesh(root, rim, Vector3(midpoint.x, 0.78, midpoint.y), Color("4a4039"))
				rim_node.rotation.y = atan2(-edge.y, edge.x)
			for spire_index in range(5):
				var angle := TAU * float(spire_index) / 5.0
				var spire := CylinderMesh.new()
				spire.top_radius = 0.03
				spire.bottom_radius = 0.65
				spire.height = 2.6 + float(spire_index % 2) * 0.8
				spire.radial_segments = 5
				_add_object_mesh(root, spire, Vector3(cos(angle) * 2.55, spire.height * 0.52, sin(angle) * 2.15), Color("393938"))
		"ashen_keep":
			var foundation := CylinderMesh.new()
			foundation.top_radius = 6.4
			foundation.bottom_radius = 6.8
			foundation.height = 0.72
			foundation.radial_segments = 16
			_add_object_mesh(root, foundation, Vector3(0.0, 0.28, 0.0), Color("514c46"))
			var outer_ring := _castle_ring_points(5.85, 4.95, Vector2(0.25, -0.12), 0.05)
			var middle_ring := _castle_ring_points(4.12, 3.42, Vector2(-0.38, -0.42), 0.13)
			var inner_ring := _castle_ring_points(2.55, 2.35, Vector2(-0.65, -0.55), 0.0)
			_add_castle_wall_ring(root, outer_ring, 1.02, 2.0, 0.66, true, Color("343333"))
			_add_castle_wall_ring(root, middle_ring, 2.35, 2.35, 0.72, true, Color("42413e"))
			_add_castle_wall_ring(root, inner_ring, 4.05, 2.80, 0.78, false, Color("504d49"))
			for tower_index in range(12):
				if tower_index % 2 == 0:
					_add_castle_tower(root, outer_ring[tower_index], 3.45 + float(tower_index % 4) * 0.24, 0.68, Color("44423f"))
				if tower_index % 3 == 0:
					_add_castle_tower(root, middle_ring[tower_index], 4.10, 0.58, Color("514e49"))
			_add_castle_tower(root, inner_ring[0], 7.45, 0.88, Color("59554e"))
			var keep := BoxMesh.new()
			keep.size = Vector3(3.4, 4.6, 3.15)
			_add_object_mesh(root, keep, Vector3(-0.68, 5.1, -0.56), Color("57534b"))
			var cap := BoxMesh.new()
			cap.size = Vector3(3.65, 0.34, 3.4)
			_add_object_mesh(root, cap, Vector3(-0.68, 7.42, -0.56), Color("3a302a"))
			for window_x in [-1.75, -0.68, 0.39]:
				_add_keep_window(root, Vector3(window_x, 5.85, 1.04), 0.20, 1.05)
			var gatehouse := BoxMesh.new()
			gatehouse.size = Vector3(2.4, 3.15, 1.15)
			_add_object_mesh(root, gatehouse, Vector3(0.0, 2.18, 4.45), Color("4b4945"))
			var gate_roof := PrismMesh.new()
			gate_roof.size = Vector3(2.9, 0.85, 1.55)
			_add_object_mesh(root, gate_roof, Vector3(0.0, 4.18, 4.45), Color("302b28"))
			_add_keep_window(root, Vector3(0.0, 2.65, 5.06), 0.46, 1.22)
			for stair_index in range(5):
				var stair := BoxMesh.new()
				stair.size = Vector3(2.2, 0.26, 0.54)
				_add_object_mesh(root, stair, Vector3(0.0, 0.48 + float(stair_index) * 0.24, 5.10 + float(stair_index) * 0.42), Color("64605a"))
		"basalt_wall":
			for block_index in range(5):
				var block := BoxMesh.new()
				block.size = Vector3(0.72, 0.92 + float(block_index % 2) * 0.10, 0.52)
				_add_object_mesh(root, block, Vector3(-1.45 + float(block_index) * 0.72, 0.46, 0.0), Color("393a39"))
			var coping := BoxMesh.new()
			coping.size = Vector3(3.9, 0.18, 0.64)
			_add_object_mesh(root, coping, Vector3(0.0, 1.0, 0.0), Color("55524c"))
		"ash_tree":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.10
			trunk.bottom_radius = 0.28
			trunk.height = 2.15
			trunk.radial_segments = 6
			var trunk_node := _add_object_mesh(root, trunk, Vector3(0.0, 1.05, 0.0), Color("302e2a"))
			trunk_node.rotation.z = 0.12
			for branch_index in range(5):
				var branch := CylinderMesh.new()
				branch.top_radius = 0.035
				branch.bottom_radius = 0.095
				branch.height = 1.05 + float(branch_index % 2) * 0.3
				branch.radial_segments = 5
				var angle := TAU * float(branch_index) / 5.0
				var branch_node := _add_object_mesh(root, branch, Vector3(cos(angle) * 0.28, 1.64 + float(branch_index % 2) * 0.24, sin(angle) * 0.28), Color("403b34"))
				branch_node.rotation.z = cos(angle) * 0.65
				branch_node.rotation.x = sin(angle) * 0.65
		"basalt_spire":
			for layer_index in range(3):
				var spire := CylinderMesh.new()
				spire.top_radius = 0.08 + float(2 - layer_index) * 0.05
				spire.bottom_radius = 0.76 - float(layer_index) * 0.16
				spire.height = 1.7 + float(layer_index) * 0.18
				spire.radial_segments = 5
				var spire_node := _add_object_mesh(root, spire, Vector3(0.0, 0.82 + float(layer_index) * 1.45, 0.0), Color("292b2c"))
				spire_node.rotation.y = float(layer_index) * 0.31
			var vein := BoxMesh.new()
			vein.size = Vector3(0.075, 1.72, 0.06)
			var vein_node := _add_object_mesh(root, vein, Vector3(0.16, 1.48, 0.48), Color("a12f13"))
			vein_node.rotation.z = -0.18
		"lava_vent":
			var vent := CylinderMesh.new()
			vent.top_radius = 0.56
			vent.bottom_radius = 0.88
			vent.height = 0.82
			vent.radial_segments = 7
			_add_object_mesh(root, vent, Vector3(0.0, 0.39, 0.0), Color("302b27"))
			var vent_core := CylinderMesh.new()
			vent_core.top_radius = 0.40
			vent_core.bottom_radius = 0.48
			vent_core.height = 0.15
			vent_core.radial_segments = 8
			_add_object_mesh(root, vent_core, Vector3(0.0, 0.83, 0.0), Color("d34a12"))
			var flame := CylinderMesh.new()
			flame.top_radius = 0.02
			flame.bottom_radius = 0.23
			flame.height = 0.55
			flame.radial_segments = 5
			_add_object_mesh(root, flame, Vector3(0.0, 1.12, 0.0), Color("ef7718"))
		"castle":
			var outer_ring := _castle_ring_points(5.45, 4.55, Vector2(0.30, 0.20), 0.03)
			var inner_ring := _castle_ring_points(3.35, 2.85, Vector2(-1.02, -0.64), 0.13)
			_add_castle_wall_ring(root, outer_ring, 1.02, 1.82, 0.52, true, Color("77756b"))
			_add_castle_wall_ring(root, inner_ring, 2.48, 2.20, 0.56, true, Color("858174"))
			for tower_index in range(12):
				if tower_index % 3 == 0:
					_add_castle_tower(root, outer_ring[tower_index], 3.20 + float(tower_index % 2) * 0.45, 0.70, Color("858174"))
				elif tower_index % 3 == 1:
					_add_castle_tower(root, inner_ring[tower_index], 2.72, 0.58, Color("908a7c"))
			# A defended, roofed gate ties the outer bailey to the offset inner ward.
			var gate_left := BoxMesh.new()
			gate_left.size = Vector3(1.38, 2.35, 1.55)
			_add_object_mesh(root, gate_left, Vector3(-1.38, 1.58, 4.14), Color("8b8679"))
			_add_object_mesh(root, gate_left, Vector3(1.38, 1.58, 4.14), Color("8b8679"))
			var gate_arch := BoxMesh.new()
			gate_arch.size = Vector3(4.2, 0.78, 1.7)
			_add_object_mesh(root, gate_arch, Vector3(0.0, 3.05, 4.14), Color("969082"))
			var gate_roof := PrismMesh.new()
			gate_roof.size = Vector3(4.75, 1.08, 2.0)
			_add_object_mesh(root, gate_roof, Vector3(0.0, 3.82, 4.14), Color("59463d"))
			var portcullis := BoxMesh.new()
			portcullis.size = Vector3(1.72, 1.95, 0.12)
			_add_object_mesh(root, portcullis, Vector3(0.0, 1.05, 4.96), Color("393732"))
			for bar_index in range(8):
				var iron_bar := BoxMesh.new()
				iron_bar.size = Vector3(0.065, 1.88, 0.07)
				_add_object_mesh(root, iron_bar, Vector3(-0.70 + float(bar_index) * 0.20, 1.05, 4.89), Color("302f2b"))
			var gate_door := BoxMesh.new()
			gate_door.size = Vector3(1.56, 0.14, 0.12)
			for brace_index in range(4):
				_add_object_mesh(root, gate_door, Vector3(0.0, 0.42 + float(brace_index) * 0.38, 4.90), Color("604a37"))
			# The lower keep is rectangular and buttressed; the narrower upper hall
			# and a separate belfry create a stepped skyline instead of one square block.
			var keep_lower := BoxMesh.new()
			keep_lower.size = Vector3(3.95, 3.15, 3.30)
			_add_object_mesh(root, keep_lower, Vector3(-0.60, 3.45, -0.66), Color("8e897b"))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var buttress := BoxMesh.new()
					buttress.size = Vector3(0.48, 3.30, 0.50)
					_add_object_mesh(root, buttress, Vector3(-0.60 + sx * 1.78, 3.38, -0.66 + sz * 1.47), Color("a19b8d"))
			_add_keep_window(root, Vector3(-1.70, 3.55, 1.04))
			_add_keep_window(root, Vector3(-0.72, 3.55, 1.04))
			_add_keep_window(root, Vector3(0.26, 3.55, 1.04))
			_add_keep_window(root, Vector3(-1.70, 4.28, 1.04))
			_add_keep_window(root, Vector3(0.26, 4.28, 1.04))
			var keep_upper := BoxMesh.new()
			keep_upper.size = Vector3(2.88, 2.35, 2.50)
			_add_object_mesh(root, keep_upper, Vector3(-0.43, 6.15, -0.62), Color("aaa391"))
			_add_keep_window(root, Vector3(-1.18, 6.06, 0.67), 0.15, 0.68)
			_add_keep_window(root, Vector3(0.34, 6.06, 0.67), 0.15, 0.68)
			var keep_roof := PrismMesh.new()
			keep_roof.size = Vector3(3.20, 1.45, 2.78)
			_add_object_mesh(root, keep_roof, Vector3(-0.43, 8.00, -0.62), Color("55463d"))
			for side in range(4):
				var parapet := BoxMesh.new()
				var parapet_position: Vector3
				if side < 2:
					parapet.size = Vector3(3.15, 0.26, 0.30)
					parapet_position = Vector3(-0.43, 7.38, -0.62 + (-1.22 if side == 0 else 1.22))
				else:
					parapet.size = Vector3(0.30, 0.26, 2.55)
					parapet_position = Vector3(-0.43 + (-1.38 if side == 2 else 1.38), 7.38, -0.62)
				_add_object_mesh(root, parapet, parapet_position, Color("999486"))
				for merlon_index in range(6):
					var merlon := BoxMesh.new()
					merlon.size = Vector3(0.28, 0.34, 0.34)
					if side < 2:
						var mx := -1.72 + float(merlon_index) * 0.52
						var mz := -1.86 if side == 0 else 0.62
						_add_object_mesh(root, merlon, Vector3(mx, 7.66, mz), Color("aaa494"))
					else:
						var mz := -1.62 + float(merlon_index) * 0.52
						var mx := -1.81 if side == 2 else 0.95
						_add_object_mesh(root, merlon, Vector3(mx, 7.66, mz), Color("aaa494"))
			# An octagonal belfry rises behind the keep, with deep dark openings.
			var belfry := CylinderMesh.new()
			belfry.top_radius = 0.82
			belfry.bottom_radius = 0.98
			belfry.height = 2.55
			belfry.radial_segments = 8
			_add_object_mesh(root, belfry, Vector3(-0.25, 9.23, -1.05), Color("969082"))
			var belfry_roof := CylinderMesh.new()
			belfry_roof.top_radius = 0.0
			belfry_roof.bottom_radius = 1.25
			belfry_roof.height = 1.38
			belfry_roof.radial_segments = 8
			_add_object_mesh(root, belfry_roof, Vector3(-0.25, 11.18, -1.05), Color("493d35"))
			for opening in range(4):
				var opening_angle := TAU * float(opening) / 4.0
				var shutter := BoxMesh.new()
				shutter.size = Vector3(0.28, 0.62, 0.06)
				_add_object_mesh(root, shutter, Vector3(-0.25 + cos(opening_angle) * 0.93, 9.48, -1.05 + sin(opening_angle) * 0.93), Color("282a29"))
			# Chapel, hall, and well make the courtyard a lived-in inner ward.
			var chapel := BoxMesh.new()
			chapel.size = Vector3(2.35, 1.52, 1.78)
			_add_object_mesh(root, chapel, Vector3(1.70, 1.08, -1.62), Color("9a927e"))
			var chapel_roof := PrismMesh.new()
			chapel_roof.size = Vector3(2.62, 1.08, 2.02)
			_add_object_mesh(root, chapel_roof, Vector3(1.70, 2.38, -1.62), Color("59463d"))
			var hall := BoxMesh.new()
			hall.size = Vector3(2.25, 1.22, 1.72)
			_add_object_mesh(root, hall, Vector3(-2.20, 0.83, -1.55), Color("a2947f"))
			var hall_roof := PrismMesh.new()
			hall_roof.size = Vector3(2.50, 0.90, 1.98)
			_add_object_mesh(root, hall_roof, Vector3(-2.20, 1.86, -1.55), Color("55463d"))
			var courtyard_well := CylinderMesh.new()
			courtyard_well.top_radius = 0.36
			courtyard_well.bottom_radius = 0.46
			courtyard_well.height = 0.58
			courtyard_well.radial_segments = 10
			_add_object_mesh(root, courtyard_well, Vector3(0.50, 0.32, -2.10), Color("a09b8e"))
		"gatehouse":
			var gate_tower := BoxMesh.new()
			gate_tower.size = Vector3(0.74, 2.65, 0.84)
			_add_object_mesh(root, gate_tower, Vector3(-0.84, 1.34, 0.0), Color("888477"))
			_add_object_mesh(root, gate_tower, Vector3(0.84, 1.34, 0.0), Color("888477"))
			var gate_lintel := BoxMesh.new()
			gate_lintel.size = Vector3(2.50, 0.70, 1.02)
			_add_object_mesh(root, gate_lintel, Vector3(0.0, 2.43, 0.0), Color("9d9687"))
			var gate_roof := PrismMesh.new()
			gate_roof.size = Vector3(2.78, 0.82, 1.26)
			_add_object_mesh(root, gate_roof, Vector3(0.0, 3.20, 0.0), Color("514139"))
			var gate_door := BoxMesh.new()
			gate_door.size = Vector3(1.12, 1.75, 0.10)
			_add_object_mesh(root, gate_door, Vector3(0.0, 0.90, 0.54), Color("49382b"))
		"stone_wall_low":
			var low_wall := BoxMesh.new()
			low_wall.size = Vector3(2.35, 0.62, 0.42)
			_add_object_mesh(root, low_wall, Vector3(0.0, 0.33, 0.0), Color("8d8a7e"))
			var low_cap := BoxMesh.new()
			low_cap.size = Vector3(2.45, 0.12, 0.50)
			_add_object_mesh(root, low_cap, Vector3(0.0, 0.70, 0.0), Color("aaa494"))
		"palisade":
			var palisade_rail := BoxMesh.new()
			palisade_rail.size = Vector3(2.15, 0.12, 0.12)
			_add_object_mesh(root, palisade_rail, Vector3(0.0, 0.68, 0.0), Color("64472f"))
			for stake_index in range(8):
				var stake := PrismMesh.new()
				stake.size = Vector3(0.24, 1.34, 0.26)
				var stake_node := _add_object_mesh(root, stake, Vector3(-0.94 + float(stake_index) * 0.27, 0.65, 0.0), Color("805d3e"))
				stake_node.rotation.y = PI * 0.5
		"stone_bridge":
			var stone_deck := BoxMesh.new()
			stone_deck.size = Vector3(7.60, 0.42, 1.92)
			_add_object_mesh(root, stone_deck, Vector3(0.0, 0.52, 0.0), Color("8b8b80"))
			var stone_curb := BoxMesh.new()
			stone_curb.size = Vector3(7.64, 0.34, 0.18)
			_add_object_mesh(root, stone_curb, Vector3(0.0, 0.87, -0.90), Color("aaa597"))
			_add_object_mesh(root, stone_curb, Vector3(0.0, 0.87, 0.90), Color("aaa597"))
			var bridge_block := BoxMesh.new()
			bridge_block.size = Vector3(0.35, 0.10, 1.60)
			for block_index in range(20):
				_add_object_mesh(root, bridge_block, Vector3(-3.45 + float(block_index) * 0.36, 0.77, 0.0), Color("aaa394"))
			for arch_index in range(5):
				var pier := BoxMesh.new()
				pier.size = Vector3(0.38, 0.94, 1.80)
				_add_object_mesh(root, pier, Vector3(-3.0 + float(arch_index) * 1.5, 0.0, 0.0), Color("77776e"))
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
		"birch":
			var birch_trunk := CylinderMesh.new()
			birch_trunk.top_radius = 0.055
			birch_trunk.bottom_radius = 0.12
			birch_trunk.height = 1.80
			birch_trunk.radial_segments = 7
			_add_object_mesh(root, birch_trunk, Vector3(0.0, 0.90, 0.0), Color("d2cdb7"))
			var birch_mark := BoxMesh.new()
			birch_mark.size = Vector3(0.14, 0.06, 0.018)
			for mark_index in range(4):
				_add_object_mesh(root, birch_mark, Vector3(0.0, 0.38 + float(mark_index) * 0.30, 0.116), Color("493f36"))
			var birch_crown := SphereMesh.new()
			birch_crown.radius = 0.44
			birch_crown.height = 0.92
			birch_crown.radial_segments = 7
			birch_crown.rings = 4
			_add_object_mesh(root, birch_crown, Vector3(0.0, 1.82, 0.0), Color("5d884b"), Vector3(0.78, 1.10, 0.78))
			_add_object_mesh(root, birch_crown, Vector3(0.24, 1.55, -0.10), Color("82a75c"), Vector3(0.62, 0.76, 0.64))
		"fruit_tree":
			var fruit_trunk := CylinderMesh.new()
			fruit_trunk.top_radius = 0.08
			fruit_trunk.bottom_radius = 0.13
			fruit_trunk.height = 0.92
			fruit_trunk.radial_segments = 7
			_add_object_mesh(root, fruit_trunk, Vector3(0.0, 0.46, 0.0), Color("765338"))
			var fruit_crown := SphereMesh.new()
			fruit_crown.radius = 0.48
			fruit_crown.height = 0.85
			fruit_crown.radial_segments = 7
			fruit_crown.rings = 4
			_add_object_mesh(root, fruit_crown, Vector3(0.0, 1.05, 0.0), Color("4e7b3c"))
			var fruit := SphereMesh.new()
			fruit.radius = 0.09
			fruit.height = 0.16
			fruit.radial_segments = 6
			fruit.rings = 3
			for fruit_index in range(7):
				var angle := TAU * float(fruit_index) / 7.0
				_add_object_mesh(root, fruit, Vector3(cos(angle) * 0.38, 0.94 + float(fruit_index % 3) * 0.18, sin(angle) * 0.38), Color("c85b35"))
		"oak":
			var oak_trunk := CylinderMesh.new()
			oak_trunk.top_radius = 0.075
			oak_trunk.bottom_radius = 0.15
			oak_trunk.height = 0.98
			oak_trunk.radial_segments = 8
			_add_object_mesh(root, oak_trunk, Vector3(0.0, 0.49, 0.0), Color("765338"))
			var branch := CylinderMesh.new()
			branch.top_radius = 0.035
			branch.bottom_radius = 0.065
			branch.height = 0.68
			branch.radial_segments = 6
			for branch_index in range(4):
				var angle := TAU * float(branch_index) / 4.0 + 0.35
				var branch_node := _add_object_mesh(root, branch, Vector3(cos(angle) * 0.24, 0.82, sin(angle) * 0.24), Color("765338"))
				branch_node.rotation.z = cos(angle) * 0.82
				branch_node.rotation.x = sin(angle) * 0.82
			var crown := SphereMesh.new()
			crown.radius = 0.43
			crown.height = 0.78
			crown.radial_segments = 8
			crown.rings = 5
			_add_object_mesh(root, crown, Vector3(0.0, 1.13, 0.0), Color("47753c"), Vector3(1.0, 0.86, 1.0))
			_add_object_mesh(root, crown, Vector3(-0.31, 1.00, 0.12), Color("588642"), Vector3(0.72, 0.74, 0.76))
			_add_object_mesh(root, crown, Vector3(0.30, 1.08, -0.14), Color("64934a"), Vector3(0.70, 0.78, 0.72))
			_add_object_mesh(root, crown, Vector3(0.02, 1.42, 0.28), Color("54813f"), Vector3(0.74, 0.72, 0.74))
			_add_object_mesh(root, crown, Vector3(-0.08, 1.36, -0.28), Color("6a944c"), Vector3(0.68, 0.70, 0.68))
		"pine":
			var pine_trunk := CylinderMesh.new()
			pine_trunk.top_radius = 0.055
			pine_trunk.bottom_radius = 0.105
			pine_trunk.height = 1.58
			pine_trunk.radial_segments = 8
			_add_object_mesh(root, pine_trunk, Vector3(0.0, 0.79, 0.0), Color("74513a"))
			for tier in range(4):
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.46 - float(tier) * 0.065
				cone.height = 0.72
				cone.radial_segments = 9
				_add_object_mesh(root, cone, Vector3(0.0, 0.57 + float(tier) * 0.32, 0.0), [Color("315f3e"), Color("3d7544"), Color("4a8248"), Color("5a8b4d")][tier])
				if tier < 3:
					var pine_branch := CylinderMesh.new()
					pine_branch.top_radius = 0.025
					pine_branch.bottom_radius = 0.045
					pine_branch.height = 0.36 - float(tier) * 0.04
					pine_branch.radial_segments = 5
					for arm in range(3):
						var angle := TAU * float(arm) / 3.0 + float(tier) * 0.42
						var arm_node := _add_object_mesh(root, pine_branch, Vector3(cos(angle) * 0.17, 0.50 + float(tier) * 0.32, sin(angle) * 0.17), Color("74513a"))
						arm_node.rotation.z = cos(angle) * 0.95
						arm_node.rotation.x = sin(angle) * 0.95
		"outcrop":
			var outcrop_rock := SphereMesh.new()
			outcrop_rock.radius = 0.60
			outcrop_rock.height = 0.92
			outcrop_rock.radial_segments = 6
			outcrop_rock.rings = 3
			var outcrop_a := _add_object_mesh(root, outcrop_rock, Vector3(-0.38, 0.40, -0.08), Color("777970"), Vector3(1.22, 0.85, 0.90))
			outcrop_a.rotation.z = -0.12
			var outcrop_b := _add_object_mesh(root, outcrop_rock, Vector3(0.32, 0.32, 0.14), Color("92938b"), Vector3(0.86, 0.72, 0.82))
			outcrop_b.rotation.z = 0.16
			_add_object_mesh(root, outcrop_rock, Vector3(0.0, 0.64, -0.10), Color("a1a195"), Vector3(0.70, 0.84, 0.72))
			for chip_index in range(5):
				var chip := SphereMesh.new()
				chip.radius = 0.22 + float(chip_index % 2) * 0.06
				chip.height = 0.30 + float(chip_index % 3) * 0.04
				chip.radial_segments = 6
				chip.rings = 3
				var angle := TAU * float(chip_index) / 5.0
				var chip_node := _add_object_mesh(root, chip, Vector3(cos(angle) * 0.66, 0.13 + float(chip_index % 2) * 0.04, sin(angle) * 0.52), [Color("777970"), Color("888980"), Color("98988d")][chip_index % 3])
				chip_node.rotation.y = angle
			# Small lichen patches catch light and break up the bare gray mass.
			for lichen_index in range(3):
				var lichen := SphereMesh.new()
				lichen.radius = 0.13
				lichen.height = 0.07
				lichen.radial_segments = 6
				lichen.rings = 2
				_add_object_mesh(root, lichen, Vector3(-0.22 + float(lichen_index) * 0.20, 0.48 + float(lichen_index % 2) * 0.12, 0.34), Color("71805a"), Vector3(1.0, 0.30, 0.56))
		"haystack":
			var hay := CylinderMesh.new()
			hay.top_radius = 0.04
			hay.bottom_radius = 0.52
			hay.height = 0.95
			hay.radial_segments = 9
			_add_object_mesh(root, hay, Vector3(0.0, 0.48, 0.0), Color("c3a65e"))
			var hay_band := TorusMesh.new()
			hay_band.inner_radius = 0.43
			hay_band.outer_radius = 0.49
			_add_object_mesh(root, hay_band, Vector3(0.0, 0.33, 0.0), Color("8e7141"))
		"well":
			var well_ring := TorusMesh.new()
			well_ring.inner_radius = 0.31
			well_ring.outer_radius = 0.48
			_add_object_mesh(root, well_ring, Vector3(0.0, 0.30, 0.0), Color("8d8a7d"))
			var well_pillar := CylinderMesh.new()
			well_pillar.top_radius = 0.07
			well_pillar.bottom_radius = 0.07
			well_pillar.height = 1.18
			well_pillar.radial_segments = 6
			_add_object_mesh(root, well_pillar, Vector3(-0.47, 0.72, 0.0), Color("684b32"))
			_add_object_mesh(root, well_pillar, Vector3(0.47, 0.72, 0.0), Color("684b32"))
			var well_beam := BoxMesh.new()
			well_beam.size = Vector3(1.15, 0.12, 0.12)
			_add_object_mesh(root, well_beam, Vector3(0.0, 1.34, 0.0), Color("765538"))
			var well_roof := PrismMesh.new()
			well_roof.size = Vector3(1.35, 0.70, 1.00)
			_add_object_mesh(root, well_roof, Vector3(0.0, 1.70, 0.0), Color("514039"), Vector3.ONE, 3)
			var well_water := CylinderMesh.new()
			well_water.top_radius = 0.30
			well_water.bottom_radius = 0.30
			well_water.height = 0.018
			well_water.radial_segments = 12
			_add_object_mesh(root, well_water, Vector3(0.0, 0.36, 0.0), Color("315f68"), Vector3.ONE, 4)
			var winch := CylinderMesh.new()
			winch.top_radius = 0.065
			winch.bottom_radius = 0.065
			winch.height = 1.08
			winch.radial_segments = 8
			var winch_node := _add_object_mesh(root, winch, Vector3(0.0, 1.16, 0.0), Color("765538"), Vector3.ONE, 1)
			winch_node.rotation.z = PI * 0.5
			var rope := CylinderMesh.new()
			rope.top_radius = 0.025
			rope.bottom_radius = 0.025
			rope.height = 0.54
			rope.radial_segments = 5
			_add_object_mesh(root, rope, Vector3(0.0, 0.82, 0.0), Color("b49b70"), Vector3.ONE, 1)
			var crank := BoxMesh.new()
			crank.size = Vector3(0.10, 0.42, 0.10)
			_add_object_mesh(root, crank, Vector3(0.57, 1.18, 0.0), Color("765538"), Vector3.ONE, 1)
		"camp":
			var tent := PrismMesh.new()
			tent.size = Vector3(1.15, 0.95, 1.42)
			_add_object_mesh(root, tent, Vector3(-0.32, 0.48, 0.0), Color("a78a55"))
			var tent_flap := BoxMesh.new()
			tent_flap.size = Vector3(0.48, 0.63, 0.05)
			_add_object_mesh(root, tent_flap, Vector3(-0.32, 0.34, 0.72), Color("544332"))
			var camp_log := CylinderMesh.new()
			camp_log.top_radius = 0.07
			camp_log.bottom_radius = 0.08
			camp_log.height = 0.65
			camp_log.radial_segments = 6
			var log_a := _add_object_mesh(root, camp_log, Vector3(0.45, 0.10, 0.22), Color("694c31"))
			log_a.rotation.z = PI * 0.5
			var log_b := _add_object_mesh(root, camp_log, Vector3(0.45, 0.10, -0.22), Color("765438"), Vector3.ONE, 1)
			log_b.rotation.z = PI * 0.5
			var ridge_pole := CylinderMesh.new()
			ridge_pole.top_radius = 0.035
			ridge_pole.bottom_radius = 0.045
			ridge_pole.height = 1.50
			ridge_pole.radial_segments = 5
			var pole_node := _add_object_mesh(root, ridge_pole, Vector3(-0.32, 0.76, 0.0), Color("79583a"), Vector3.ONE, 1)
			pole_node.rotation.z = PI * 0.5
			for rope_side in [-1.0, 1.0]:
				var guy_rope := CylinderMesh.new()
				guy_rope.top_radius = 0.012
				guy_rope.bottom_radius = 0.012
				guy_rope.height = 0.62
				guy_rope.radial_segments = 4
				var rope_node := _add_object_mesh(root, guy_rope, Vector3(-0.32 + rope_side * 0.48, 0.28, 0.60), Color("b39a6b"), Vector3.ONE, 1)
				rope_node.rotation.z = rope_side * -0.90
		"boulder":
			var rock := SphereMesh.new()
			rock.radius = 0.48
			rock.height = 0.78
			rock.radial_segments = 7
			rock.rings = 4
			var main_boulder := _add_object_mesh(root, rock, Vector3(0.0, 0.30, 0.0), Color("77776d"), Vector3(1.25, 0.78, 0.92))
			main_boulder.rotation.y = 0.28
			for shard_index in range(3):
				var shard := SphereMesh.new()
				shard.radius = 0.20 + float(shard_index % 2) * 0.055
				shard.height = 0.26
				shard.radial_segments = 6
				shard.rings = 3
				var angle := TAU * float(shard_index) / 3.0 + 0.5
				var shard_node := _add_object_mesh(root, shard, Vector3(cos(angle) * 0.51, 0.10, sin(angle) * 0.38), Color("898a80"))
				shard_node.rotation.y = angle
			var lichen := SphereMesh.new()
			lichen.radius = 0.12
			lichen.height = 0.055
			lichen.radial_segments = 6
			lichen.rings = 2
			_add_object_mesh(root, lichen, Vector3(-0.22, 0.44, 0.35), Color("71805a"), Vector3(1.0, 0.30, 0.56))
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

func _add_keep_window(root: Node3D, center: Vector3, width: float = 0.20, height: float = 0.82) -> void:
	var recess := BoxMesh.new()
	recess.size = Vector3(width, height, 0.07)
	_add_object_mesh(root, recess, center, Color("282b29"))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(width + 0.14, 0.12, 0.12)
	_add_object_mesh(root, lintel, center + Vector3(0.0, height * 0.5 + 0.07, 0.0), Color("b1a996"))
	var sill := BoxMesh.new()
	sill.size = Vector3(width + 0.18, 0.11, 0.16)
	_add_object_mesh(root, sill, center + Vector3(0.0, -height * 0.5 - 0.06, 0.025), Color("8f897b"))

func _add_building_shell(root: Node3D, footprint: Vector3, wall_height: float, wall_color: Color, roof_color: Color, door_color: Color) -> void:
	var foundation := BoxMesh.new()
	foundation.size = Vector3(footprint.x + 0.16, 0.16, footprint.z + 0.16)
	_add_object_mesh(root, foundation, Vector3(0.0, 0.08, 0.0), wall_color.darkened(0.18))
	var walls := BoxMesh.new()
	walls.size = Vector3(footprint.x, wall_height, footprint.z)
	_add_object_mesh(root, walls, Vector3(0.0, 0.16 + wall_height * 0.5, 0.0), wall_color)
	var roof := PrismMesh.new()
	roof.size = Vector3(footprint.x + 0.28, maxf(0.64, footprint.y * 1.22), footprint.z + 0.32)
	_add_object_mesh(root, roof, Vector3(0.0, wall_height + 0.22, 0.0), roof_color, Vector3.ONE, 3)
	# Eaves, ridge cap and exposed rafter ends give the roof a built, layered silhouette.
	var ridge := CylinderMesh.new()
	ridge.top_radius = 0.075
	ridge.bottom_radius = 0.075
	ridge.height = footprint.x + 0.34
	ridge.radial_segments = 7
	var ridge_instance := _add_object_mesh(root, ridge, Vector3(0.0, wall_height + 0.58, 0.0), roof_color.lightened(0.16), Vector3.ONE, 3)
	ridge_instance.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		var eave := BoxMesh.new()
		eave.size = Vector3(footprint.x + 0.38, 0.10, 0.13)
		_add_object_mesh(root, eave, Vector3(0.0, wall_height + 0.12, side * (footprint.z * 0.5 + 0.12)), roof_color.darkened(0.12), Vector3.ONE, 3)
		for rafter_index in range(3):
			var rafter := BoxMesh.new()
			rafter.size = Vector3(0.09, 0.30, 0.10)
			var rafter_node := _add_object_mesh(root, rafter, Vector3(-footprint.x * 0.34 + float(rafter_index) * footprint.x * 0.34, wall_height + 0.08, side * (footprint.z * 0.5 + 0.14)), wall_color.darkened(0.18), Vector3.ONE, 1)
			rafter_node.rotation.x = side * -0.24
	# A restrained timber frame breaks up broad wall surfaces and makes close views read as construction.
	for x_side in [-1.0, 1.0]:
		var corner_post := BoxMesh.new()
		corner_post.size = Vector3(0.105, wall_height, 0.11)
		_add_object_mesh(root, corner_post, Vector3(x_side * (footprint.x * 0.5 - 0.07), 0.16 + wall_height * 0.5, footprint.z * 0.5 + 0.018), wall_color.darkened(0.20), Vector3.ONE, 1)
	var facade_beam := BoxMesh.new()
	facade_beam.size = Vector3(footprint.x, 0.10, 0.10)
	_add_object_mesh(root, facade_beam, Vector3(0.0, 0.16 + wall_height * 0.28, footprint.z * 0.5 + 0.02), wall_color.darkened(0.14), Vector3.ONE, 1)
	var door := BoxMesh.new()
	door.size = Vector3(0.30, wall_height * 0.73, 0.07)
	_add_object_mesh(root, door, Vector3(0.0, 0.16 + door.size.y * 0.5, footprint.z * 0.5 + 0.045), door_color, Vector3.ONE, 1)
	for plank_index in [-1.0, 1.0]:
		var plank := BoxMesh.new()
		plank.size = Vector3(0.018, door.size.y * 0.88, 0.018)
		_add_object_mesh(root, plank, Vector3(plank_index * 0.075, 0.16 + door.size.y * 0.5, footprint.z * 0.5 + 0.087), door_color.lightened(0.12), Vector3.ONE, 1)
	var handle := SphereMesh.new()
	handle.radius = 0.035
	handle.height = 0.07
	handle.radial_segments = 6
	handle.rings = 3
	_add_object_mesh(root, handle, Vector3(0.09, 0.16 + door.size.y * 0.52, footprint.z * 0.5 + 0.10), Color("b89a58"), Vector3.ONE, 4)
	var doorstep := BoxMesh.new()
	doorstep.size = Vector3(0.48, 0.09, 0.20)
	_add_object_mesh(root, doorstep, Vector3(0.0, 0.05, footprint.z * 0.5 + 0.13), wall_color.lightened(0.10), Vector3.ONE, 0)
	var window_y := 0.16 + wall_height * 0.64
	var window_z := footprint.z * 0.5 + 0.045
	_add_building_window(root, Vector3(-footprint.x * 0.28, window_y, window_z), 0.19)
	_add_building_window(root, Vector3(footprint.x * 0.28, window_y, window_z), 0.19)
	var side_window := BoxMesh.new()
	side_window.size = Vector3(0.06, 0.22, 0.18)
	_add_object_mesh(root, side_window, Vector3(footprint.x * 0.5 + 0.035, window_y, -footprint.z * 0.12), Color("718184"))

func _add_building_window(root: Node3D, position: Vector3, width: float) -> void:
	var frame := BoxMesh.new()
	frame.size = Vector3(width + 0.12, 0.34, 0.07)
	_add_object_mesh(root, frame, position, Color("594536"), Vector3.ONE, 1)
	var pane := BoxMesh.new()
	pane.size = Vector3(width, 0.24, 0.035)
	_add_object_mesh(root, pane, position + Vector3(0.0, 0.0, 0.045), Color("657c80"), Vector3.ONE, 4)
	var mullion := BoxMesh.new()
	mullion.size = Vector3(0.035, 0.24, 0.04)
	_add_object_mesh(root, mullion, position + Vector3(0.0, 0.0, 0.068), Color("594536"), Vector3.ONE, 1)
	var crossbar := BoxMesh.new()
	crossbar.size = Vector3(width, 0.035, 0.04)
	_add_object_mesh(root, crossbar, position + Vector3(0.0, 0.0, 0.068), Color("594536"), Vector3.ONE, 1)
	var sill := BoxMesh.new()
	sill.size = Vector3(width + 0.18, 0.07, 0.13)
	_add_object_mesh(root, sill, position + Vector3(0.0, -0.20, 0.035), Color("756047"), Vector3.ONE, 1)
	for side in [-1.0, 1.0]:
		var shutter := BoxMesh.new()
		shutter.size = Vector3(0.09, 0.28, 0.055)
		_add_object_mesh(root, shutter, position + Vector3(side * (width * 0.5 + 0.07), 0.0, 0.045), Color("594536"), Vector3.ONE, 1)

func _add_building_chimney(root: Node3D, position: Vector3) -> void:
	var chimney := CylinderMesh.new()
	chimney.top_radius = 0.10
	chimney.bottom_radius = 0.14
	chimney.height = 0.74
	chimney.radial_segments = 7
	_add_object_mesh(root, chimney, position, Color("776957"))
	var chimney_cap := BoxMesh.new()
	chimney_cap.size = Vector3(0.30, 0.10, 0.25)
	_add_object_mesh(root, chimney_cap, position + Vector3(0.0, 0.40, 0.0), Color("8d8171"))

func _castle_ring_points(radius_x: float, radius_z: float, offset: Vector2, phase: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var irregularity: Array[float] = [1.0, 0.94, 1.06, 0.97, 1.03, 0.91, 1.05, 0.96, 1.04, 0.93, 1.07, 0.98]
	for point_index in range(12):
		var angle := TAU * float(point_index) / 12.0 + phase
		var factor: float = irregularity[point_index]
		points.append(offset + Vector2(cos(angle) * radius_x * factor, sin(angle) * radius_z * factor))
	return points

func _add_castle_wall_ring(root: Node3D, points: Array[Vector2], center_y: float, wall_height: float, thickness: float, has_gate: bool, color: Color) -> void:
	for point_index in range(points.size()):
		var a := points[point_index]
		var b := points[(point_index + 1) % points.size()]
		var midpoint := (a + b) * 0.5
		if has_gate and midpoint.y > 0.78 * maxf(absf(a.y), absf(b.y)):
			continue
		var edge := b - a
		var length := edge.length()
		var yaw := atan2(-edge.y, edge.x)
		var wall := BoxMesh.new()
		wall.size = Vector3(length + 0.20, wall_height, thickness)
		var segment_center := Vector3(midpoint.x, center_y, midpoint.y)
		var wall_instance := _add_object_mesh(root, wall, segment_center, color)
		wall_instance.rotation.y = yaw
		var coping := BoxMesh.new()
		coping.size = Vector3(length + 0.26, 0.20, thickness + 0.16)
		var coping_instance := _add_object_mesh(root, coping, Vector3(midpoint.x, center_y + wall_height * 0.5 + 0.08, midpoint.y), color.lightened(0.12))
		coping_instance.rotation.y = yaw
		var merlons := maxi(1, roundi(length / 0.72))
		for merlon_index in range(merlons):
			var along := (float(merlon_index) + 0.5) / float(merlons) - 0.5
			var merlon := BoxMesh.new()
			merlon.size = Vector3(0.34, 0.34, thickness + 0.10)
			var position := Vector3(midpoint.x + edge.x * along, center_y + wall_height * 0.5 + 0.31, midpoint.y + edge.y * along)
			var merlon_instance := _add_object_mesh(root, merlon, position, color.lightened(0.20))
			merlon_instance.rotation.y = yaw

func _add_castle_tower(root: Node3D, point: Vector2, height: float, radius: float, color: Color) -> void:
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius * 0.94
	shaft.bottom_radius = radius * 1.08
	shaft.height = height
	shaft.radial_segments = 12
	_add_object_mesh(root, shaft, Vector3(point.x, height * 0.5, point.y), color)
	var battlement := CylinderMesh.new()
	battlement.top_radius = radius * 1.20
	battlement.bottom_radius = radius * 1.20
	battlement.height = 0.24
	battlement.radial_segments = 12
	_add_object_mesh(root, battlement, Vector3(point.x, height + 0.09, point.y), color.lightened(0.12))
	for crenel_index in range(8):
		var angle := TAU * float(crenel_index) / 8.0
		var crenel := BoxMesh.new()
		crenel.size = Vector3(0.28, 0.38, 0.32)
		var instance := _add_object_mesh(root, crenel, Vector3(point.x + cos(angle) * radius * 1.05, height + 0.36, point.y + sin(angle) * radius * 1.05), color.lightened(0.16))
		instance.rotation.y = -angle
	for slit_index in range(3):
		var slit_angle := TAU * float(slit_index) / 3.0 + 0.30
		var slit := BoxMesh.new()
		slit.size = Vector3(0.12, 0.48, 0.07)
		var slit_instance := _add_object_mesh(root, slit, Vector3(point.x + cos(slit_angle) * radius * 0.96, height * 0.60, point.y + sin(slit_angle) * radius * 0.96), Color("292b2a"))
		slit_instance.rotation.y = slit_angle + PI * 0.5
func _add_object_mesh(parent: Node3D, mesh: Mesh, local_position: Vector3, color: Color, local_scale: Vector3 = Vector3.ONE, surface_style: int = -1) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = local_position
	instance.scale = local_scale
	if parent.name in ["PlacedAshenreachCitadel", "PlacedIcehelmHold", "PlacedIronholdForge", "PlacedStormcrownKeep", "PlacedGrandStoneKeep", "PlacedHillFort", "PlacedRuinedFort"]:
		var castle_material := ShaderMaterial.new()
		castle_material.shader = load("res://assets/materials/castle_stone.gdshader") as Shader
		castle_material.set_shader_parameter("base_color", color)
		castle_material.set_shader_parameter("masonry", parent.name == "PlacedAshenreachCitadel" or (color.r > 0.40 and color.g > 0.40 and color.b > 0.36))
		instance.material_override = castle_material
	else:
		var prop_material := ShaderMaterial.new()
		prop_material.shader = load("res://assets/materials/prop_surface.gdshader") as Shader
		prop_material.set_shader_parameter("base_color", color)
		prop_material.set_shader_parameter("surface_style", surface_style if surface_style >= 0 else _prop_surface_style(color))
		prop_material.set_shader_parameter("detail_strength", 0.82)
		instance.material_override = prop_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance

func _prop_surface_style(color: Color) -> int:
	var brightness := (color.r + color.g + color.b) / 3.0
	if color.g > color.r * 1.08 and color.g > color.b * 1.10:
		return 2 # foliage
	if color.r > color.b * 1.45 and color.r > color.g * 0.98 and brightness < 0.47:
		return 3 # dark fired roof tile
	if color.b > color.r * 1.10 and color.b > color.g * 0.96 and brightness < 0.62:
		return 4 # metal, glass, or dark fittings
	if color.r > color.b * 1.25 and color.g > color.b * 1.18:
		return 1 # timber
	return 0 # stone

func _object_footprint_radius(kind: String) -> int:
	match kind:
		"castle", "fortress", "castle_ruin", "ashen_keep", "blackthorn_keep", "icehelm_hold", "ironhold_forge", "stormcrown_keep": return 5
		"bridge", "stone_bridge", "harbor_dock": return 2
		"silverkeep_lighthouse", "dragon_roost": return 1
		"gatehouse": return 1
		"wall", "basalt_wall", "fence": return 0
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
		var material := ShaderMaterial.new()
		material.shader = load("res://assets/materials/prop_surface.gdshader") as Shader
		material.set_shader_parameter("use_vertex_color", true)
		material.set_shader_parameter("surface_style", 0)
		material.set_shader_parameter("detail_strength", 0.42)
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
	var preset_name := _generation_preset_title(preset)
	var extra := " It also places the keep, bridge, cottages, roads, and forests." if preset == "kingdom" else (" It builds the volcano, lava rivers, obsidian ridges, and Citadel." if preset == "ashenreach" else (" It adds the region’s signature landmark and terrain dressing." if _is_territory_preset(preset) else ""))
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
	var is_ashenreach := _generation_preset == "ashenreach"
	var is_territory := _is_territory_preset(_generation_preset)
	var has_generated_objects := is_kingdom or is_ashenreach or is_territory
	var before_objects: Array[Node3D] = []
	if has_generated_objects:
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
		elif is_kingdom:
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
		elif is_ashenreach:
			var volcanic_dx := float(cell.x) - 41.0
			var volcanic_dz := (float(cell.y) - 27.0) * 0.86
			var volcano_distance := Vector2(volcanic_dx, volcanic_dz).length()
			var ridge_distance := absf(float(cell.x) - _ashenreach_ridge_x(float(cell.y)))
			var lava_distance := absf(float(cell.x) - _ashenreach_lava_x(float(cell.y)))
			var fork_distance := absf(float(cell.x) - _ashenreach_fork_x(float(cell.y)))
			var noise_value := broad.get_noise_2d(float(cell.x) * 0.075, float(cell.y) * 0.075)
			var volcanic_rise := clampf((12.5 - volcano_distance) / 12.5, 0.0, 1.0)
			var ridge_rise := clampf((5.6 - ridge_distance) / 5.6, 0.0, 1.0)
			level = roundi(1.0 + noise_value * 1.9 + volcanic_rise * 10.8 + ridge_rise * 7.2 + ridge_noise.get_noise_2d(float(cell.x) * 0.17, float(cell.y) * 0.12) * 1.6)
			if volcano_distance < 3.2:
				terrain = HexGrid.Terrain.LAVA
				level = 0
			elif volcano_distance < 4.1:
				terrain = HexGrid.Terrain.STONE
				level = maxi(level, 9)
			elif volcano_distance < 6.8 and volcano_distance > 5.1 and noise_value > -0.25:
				terrain = HexGrid.Terrain.STONE
				level = maxi(level, 7)
			elif lava_distance < 1.05 or (cell.y > 42 and fork_distance < 0.85):
				terrain = HexGrid.Terrain.LAVA
				level = 0
			elif lava_distance < 2.1 or (cell.y > 42 and fork_distance < 1.75):
				terrain = HexGrid.Terrain.STONE if noise_value > 0.2 else HexGrid.Terrain.MUD
				level = mini(level, 1)
			elif ridge_distance < 2.8 and level >= 5:
				terrain = HexGrid.Terrain.STONE
			elif level <= 1 and noise_value < -0.2:
				terrain = HexGrid.Terrain.MUD
			else:
				terrain = HexGrid.Terrain.ASH
			var keep_distance := _kingdom_hex_distance(cell, Vector2i(32, 68))
			if keep_distance <= 6 and cell.y > 48 and cell.y < 91 and volcano_distance > 13.0:
				level = clampi(maxi(level, 6 - floori(float(keep_distance) * 0.34)), 4, 8)
				if terrain == HexGrid.Terrain.LAVA or terrain == HexGrid.Terrain.MUD:
					terrain = HexGrid.Terrain.ASH if keep_distance > 4 else HexGrid.Terrain.STONE
		elif is_territory:
			var region_data := _territory_landscape(_generation_preset, cell, broad_value, ridge_noise)
			level = int(region_data["level"])
			terrain = int(region_data["terrain"])
			var landmark_distance := _kingdom_hex_distance(cell, _territory_landmark_cell(_generation_preset))
			if landmark_distance <= 5:
				level = clampi(maxi(level, 5 - floori(float(landmark_distance) * 0.24)), 3, 9)
				if terrain == HexGrid.Terrain.WATER or terrain == HexGrid.Terrain.LAVA:
					terrain = HexGrid.Terrain.STONE if _generation_preset in ["frostpeaks", "drakeshard", "stormcrown"] else HexGrid.Terrain.GRASS
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
		if has_generated_objects:
			after_terrain[index] = {"elevation": bounded_level, "terrain": terrain}

	board_view.refresh_all()
	var generated_objects: Array[Node3D] = []
	if is_kingdom:
		generated_objects = _populate_kingdom_objects(broad.seed)
	elif is_ashenreach:
		generated_objects = _populate_ashenreach_objects(broad.seed)
	elif is_territory:
		generated_objects = _populate_territory_objects(_generation_preset, broad.seed)
	_resnap_all_objects()
	_last_stroke_cell = INVALID_CELL
	if has_generated_objects:
		_commit_undo({
			"_map_generation": true,
			"before_terrain": before_terrain,
			"after_terrain": after_terrain,
			"before_objects": before_objects,
			"after_objects": generated_objects
		})
	elif not before_terrain.is_empty():
		_commit_undo(before_terrain)
	var preset_name := _generation_preset_title(_generation_preset)
	tool_status.text = "Generated %s • Undo to restore" % preset_name
	_update_readout()

func _is_territory_preset(preset: String) -> bool:
	return preset in ["ravenwood", "blighted_marsh", "cursed_mire", "shadowfen", "frostpeaks", "drakeshard", "iron_plains", "veiled_sea", "ember_coast", "stormcrown"]

func _generation_preset_title(preset: String) -> String:
	var titles := {
		"island": "island", "highlands": "highlands", "kingdom": "kingdom",
		"ashenreach": "Ashenreach", "ravenwood": "Ravenwood • Blackthorn",
		"blighted_marsh": "Blighted Marsh", "cursed_mire": "Cursed Mire • Deadwind Hollow",
		"shadowfen": "Shadowfen Forest", "frostpeaks": "Frostpeaks • Icehelm",
		"drakeshard": "Drakeshard Range • Ironhold", "iron_plains": "Iron Plains • Harrowstead",
		"veiled_sea": "Veiled Sea • Silverkeep", "ember_coast": "Ember Coast • Dragon’s Rest",
		"stormcrown": "Stormcrown Keep"
	}
	return str(titles.get(preset, preset.capitalize()))

func _territory_landmark_cell(preset: String) -> Vector2i:
	match preset:
		"ravenwood": return Vector2i(21, 52)
		"blighted_marsh": return Vector2i(34, 63)
		"cursed_mire": return Vector2i(28, 76)
		"shadowfen": return Vector2i(43, 61)
		"frostpeaks": return Vector2i(32, 77)
		"drakeshard": return Vector2i(33, 64)
		"iron_plains": return Vector2i(32, 68)
		"veiled_sea": return Vector2i(47, 66)
		"ember_coast": return Vector2i(18, 73)
		"stormcrown": return Vector2i(35, 63)
		_: return Vector2i(32, 64)

func _territory_landscape(preset: String, cell: Vector2i, broad_value: float, ridge_noise: FastNoiseLite) -> Dictionary:
	var x := float(cell.x)
	var z := float(cell.y)
	var nx := (x / float(HexGrid.COLUMNS - 1) - 0.5) * 2.0
	var nz := (z / float(HexGrid.ROWS - 1) - 0.5) * 2.0
	var detail := ridge_noise.get_noise_2d(x * 0.12 + 83.0, z * 0.10 - 37.0)
	var ridge := 1.0 - absf(ridge_noise.get_noise_2d(x * 0.048 + 41.0, z * 0.043 - 73.0))
	var level := 1
	var terrain := HexGrid.Terrain.GRASS
	match preset:
		"ravenwood":
			var hollow := absf(x - (25.0 + sin(z * 0.045) * 9.0))
			level = roundi(2.0 + broad_value * 3.1 + ridge * 4.1 + detail * 1.2)
			if hollow < 1.6:
				terrain = HexGrid.Terrain.MUD
				level = mini(level, 1)
			elif ridge > 0.78 and level >= 5:
				terrain = HexGrid.Terrain.STONE
			elif broad_value < -0.2:
				terrain = HexGrid.Terrain.DIRT
		"blighted_marsh":
			var channel := absf(x - (27.0 + sin(z * 0.052) * 11.0 + sin(z * 0.12) * 2.0))
			var pools := ridge_noise.get_noise_2d(x * 0.11, z * 0.09)
			level = clampi(roundi(1.0 + broad_value * 1.4 + detail * 0.8), 0, 3)
			if channel < 1.05 or (pools < -0.52 and broad_value < 0.05):
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif channel < 3.2 or pools < -0.17:
				terrain = HexGrid.Terrain.MUD
			elif broad_value > 0.34:
				terrain = HexGrid.Terrain.GRASS
			else:
				terrain = HexGrid.Terrain.DIRT
		"cursed_mire":
			var bog := ridge_noise.get_noise_2d(x * 0.075 - 12.0, z * 0.075 + 55.0)
			var drowned_river := absf(x - (39.0 - z * 0.13 + sin(z * 0.065) * 7.0))
			level = clampi(roundi(0.6 + broad_value * 2.1 + detail), -1, 3)
			if drowned_river < 1.0 or (bog < -0.45 and broad_value < 0.12):
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif drowned_river < 2.8 or bog < 0.22:
				terrain = HexGrid.Terrain.MUD
			else:
				terrain = HexGrid.Terrain.DIRT
		"shadowfen":
			var fen_stream := absf(x - (45.0 + sin(z * 0.055) * 8.0))
			level = roundi(2.5 + broad_value * 3.0 + ridge * 4.8 + detail)
			if fen_stream < 1.0 and broad_value < 0.25:
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif fen_stream < 2.6 or broad_value < -0.34:
				terrain = HexGrid.Terrain.MUD
			elif level >= 7 and ridge > 0.80:
				terrain = HexGrid.Terrain.STONE
			else:
				terrain = HexGrid.Terrain.GRASS
		"frostpeaks":
			var alpine := ridge_noise.get_noise_2d(x * 0.055 + 120.0, z * 0.052 - 28.0)
			level = roundi(2.5 + absf(alpine) * 8.2 + broad_value * 2.8 + ridge * 3.8)
			if alpine < -0.58 and level < 8:
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif level >= 8 and alpine > 0.38:
				terrain = HexGrid.Terrain.STONE
			elif level >= 4 or broad_value < -0.1:
				terrain = HexGrid.Terrain.SNOW
			else:
				terrain = HexGrid.Terrain.GRASS
		"drakeshard":
			var spine_x := 31.0 + sin(z * 0.048) * 10.0 + sin(z * 0.12) * 2.5
			var spine_dist := absf(x - spine_x)
			level = roundi(1.8 + maxf(0.0, 8.8 - spine_dist * 1.35) + ridge * 3.5 + broad_value * 2.0)
			if spine_dist < 2.8 and level >= 8:
				terrain = HexGrid.Terrain.SNOW if level >= 12 else HexGrid.Terrain.STONE
			elif spine_dist < 5.2 or level >= 9:
				terrain = HexGrid.Terrain.STONE
			elif level <= 1:
				terrain = HexGrid.Terrain.MUD
			else:
				terrain = HexGrid.Terrain.GRASS
		"iron_plains":
			var river := absf(x - (44.0 - z * 0.18 + sin(z * 0.055) * 5.5))
			var road := absf(x - (17.0 + z * 0.15 + sin(z * 0.04) * 3.0))
			level = clampi(roundi(1.2 + broad_value * 2.0 + detail), 0, 4)
			if river < 0.85:
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif river < 2.2:
				terrain = HexGrid.Terrain.SAND
				level = 0
			elif road < 0.7:
				terrain = HexGrid.Terrain.ROAD
				level = mini(level, 1)
			elif (floori(float(cell.x) / 5.0) + floori(float(cell.y) / 8.0)) % 3 == 0:
				terrain = HexGrid.Terrain.DIRT
			else:
				terrain = HexGrid.Terrain.GRASS
		"veiled_sea":
			var island_distance := Vector2(nx * 1.18, nz * 0.82).length()
			level = roundi((0.98 - island_distance) * 20.0 + broad_value * 3.4 + detail)
			if island_distance > 0.92 or level < 0:
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif island_distance > 0.78:
				terrain = HexGrid.Terrain.SAND
				level = clampi(level, 0, 2)
			elif ridge > 0.78 and level > 7:
				terrain = HexGrid.Terrain.STONE
			else:
				terrain = HexGrid.Terrain.GRASS if broad_value > -0.28 else HexGrid.Terrain.DIRT
		"ember_coast":
			var coast := absf(x - (48.0 + sin(z * 0.045) * 5.0))
			var vent_center := Vector2(x - 20.0, (z - 35.0) * 0.8).length()
			var lava := absf(x - (22.0 + z * 0.17 + sin(z * 0.06) * 5.0))
			level = roundi(1.0 + broad_value * 2.4 + maxf(0.0, 11.0 - vent_center) * 0.7 + ridge * 3.0)
			if coast < 1.1:
				terrain = HexGrid.Terrain.WATER
				level = 0
			elif coast < 2.8:
				terrain = HexGrid.Terrain.SAND
				level = mini(level, 1)
			elif vent_center < 2.1 or (z > 40.0 and lava < 0.9):
				terrain = HexGrid.Terrain.LAVA
				level = 0
			elif vent_center < 4.6 or (z > 40.0 and lava < 2.0):
				terrain = HexGrid.Terrain.STONE
			elif vent_center < 9.0 or ridge > 0.78:
				terrain = HexGrid.Terrain.ASH
			else:
				terrain = HexGrid.Terrain.GRASS
		"stormcrown":
			var peak := Vector2(x - 34.0, (z - 61.0) * 0.72).length()
			level = roundi(1.0 + maxf(0.0, 17.0 - peak) * 0.72 + ridge * 5.0 + detail)
			if peak < 3.6 or (ridge > 0.84 and level > 9):
				terrain = HexGrid.Terrain.STONE
				level = maxi(level, 9)
			elif peak < 10.0 or level > 6:
				terrain = HexGrid.Terrain.SNOW
			elif level <= 1:
				terrain = HexGrid.Terrain.WATER
				level = 0
			else:
				terrain = HexGrid.Terrain.GRASS
	return {"level": level, "terrain": terrain}

func _ashenreach_ridge_x(row: float) -> float:
	var progress := row / float(HexGrid.ROWS - 1)
	return 18.0 + sin(progress * TAU * 1.35) * 6.8 + sin(progress * TAU * 3.4) * 2.1 + progress * 4.0

func _ashenreach_lava_x(row: float) -> float:
	var progress := clampf((row - 26.0) / 102.0, 0.0, 1.0)
	return 41.0 - 17.0 * progress + sin(progress * TAU * 1.45) * 5.2 + sin(progress * TAU * 3.7) * 1.6

func _ashenreach_fork_x(row: float) -> float:
	var progress := clampf((row - 46.0) / 70.0, 0.0, 1.0)
	return 41.0 + 9.0 * progress + sin(progress * TAU * 1.2) * 3.0

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

func _populate_territory_objects(preset: String, seed_value: int) -> Array[Node3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_value) ^ int(hash(preset))
	var spawned: Array[Node3D] = []
	var occupied: Dictionary = {}
	var center := _territory_landmark_cell(preset)
	var landmark_kind := "castle_ruin"
	match preset:
		"ravenwood": landmark_kind = "blackthorn_keep"
		"blighted_marsh": landmark_kind = "castle_ruin"
		"cursed_mire": landmark_kind = "castle_ruin"
		"shadowfen": landmark_kind = "castle_ruin"
		"frostpeaks": landmark_kind = "icehelm_hold"
		"drakeshard": landmark_kind = "ironhold_forge"
		"iron_plains": landmark_kind = "manor"
		"veiled_sea": landmark_kind = "silverkeep_lighthouse"
		"ember_coast": landmark_kind = "dragon_roost"
		"stormcrown": landmark_kind = "stormcrown_keep"
	_spawn_kingdom_object(landmark_kind, center, rng, occupied, spawned)
	if preset == "ravenwood":
		for edge in range(6):
			for distance in range(7, 10):
				var wall_cell := center + Vector2i(0, 0)
				var axial_center := grid.axial_coordinates(center)
				var axial_point := axial_center + HexGrid.EDGE_AXIAL_DIRECTIONS[edge] * distance
				wall_cell = Vector2i(axial_point.x + floori(float(axial_point.y) * 0.5), axial_point.y)
				if not grid.contains(wall_cell):
					continue
				var outward := grid.world_center(wall_cell) - grid.world_center(center)
				_spawn_kingdom_object("palisade", wall_cell, rng, occupied, spawned, rad_to_deg(atan2(outward.z, outward.x)) + 90.0)
	if preset == "veiled_sea":
		_spawn_kingdom_object("harbor_dock", Vector2i(51, 67), rng, occupied, spawned, -18.0)
	if preset == "iron_plains":
		for windmill_cell in [Vector2i(15, 28), Vector2i(51, 38), Vector2i(13, 103), Vector2i(52, 106)]:
			_spawn_kingdom_object("windmill", windmill_cell, rng, occupied, spawned, rng.randf_range(0.0, 360.0))
	if preset in ["ember_coast", "ashenreach"]:
		for row in range(43, 116, 12):
			var column := clampi(roundi(22.0 + float(row) * 0.17 + rng.randf_range(-2.0, 2.0)), 0, HexGrid.COLUMNS - 1)
			_spawn_kingdom_object("lava_vent", Vector2i(column, row), rng, occupied, spawned)
	var vegetation_kind := "pine"
	var tree_target := 96
	var scatter_radius := 42
	match preset:
		"ravenwood":
			vegetation_kind = "pine"
			tree_target = 145
			scatter_radius = 48
		"blighted_marsh", "cursed_mire", "shadowfen":
			vegetation_kind = "marsh_tree"
			tree_target = 112 if preset != "shadowfen" else 138
			scatter_radius = 50
		"frostpeaks":
			vegetation_kind = "pine"
			tree_target = 68
			scatter_radius = 40
		"drakeshard":
			vegetation_kind = "pine"
			tree_target = 38
			scatter_radius = 38
		"iron_plains":
			vegetation_kind = "oak"
			tree_target = 34
			scatter_radius = 54
		"veiled_sea":
			vegetation_kind = "oak"
			tree_target = 70
			scatter_radius = 44
		"ember_coast":
			vegetation_kind = "ash_tree"
			tree_target = 48
			scatter_radius = 45
		"stormcrown":
			vegetation_kind = "pine"
			tree_target = 72
			scatter_radius = 40
	var placed_trees := 0
	for attempt in range(tree_target * 40):
		if placed_trees >= tree_target:
			break
		var cell := Vector2i(
			rng.randi_range(maxi(1, center.x - scatter_radius), mini(HexGrid.COLUMNS - 2, center.x + scatter_radius)),
			rng.randi_range(maxi(1, center.y - scatter_radius), mini(HexGrid.ROWS - 2, center.y + scatter_radius))
		)
		var terrain := grid.terrain_at(cell)
		if _kingdom_hex_distance(cell, center) < 7 or terrain in [HexGrid.Terrain.WATER, HexGrid.Terrain.LAVA, HexGrid.Terrain.STONE, HexGrid.Terrain.ROAD]:
			continue
		if preset in ["frostpeaks", "stormcrown"] and terrain == HexGrid.Terrain.MUD:
			continue
		if preset in ["ember_coast"] and terrain not in [HexGrid.Terrain.ASH, HexGrid.Terrain.GRASS, HexGrid.Terrain.DIRT]:
			continue
		if occupied.has(grid.index_of(cell)):
			continue
		_spawn_kingdom_object(vegetation_kind, cell, rng, occupied, spawned)
		if occupied.has(grid.index_of(cell)):
			placed_trees += 1
	var building_target := 12
	if preset in ["ravenwood", "iron_plains", "veiled_sea"]:
		building_target = 24
	elif preset in ["blighted_marsh", "cursed_mire", "shadowfen"]:
		building_target = 7
	elif preset in ["drakeshard", "frostpeaks", "stormcrown"]:
		building_target = 5
	var placed_buildings := 0
	for attempt in range(building_target * 45):
		if placed_buildings >= building_target:
			break
		var cell := Vector2i(
			rng.randi_range(maxi(1, center.x - 27), mini(HexGrid.COLUMNS - 2, center.x + 27)),
			rng.randi_range(maxi(1, center.y - 28), mini(HexGrid.ROWS - 2, center.y + 28))
		)
		var terrain := grid.terrain_at(cell)
		var distance := _kingdom_hex_distance(cell, center)
		if distance < 7 or distance > 28 or occupied.has(grid.index_of(cell)):
			continue
		if terrain in [HexGrid.Terrain.WATER, HexGrid.Terrain.LAVA, HexGrid.Terrain.STONE, HexGrid.Terrain.SNOW]:
			continue
		var building_kind := "cottage"
		match preset:
			"iron_plains":
				building_kind = "farmhouse" if rng.randf() < 0.55 else "cottage"
			"veiled_sea":
				building_kind = "stone_house" if rng.randf() < 0.4 else "cottage"
			"ravenwood":
				building_kind = "cottage" if rng.randf() < 0.8 else "watchtower"
			"blighted_marsh", "cursed_mire", "shadowfen":
				building_kind = "camp" if rng.randf() < 0.7 else "cottage"
			_:
				building_kind = "cottage" if rng.randf() < 0.7 else "watchtower"
		_spawn_kingdom_object(building_kind, cell, rng, occupied, spawned)
		if occupied.has(grid.index_of(cell)):
			placed_buildings += 1
	return spawned

func _populate_ashenreach_objects(seed_value: int) -> Array[Node3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0xA5EED
	var spawned: Array[Node3D] = []
	var occupied: Dictionary = {}
	_spawn_kingdom_object("ashen_keep", Vector2i(32, 68), rng, occupied, spawned)
	for spire_cell in [Vector2i(35, 20), Vector2i(47, 25), Vector2i(32, 34), Vector2i(50, 36), Vector2i(37, 41), Vector2i(46, 46)]:
		_spawn_kingdom_object("basalt_spire", spire_cell, rng, occupied, spawned, rng.randf_range(0.0, 360.0))
	for row in range(34, 119, 9):
		var column := clampi(roundi(_ashenreach_lava_x(float(row)) + rng.randf_range(-2.0, 2.0)), 0, HexGrid.COLUMNS - 1)
		var vent_cell := Vector2i(column, row)
		if grid.terrain_at(vent_cell) != HexGrid.Terrain.LAVA:
			_spawn_kingdom_object("lava_vent", vent_cell, rng, occupied, spawned)
	var attempts := 0
	var trees := 0
	while trees < 42 and attempts < 1400:
		attempts += 1
		var cell := Vector2i(rng.randi_range(2, HexGrid.COLUMNS - 3), rng.randi_range(4, HexGrid.ROWS - 5))
		if occupied.has(grid.index_of(cell)) or _kingdom_hex_distance(cell, Vector2i(32, 68)) < 11:
			continue
		if absf(float(cell.x) - _ashenreach_lava_x(float(cell.y))) < 5.0:
			continue
		if grid.terrain_at(cell) == HexGrid.Terrain.LAVA or grid.terrain_at(cell) == HexGrid.Terrain.STONE:
			continue
		var kind := "ash_tree" if rng.randf() < 0.65 else "boulder"
		_spawn_kingdom_object(kind, cell, rng, occupied, spawned)
		if occupied.has(grid.index_of(cell)):
			trees += 1
	for ruin_cell in [Vector2i(10, 44), Vector2i(53, 89), Vector2i(11, 112), Vector2i(51, 57)]:
		if grid.terrain_at(ruin_cell) != HexGrid.Terrain.LAVA:
			_spawn_kingdom_object("castle_ruin", ruin_cell, rng, occupied, spawned)
	return spawned

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
	var field_origins: Array[Vector2i] = [Vector2i(36, 80), Vector2i(45, 80), Vector2i(54, 80), Vector2i(36, 94), Vector2i(54, 94), Vector2i(36, 108), Vector2i(45, 108), Vector2i(54, 108)]
	for field_origin in field_origins:
		for offset in range(5):
			var top_cell: Vector2i = field_origin + Vector2i(offset, 0)
			var bottom_cell: Vector2i = field_origin + Vector2i(offset, 6)
			var left_cell: Vector2i = field_origin + Vector2i(0, offset)
			var right_cell: Vector2i = field_origin + Vector2i(4, offset)
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
	var rotation := fixed_rotation if fixed_rotation >= 0.0 else (rng.randf_range(0.0, 360.0) if kind in ["cottage", "house", "oak", "pine", "boulder", "ash_tree", "basalt_spire"] else 0.0)
	var scale_factor := rng.randf_range(0.78, 1.12) if kind not in ["castle", "bridge", "ashen_keep"] else 1.0
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
		grid.terrain_ids[index] = clampi(int(terrain_value[index]), HexGrid.Terrain.GRASS, HexGrid.Terrain.LAVA)
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
			if not grid.contains(cell) or not ["house", "cottage", "stone_house", "farmhouse", "manor", "tavern", "chapel", "watchtower", "windmill", "blackthorn_keep", "icehelm_hold", "ironhold_forge", "stormcrown_keep", "marsh_tree", "silverkeep_lighthouse", "harbor_dock", "dragon_roost", "ashen_keep", "basalt_wall", "ash_tree", "basalt_spire", "lava_vent", "castle", "fortress", "castle_ruin", "gatehouse", "bridge", "stone_bridge", "wall", "stone_wall_low", "palisade", "fence", "oak", "pine", "birch", "fruit_tree", "boulder", "outcrop", "haystack", "well", "camp", "marker"].has(kind):
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
