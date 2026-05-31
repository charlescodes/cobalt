class_name EditorPanel
extends PanelContainer

const GroundDataScript := preload("res://src/environment/ground_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const BspBuildingGeneratorScript := preload("res://src/generation/bsp_building_generator.gd")

const TOOL_SELECT_INSPECT: StringName = &"select_inspect"
const TOOL_NPC_BRUSH: StringName = &"npc_brush"
const TOOL_PC_BRUSH: StringName = &"pc_brush"
const TOOL_WALL_BRUSH: StringName = &"wall_brush"
const TOOL_DOOR_BRUSH: StringName = &"door_brush"
const TOOL_BUILDING_BRUSH: StringName = &"building_brush"
const WALL_BRUSH_MODE_LINE: StringName = &"line"
const WALL_BRUSH_MODE_RECTANGLE: StringName = &"rectangle"
const DOCK_WIDTH: float = 376.0
const COLLAPSED_HEIGHT: float = 58.0
const EXPANDED_HEIGHT: float = 420.0
const SCREEN_MARGIN: float = 16.0
const TOOL_CONTENT_MARGIN_LEFT: int = 2
const TOOL_CONTENT_MARGIN_TOP: int = 2
const TOOL_CONTENT_MARGIN_RIGHT: int = 8
const TOOL_CONTENT_MARGIN_BOTTOM: int = 2

var _select_button: Button
var _brush_button: Button
var _pc_button: Button
var _wall_button: Button
var _door_button: Button
var _building_button: Button
var _wall_line_button: Button
var _wall_rectangle_button: Button
var _content_root: VBoxContainer
var _select_content: Control
var _brush_content: Control
var _pc_content: Control
var _wall_content: Control
var _door_content: Control
var _building_content: Control
var _inspector_label: Label
var _brush_label: Label
var _pc_label: Label
var _wall_label: Label
var _door_label: Label
var _building_label: Label
var _building_width_slider: HSlider
var _building_depth_slider: HSlider
var _building_min_room_slider: HSlider
var _building_room_count_slider: HSlider
var _building_seed_slider: HSlider
var _building_submit_button: Button
var _selected_node: Node
var _selected_data: Resource
var _selected_kind: StringName = &""
var _active_tool: StringName = TOOL_SELECT_INSPECT
var _expanded_tool: StringName = &""
var _wall_brush_mode: StringName = WALL_BRUSH_MODE_LINE
var _building_parameters: Dictionary = BspBuildingGeneratorScript.default_parameters()
var _panel_position: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_start_mouse_position: Vector2 = Vector2.ZERO
var _drag_start_panel_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_configure_position()
	_configure_style()
	_ensure_layout()
	_render_inspector()

	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	var mode_callable := Callable(self, "_on_editor_mode_changed")
	var selection_callable := Callable(self, "_on_editor_selection_changed")
	var building_seed_callable := Callable(self, "_on_editor_building_brush_seed_selected")
	if event_bus.has_signal(&"editor_mode_changed") and not event_bus.is_connected(&"editor_mode_changed", mode_callable):
		event_bus.connect(&"editor_mode_changed", mode_callable)
	if event_bus.has_signal(&"editor_selection_changed") and not event_bus.is_connected(&"editor_selection_changed", selection_callable):
		event_bus.connect(&"editor_selection_changed", selection_callable)
	if event_bus.has_signal(&"editor_building_brush_seed_selected") and not event_bus.is_connected(&"editor_building_brush_seed_selected", building_seed_callable):
		event_bus.connect(&"editor_building_brush_seed_selected", building_seed_callable)

func get_inspector_text() -> String:
	return _inspector_label.text if _inspector_label != null else ""

func get_active_tool() -> StringName:
	return _active_tool

func get_expanded_tool() -> StringName:
	return _expanded_tool

func get_wall_brush_mode() -> StringName:
	return _wall_brush_mode

func get_building_brush_parameters() -> Dictionary:
	return _building_parameters.duplicate()

func is_tool_panel_expanded() -> bool:
	return _expanded_tool != &""

func get_panel_position() -> Vector2:
	return _panel_position

func set_panel_position(next_position: Vector2) -> void:
	_panel_position = _clamped_panel_position(next_position)
	_apply_panel_frame()

func is_dragging() -> bool:
	return _is_dragging

func toggle_tool_panel(tool_id: StringName) -> void:
	if not _is_known_tool(tool_id):
		return

	if _active_tool == tool_id and _expanded_tool == tool_id:
		_expanded_tool = &""
	else:
		_set_active_tool(tool_id)
		if tool_id == TOOL_WALL_BRUSH:
			_set_wall_brush_mode(WALL_BRUSH_MODE_LINE, true, true)
		_expanded_tool = tool_id
	_update_tool_ui()

func set_wall_brush_mode(mode: StringName) -> void:
	_set_wall_brush_mode(mode, true)
	_update_tool_ui()

func collapse_tool_panel() -> void:
	_expanded_tool = &""
	_update_tool_ui()

func _configure_position() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	var viewport_size := get_viewport_rect().size
	_panel_position = Vector2(
		maxf(SCREEN_MARGIN, viewport_size.x - DOCK_WIDTH - SCREEN_MARGIN),
		SCREEN_MARGIN
	)
	_apply_panel_frame()

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.045, 0.047, 0.92)
	panel_style.border_color = Color(0.24, 0.27, 0.27, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", panel_style)

func _ensure_layout() -> void:
	if _inspector_label != null:
		return

	var layout := VBoxContainer.new()
	layout.name = "EditorToolDockLayout"
	layout.add_theme_constant_override("separation", 8)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(layout)

	var button_row := HBoxContainer.new()
	button_row.name = "ToolButtonRow"
	button_row.add_theme_constant_override("separation", 8)
	layout.add_child(button_row)

	_select_button = _new_tool_button("SelectInspectToolButton", "Select", TOOL_SELECT_INSPECT)
	button_row.add_child(_select_button)

	_brush_button = _new_tool_button("NpcBrushToolButton", "NPC", TOOL_NPC_BRUSH)
	button_row.add_child(_brush_button)

	_pc_button = _new_tool_button("PcBrushToolButton", "PC", TOOL_PC_BRUSH)
	button_row.add_child(_pc_button)

	_wall_button = _new_tool_button("WallBrushToolButton", "Wall", TOOL_WALL_BRUSH)
	button_row.add_child(_wall_button)

	_door_button = _new_tool_button("DoorBrushToolButton", "Door", TOOL_DOOR_BRUSH)
	button_row.add_child(_door_button)

	_building_button = _new_tool_button("BuildingBrushToolButton", "Bldg.", TOOL_BUILDING_BRUSH)
	button_row.add_child(_building_button)

	var separator := HSeparator.new()
	separator.name = "ToolInspectorSeparator"
	separator.visible = false
	layout.add_child(separator)

	_content_root = VBoxContainer.new()
	_content_root.name = "ToolContent"
	_content_root.visible = false
	_content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_content_root)

	_select_content = _build_select_content()
	_content_root.add_child(_select_content)

	_brush_content = _build_brush_content()
	_content_root.add_child(_brush_content)

	_pc_content = _build_pc_content()
	_content_root.add_child(_pc_content)

	_wall_content = _build_wall_content()
	_content_root.add_child(_wall_content)

	_door_content = _build_door_content()
	_content_root.add_child(_door_content)

	_building_content = _build_building_content()
	_content_root.add_child(_building_content)

	_update_tool_ui()

