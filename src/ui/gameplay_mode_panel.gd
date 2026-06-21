class_name GameplayModePanel
extends PanelContainer

const RUNTIME_MODE_GAME: StringName = &"game"
const CONTROL_MODE_REAL_TIME: StringName = &"real_time"
const CONTROL_MODE_TURN_BASED: StringName = &"turn_based"

var _real_time_button: Button
var _turn_based_button: Button
var _selected_mode: StringName = CONTROL_MODE_REAL_TIME

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_configure_position()
	_configure_style()
	_ensure_layout()
	_connect_event_bus()
	_update_buttons()

func get_selected_mode() -> StringName:
	return _selected_mode

func _configure_position() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -132.0
	offset_top = -58.0
	offset_right = -16.0
	offset_bottom = -16.0

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.045, 0.047, 0.9)
	panel_style.border_color = Color(0.24, 0.27, 0.27, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 5.0
	panel_style.content_margin_top = 5.0
	panel_style.content_margin_right = 5.0
	panel_style.content_margin_bottom = 5.0
	add_theme_stylebox_override("panel", panel_style)

func _ensure_layout() -> void:
	var row := HBoxContainer.new()
	row.name = "ModeButtons"
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	var group := ButtonGroup.new()
	_real_time_button = _new_mode_button("RealTimeButton", "RT", group)
	_real_time_button.pressed.connect(_request_mode.bind(CONTROL_MODE_REAL_TIME))
	row.add_child(_real_time_button)

	_turn_based_button = _new_mode_button("TurnBasedButton", "TB", group)
	_turn_based_button.pressed.connect(_request_mode.bind(CONTROL_MODE_TURN_BASED))
	row.add_child(_turn_based_button)

func _new_mode_button(button_name: String, label: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(50.0, 30.0)
	return button

func _connect_event_bus() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return
	var runtime_callable := Callable(self, "_on_runtime_mode_changed")
	var gameplay_callable := Callable(self, "_on_gameplay_control_mode_changed")
	if not event_bus.is_connected(&"editor_mode_changed", runtime_callable):
		event_bus.connect(&"editor_mode_changed", runtime_callable)
	if not event_bus.is_connected(&"gameplay_control_mode_changed", gameplay_callable):
		event_bus.connect(&"gameplay_control_mode_changed", gameplay_callable)

func _request_mode(mode: StringName) -> void:
	var event_bus := _get_event_bus()
	if event_bus != null and event_bus.has_signal(&"gameplay_control_mode_requested"):
		event_bus.emit_signal(&"gameplay_control_mode_requested", mode)

func _on_runtime_mode_changed(mode: StringName) -> void:
	visible = mode == RUNTIME_MODE_GAME

func _on_gameplay_control_mode_changed(mode: StringName) -> void:
	if mode == CONTROL_MODE_REAL_TIME or mode == CONTROL_MODE_TURN_BASED:
		_selected_mode = mode
		_update_buttons()

func _update_buttons() -> void:
	if _real_time_button != null:
		_real_time_button.set_pressed_no_signal(_selected_mode == CONTROL_MODE_REAL_TIME)
	if _turn_based_button != null:
		_turn_based_button.set_pressed_no_signal(_selected_mode == CONTROL_MODE_TURN_BASED)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("EventBus")
