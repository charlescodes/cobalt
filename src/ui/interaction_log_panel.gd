class_name InteractionLogPanel
extends PanelContainer

var _content_label: Label
var _latest_output: Dictionary = {}

func _ready() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_layout()
	_configure_style()
	_render_output()
	var event_bus := _get_event_bus()
	var examined_callable := Callable(self, "_on_examined_output")
	if event_bus != null and not event_bus.is_connected(&"examined_output", examined_callable):
		event_bus.connect(&"examined_output", examined_callable)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_interaction_log"):
		visible = not visible
		get_viewport().set_input_as_handled()

func _on_examined_output(_target_domain: StringName, _target_data: Resource, output: Dictionary) -> void:
	_latest_output = output
	_render_output()

func _configure_layout() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16.0
	offset_right = 336.0
	offset_top = -104.0
	offset_bottom = -16.0

	_content_label = get_node_or_null("Content") as Label
	if _content_label != null:
		return

	_content_label = Label.new()
	_content_label.name = "Content"
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_content_label)

func _render_output() -> void:
	if _content_label == null:
		return

	if _latest_output.is_empty():
		_content_label.text = "No examined target"
		return

	var lines: Array[String] = []
	_append_output_line(lines, "domain")
	_append_output_line(lines, "object_kind")
	_append_output_line(lines, "object_id")
	_content_label.text = "\n".join(PackedStringArray(lines))

func _append_output_line(lines: Array[String], key: String) -> void:
	if not _latest_output.has(key):
		return

	lines.append("%s: %s" % [key, str(_latest_output[key])])

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.045, 0.045, 0.86)
	panel_style.border_color = Color(0.22, 0.25, 0.24, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", panel_style)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