func _new_tool_button(button_name: String, label: String, tool_id: StringName) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_tool_button_pressed.bind(tool_id))
	button.gui_input.connect(_on_drag_gui_input)
	return button

func _build_select_content() -> Control:
	_inspector_label = Label.new()
	_inspector_label.name = "InspectorContent"
	_configure_tool_label(_inspector_label)
	return _new_tool_content("SelectInspectContent", "SelectInspectContentPadding", _inspector_label)

func _build_brush_content() -> Control:
	_brush_label = Label.new()
	_brush_label.name = "NpcBrushProperties"
	_configure_tool_label(_brush_label)
	_brush_label.text = "\n".join(PackedStringArray([
		"NPC Brush",
		"object_kind: non_player_character",
		"size: (0.50, 1.83, 0.50)",
		"color: (0.450, 0.450, 0.450, 1.000)",
	]))
	return _new_tool_content("NpcBrushContent", "NpcBrushContentPadding", _brush_label)

func _build_pc_content() -> Control:
	_pc_label = Label.new()
	_pc_label.name = "PcBrushProperties"
	_configure_tool_label(_pc_label)
	_pc_label.text = "\n".join(PackedStringArray([
		"PC Brush",
		"object_kind: player_character",
		"size: (0.50, 1.83, 0.50)",
		"color: (0.100, 0.250, 1.000, 1.000)",
	]))
	return _new_tool_content("PcBrushContent", "PcBrushContentPadding", _pc_label)

