class_name DebugLogPanel
extends PanelContainer

const MAX_LINES: int = 8

var _content_label: Label
var _lines: Array[String] = []

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_layout()
	_configure_style()
	_connect_events()
	_render()

func _on_interaction_targeting_started(source: Node, action_id: StringName) -> void:
	_append("targeting_started action=%s source=%s" % [action_id, _node_name(source)])

func _on_interaction_targeting_cancelled(source: Node, action_id: StringName) -> void:
	_append("targeting_cancelled action=%s source=%s" % [action_id, _node_name(source)])

func _on_interaction_targeting_failed(
	source: Node,
	target: Node,
	action_id: StringName,
	reason: StringName,
	details: Dictionary
) -> void:
	_append(
		"targeting_failed action=%s reason=%s source=%s target=%s iter=%s"
		% [
			action_id,
			reason,
			_node_name(source),
			_node_name(target),
			str(details.get("navigation_map_iteration", 0)),
		]
	)

func _on_move_requested(actor: Node, _actor_data: Resource, destination_data: Resource) -> void:
	var position_text := ""
	if destination_data != null:
		var position: Variant = destination_data.get("position")
		if position is Vector3:
			position_text = " target=%s" % [position]
	_append("move_requested actor=%s%s" % [_node_name(actor), position_text])

func _on_movement_started(actor: Node, path: PackedVector3Array) -> void:
	_append("movement_started actor=%s points=%d" % [_node_name(actor), path.size()])

func _on_movement_completed(actor: Node, destination_data: Resource) -> void:
	var position_text := ""
	if destination_data != null:
		var position: Variant = destination_data.get("position")
		if position is Vector3:
			position_text = " target=%s" % [position]
	_append("movement_completed actor=%s%s" % [_node_name(actor), position_text])

func _on_movement_failed(actor: Node, _destination_data: Resource, reason: StringName) -> void:
	_append("movement_failed actor=%s reason=%s" % [_node_name(actor), reason])

func _configure_layout() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16.0
	offset_right = 496.0
	offset_top = 16.0
	offset_bottom = 164.0

	_content_label = get_node_or_null("Content") as Label
	if _content_label != null:
		return

	_content_label = Label.new()
	_content_label.name = "Content"
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_content_label)

func _connect_events() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	_connect_if_needed(event_bus, &"interaction_targeting_started", Callable(self, "_on_interaction_targeting_started"))
	_connect_if_needed(event_bus, &"interaction_targeting_cancelled", Callable(self, "_on_interaction_targeting_cancelled"))
	_connect_if_needed(event_bus, &"interaction_targeting_failed", Callable(self, "_on_interaction_targeting_failed"))
	_connect_if_needed(event_bus, &"move_requested", Callable(self, "_on_move_requested"))
	_connect_if_needed(event_bus, &"movement_started", Callable(self, "_on_movement_started"))
	_connect_if_needed(event_bus, &"movement_completed", Callable(self, "_on_movement_completed"))
	_connect_if_needed(event_bus, &"movement_failed", Callable(self, "_on_movement_failed"))

func _connect_if_needed(event_bus: Node, signal_name: StringName, callable: Callable) -> void:
	if event_bus.has_signal(signal_name) and not event_bus.is_connected(signal_name, callable):
		event_bus.connect(signal_name, callable)

func _append(line: String) -> void:
	_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_render()

func _render() -> void:
	if _content_label == null:
		return

	if _lines.is_empty():
		_content_label.text = "Debug log ready"
		return

	_content_label.text = "\n".join(PackedStringArray(_lines))

func _node_name(node: Node) -> String:
	return "<none>" if node == null else node.name

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.04, 0.045, 0.86)
	panel_style.border_color = Color(0.2, 0.24, 0.27, 1.0)
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