func _build_wall_content() -> Control:
	var layout := VBoxContainer.new()
	layout.name = "WallBrushProperties"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)

	var mode_row := HBoxContainer.new()
	mode_row.name = "WallBrushModeRow"
	mode_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_theme_constant_override("separation", 8)
	layout.add_child(mode_row)

	_wall_line_button = _new_wall_mode_button(
		"WallLineModeButton",
		"Line",
		WALL_BRUSH_MODE_LINE
	)
	mode_row.add_child(_wall_line_button)

	_wall_rectangle_button = _new_wall_mode_button(
		"WallRectangleModeButton",
		"Rectangle",
		WALL_BRUSH_MODE_RECTANGLE
	)
	mode_row.add_child(_wall_rectangle_button)

	_wall_label = Label.new()
	_wall_label.name = "WallBrushDetails"
	_configure_tool_label(_wall_label)
	_wall_label.text = "\n".join(PackedStringArray([
		"Wall Brush",
		"default_mode: line",
		"modes: line, rectangle",
		"height: 2.20",
		"thickness: 0.18",
		"color: (0.350, 0.340, 0.320, 1.000)",
	]))
	layout.add_child(_wall_label)

	return _new_tool_content("WallBrushContent", "WallBrushContentPadding", layout)

func _build_door_content() -> Control:
	_door_label = Label.new()
	_door_label.name = "DoorBrushProperties"
	_configure_tool_label(_door_label)
	_door_label.text = "\n".join(PackedStringArray([
		"Door Brush",
		"socket_width: 1.00",
		"edge_clearance: 0.50",
		"snap_distance: 0.75",
		"marker_color: (0.820, 0.900, 0.840, 1.000)",
	]))
	return _new_tool_content("DoorBrushContent", "DoorBrushContentPadding", _door_label)

func _build_building_content() -> Control:
	var layout := VBoxContainer.new()
	layout.name = "BuildingBrushProperties"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)

	_building_width_slider = _new_building_slider("BuildingWidthSlider", 4.0, 24.0, 0.5, "width_m")
	layout.add_child(_new_building_slider_row("width_m", _building_width_slider))

	_building_depth_slider = _new_building_slider("BuildingDepthSlider", 4.0, 24.0, 0.5, "depth_m")
	layout.add_child(_new_building_slider_row("depth_m", _building_depth_slider))

	_building_min_room_slider = _new_building_slider("BuildingMinRoomSlider", 1.0, 6.0, 0.25, "min_room_size_m")
	layout.add_child(_new_building_slider_row("min_room_m", _building_min_room_slider))

	_building_room_count_slider = _new_building_slider("BuildingRoomCountSlider", 1.0, 12.0, 1.0, "target_room_count")
	layout.add_child(_new_building_slider_row("rooms", _building_room_count_slider))

	_building_seed_slider = _new_building_slider("BuildingSeedSlider", 1.0, 9999.0, 1.0, "seed")
	layout.add_child(_new_building_slider_row("seed", _building_seed_slider))

	var action_row := HBoxContainer.new()
	action_row.name = "BuildingBrushActionRow"
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 8)
	layout.add_child(action_row)

	var seed_button := Button.new()
	seed_button.name = "BuildingNewSeedButton"
	seed_button.text = "New Seed"
	seed_button.custom_minimum_size = Vector2(0.0, 32.0)
	seed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_button.pressed.connect(_on_building_new_seed_pressed)
	seed_button.gui_input.connect(_on_drag_gui_input)
	action_row.add_child(seed_button)

	_building_submit_button = Button.new()
	_building_submit_button.name = "BuildingSubmitButton"
	_building_submit_button.text = "Submit"
	_building_submit_button.custom_minimum_size = Vector2(0.0, 32.0)
	_building_submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_submit_button.pressed.connect(_on_building_submit_pressed)
	_building_submit_button.gui_input.connect(_on_drag_gui_input)
	action_row.add_child(_building_submit_button)

	_building_label = Label.new()
	_building_label.name = "BuildingBrushDetails"
	_configure_tool_label(_building_label)
	layout.add_child(_building_label)

	_apply_building_parameters_to_sliders(false)
	_update_building_summary()
	return _new_tool_content("BuildingBrushContent", "BuildingBrushContentPadding", layout)

func _new_building_slider(
	slider_name: String,
	min_value: float,
	max_value: float,
	step: float,
	parameter_name: String
) -> HSlider:
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_building_slider_changed.bind(parameter_name))
	slider.gui_input.connect(_on_drag_gui_input)
	return slider

func _new_building_slider_row(label_text: String, slider: HSlider) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % slider.name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.name = "%sLabel" % slider.name
	label.text = label_text
	label.custom_minimum_size = Vector2(92.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(slider)
	return row

func _new_wall_mode_button(button_name: String, label: String, mode: StringName) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, 32.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_wall_mode_button_pressed.bind(mode))
	button.gui_input.connect(_on_drag_gui_input)
	return button

func _new_tool_content(content_name: String, padding_name: String, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = content_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var content_padding := MarginContainer.new()
	content_padding.name = padding_name
	content_padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_padding.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_padding.add_theme_constant_override("margin_left", TOOL_CONTENT_MARGIN_LEFT)
	content_padding.add_theme_constant_override("margin_top", TOOL_CONTENT_MARGIN_TOP)
	content_padding.add_theme_constant_override("margin_right", TOOL_CONTENT_MARGIN_RIGHT)
	content_padding.add_theme_constant_override("margin_bottom", TOOL_CONTENT_MARGIN_BOTTOM)
	scroll.add_child(content_padding)
	content_padding.add_child(content)
	return scroll

func _configure_tool_label(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _gui_input(event: InputEvent) -> void:
	_handle_drag_input(event)

func _input(event: InputEvent) -> void:
	if _is_dragging:
		_handle_drag_input(event)

func _on_editor_mode_changed(mode: StringName) -> void:
	visible = mode == &"editor"
	if visible:
		_expanded_tool = &""
		_update_tool_ui()
	else:
		_is_dragging = false

func _on_editor_selection_changed(
	selected_node: Node,
	selected_data: Resource,
	selected_kind: StringName
) -> void:
	_selected_node = selected_node
	_selected_data = selected_data
	_selected_kind = selected_kind
	_render_inspector()

func _on_editor_building_brush_seed_selected(seed: int) -> void:
	_building_parameters["seed"] = clampi(seed, 1, 9999)
	_apply_building_parameters_to_sliders(false)
	_update_building_summary()

func _on_tool_button_pressed(tool_id: StringName) -> void:
	toggle_tool_panel(tool_id)

func _on_wall_mode_button_pressed(mode: StringName) -> void:
	set_wall_brush_mode(mode)

func _on_building_slider_changed(value: float, parameter_name: String) -> void:
	if parameter_name == "target_room_count" or parameter_name == "seed":
		_building_parameters[parameter_name] = int(roundf(value))
	else:
		_building_parameters[parameter_name] = value
	_update_building_summary()
	_emit_building_parameters_changed()

func _on_building_new_seed_pressed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_building_parameters["seed"] = rng.randi_range(1, 9999)
	_apply_building_parameters_to_sliders(true)
	_update_building_summary()

func _on_building_submit_pressed() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null and event_bus.has_signal(&"editor_building_brush_commit_requested"):
		event_bus.emit_signal(&"editor_building_brush_commit_requested")

func _on_drag_gui_input(event: InputEvent) -> void:
	_handle_drag_input(event)

func _handle_drag_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mouse_event.pressed:
			_is_dragging = true
			_drag_start_mouse_position = _event_screen_position(mouse_event)
			_drag_start_panel_position = _panel_position
		elif _is_dragging:
			_is_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event := event as InputEventMouseMotion
		var drag_delta := _event_screen_position(motion_event) - _drag_start_mouse_position
		set_panel_position(_drag_start_panel_position + drag_delta)
		accept_event()

func _event_screen_position(event: InputEventMouse) -> Vector2:
	if event.global_position != Vector2.ZERO:
		return event.global_position
	if event.position != Vector2.ZERO:
		return global_position + event.position

	var viewport := get_viewport()
	return viewport.get_mouse_position() if viewport != null else global_position

func _set_active_tool(tool_id: StringName) -> void:
	if not _is_known_tool(tool_id):
		return

	if _active_tool == tool_id:
		return

	_active_tool = tool_id
	var event_bus := _get_event_bus()
	if event_bus != null and event_bus.has_signal(&"editor_tool_changed"):
		event_bus.emit_signal(&"editor_tool_changed", _active_tool)

func _set_wall_brush_mode(mode: StringName, should_emit: bool = true, force_emit: bool = false) -> void:
	if not _is_known_wall_brush_mode(mode):
		return

	if _wall_brush_mode == mode and not force_emit:
		return

	_wall_brush_mode = mode
	if should_emit:
		var event_bus := _get_event_bus()
		if event_bus != null and event_bus.has_signal(&"editor_wall_brush_mode_changed"):
			event_bus.emit_signal(&"editor_wall_brush_mode_changed", _wall_brush_mode)

func _update_tool_ui() -> void:
	if _select_button != null:
		_select_button.button_pressed = _active_tool == TOOL_SELECT_INSPECT
	if _brush_button != null:
		_brush_button.button_pressed = _active_tool == TOOL_NPC_BRUSH
	if _pc_button != null:
		_pc_button.button_pressed = _active_tool == TOOL_PC_BRUSH
	if _wall_button != null:
		_wall_button.button_pressed = _active_tool == TOOL_WALL_BRUSH
	if _door_button != null:
		_door_button.button_pressed = _active_tool == TOOL_DOOR_BRUSH
	if _building_button != null:
		_building_button.button_pressed = _active_tool == TOOL_BUILDING_BRUSH
	if _wall_line_button != null:
		_wall_line_button.button_pressed = _wall_brush_mode == WALL_BRUSH_MODE_LINE
	if _wall_rectangle_button != null:
		_wall_rectangle_button.button_pressed = _wall_brush_mode == WALL_BRUSH_MODE_RECTANGLE

	if _content_root != null:
		_content_root.visible = _expanded_tool != &""
	if _select_content != null:
		_select_content.visible = _expanded_tool == TOOL_SELECT_INSPECT
	if _brush_content != null:
		_brush_content.visible = _expanded_tool == TOOL_NPC_BRUSH
	if _pc_content != null:
		_pc_content.visible = _expanded_tool == TOOL_PC_BRUSH
	if _wall_content != null:
		_wall_content.visible = _expanded_tool == TOOL_WALL_BRUSH
	if _door_content != null:
		_door_content.visible = _expanded_tool == TOOL_DOOR_BRUSH
	if _building_content != null:
		_building_content.visible = _expanded_tool == TOOL_BUILDING_BRUSH

	var separator := get_node_or_null("EditorToolDockLayout/ToolInspectorSeparator") as HSeparator
	if separator != null:
		separator.visible = _expanded_tool != &""

	_apply_panel_frame()

func _is_known_tool(tool_id: StringName) -> bool:
	return (
		tool_id == TOOL_SELECT_INSPECT
		or tool_id == TOOL_NPC_BRUSH
		or tool_id == TOOL_PC_BRUSH
		or tool_id == TOOL_WALL_BRUSH
		or tool_id == TOOL_DOOR_BRUSH
		or tool_id == TOOL_BUILDING_BRUSH
	)

func _apply_building_parameters_to_sliders(should_emit: bool) -> void:
	var slider_values := {
		"width_m": _building_width_slider,
		"depth_m": _building_depth_slider,
		"min_room_size_m": _building_min_room_slider,
		"target_room_count": _building_room_count_slider,
		"seed": _building_seed_slider,
	}
	for parameter_name in slider_values.keys():
		var slider := slider_values[parameter_name] as HSlider
		if slider == null:
			continue

		slider.set_value_no_signal(float(_building_parameters.get(parameter_name, slider.value)))

	if should_emit:
		_emit_building_parameters_changed()

func _update_building_summary() -> void:
	if _building_label == null:
		return

	_building_label.text = "\n".join(PackedStringArray([
		"Building Brush",
		"origin: center point",
		"size: %.1fm x %.1fm" % [
			float(_building_parameters.get("width_m", BspBuildingGeneratorScript.DEFAULT_WIDTH_M)),
			float(_building_parameters.get("depth_m", BspBuildingGeneratorScript.DEFAULT_DEPTH_M)),
		],
		"rooms: %d" % int(_building_parameters.get("target_room_count", BspBuildingGeneratorScript.DEFAULT_TARGET_ROOM_COUNT)),
		"min_room_m: %.2f" % float(_building_parameters.get("min_room_size_m", BspBuildingGeneratorScript.DEFAULT_MIN_ROOM_SIZE_M)),
		"seed: %d" % int(_building_parameters.get("seed", BspBuildingGeneratorScript.DEFAULT_SEED)),
	]))

func _emit_building_parameters_changed() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null and event_bus.has_signal(&"editor_building_brush_parameters_changed"):
		event_bus.emit_signal(
			&"editor_building_brush_parameters_changed",
			_building_parameters.duplicate()
		)

func _is_known_wall_brush_mode(mode: StringName) -> bool:
	return mode == WALL_BRUSH_MODE_LINE or mode == WALL_BRUSH_MODE_RECTANGLE

func _apply_panel_frame() -> void:
	var panel_size := _current_panel_size()
	_panel_position = _clamped_panel_position(_panel_position)
	custom_minimum_size = panel_size
	size = panel_size
	offset_left = _panel_position.x
	offset_top = _panel_position.y
	offset_right = _panel_position.x + panel_size.x
	offset_bottom = _panel_position.y + panel_size.y

func _current_panel_size() -> Vector2:
	var viewport_size := get_viewport_rect().size
	var width := minf(DOCK_WIDTH, maxf(180.0, viewport_size.x - (SCREEN_MARGIN * 2.0)))
	var target_height := EXPANDED_HEIGHT if _expanded_tool != &"" else COLLAPSED_HEIGHT
	var height := minf(target_height, maxf(COLLAPSED_HEIGHT, viewport_size.y - (SCREEN_MARGIN * 2.0)))
	return Vector2(width, height)

func _clamped_panel_position(next_position: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var panel_size := _current_panel_size()
	var max_position := Vector2(
		maxf(0.0, viewport_size.x - panel_size.x),
		maxf(0.0, viewport_size.y - panel_size.y)
	)
	return Vector2(
		clampf(next_position.x, 0.0, max_position.x),
		clampf(next_position.y, 0.0, max_position.y)
	)

func _render_inspector() -> void:
	if _inspector_label == null:
		return

	if _selected_data == null:
		_inspector_label.text = "No selection"
		return

	var lines: Array[String] = []
	lines.append("kind: %s" % String(_selected_kind))
	lines.append("id/name: %s" % _selected_id_or_name())
	lines.append("resource_class: %s" % _resource_class_name(_selected_data))

	if _selected_data is GroundDataScript:
		var ground := _selected_data as GroundDataScript
		lines.append("position: %s" % _format_vector3(ground.position))
		lines.append("size: %s" % _format_vector3(ground.size_m))
		lines.append("color: %s" % _format_color(ground.color))
	elif _selected_data is WallDataScript:
		var wall := _selected_data as WallDataScript
		if _selected_node is Node3D:
			lines.append("position: %s" % _format_vector3((_selected_node as Node3D).global_position))
		lines.append("line: %s -> %s" % [
			_format_vector3(wall.start_position),
			_format_vector3(wall.end_position),
		])
		lines.append("height: %.2f" % wall.height_m)
		lines.append("thickness: %.2f" % wall.thickness_m)
		lines.append("color: %s" % _format_color(wall.color))
	elif _selected_data is DoorSocketDataScript:
		var socket := _selected_data as DoorSocketDataScript
		lines.append("position: %s" % _format_vector3(socket.position))
		lines.append("width: %.2f" % socket.width_m)
		lines.append("rotation_y: %.3f" % socket.rotation_y)
		lines.append("color: %s" % _format_color(socket.color))
	elif _selected_data is WorldObjectDataScript:
		var world_object := _selected_data as WorldObjectDataScript
		lines.append("object_kind: %s" % String(world_object.object_kind))
		lines.append("position: %s" % _format_vector3(world_object.position))
		lines.append("size: %s" % _format_vector3(world_object.size_m))
		lines.append("color: %s" % _format_color(world_object.color))

	_inspector_label.text = "\n".join(PackedStringArray(lines))

func _selected_id_or_name() -> String:
	if _selected_data is GroundDataScript:
		var ground := _selected_data as GroundDataScript
		if ground.ground_id != &"":
			return String(ground.ground_id)
	if _selected_data is WorldObjectDataScript:
		var world_object := _selected_data as WorldObjectDataScript
		if world_object.object_id != &"":
			return String(world_object.object_id)
	if _selected_data is DoorSocketDataScript:
		var socket := _selected_data as DoorSocketDataScript
		if socket.socket_id != &"":
			return String(socket.socket_id)
	if _selected_node != null:
		return _selected_node.name

	return ""

func _resource_class_name(resource: Resource) -> String:
	var script := resource.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return script.resource_path.get_file().get_basename()

	return resource.get_class()

func _format_vector3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]

func _format_color(value: Color) -> String:
	return "(%.3f, %.3f, %.3f, %.3f)" % [value.r, value.g, value.b, value.a]

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
