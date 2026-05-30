class_name EditorPanel
extends PanelContainer

const GroundDataScript := preload("res://src/environment/ground_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

var _tool_button: Button
var _inspector_label: Label
var _selected_node: Node
var _selected_data: Resource
var _selected_kind: StringName = &""

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
	if event_bus.has_signal(&"editor_mode_changed") and not event_bus.is_connected(&"editor_mode_changed", mode_callable):
		event_bus.connect(&"editor_mode_changed", mode_callable)
	if event_bus.has_signal(&"editor_selection_changed") and not event_bus.is_connected(&"editor_selection_changed", selection_callable):
		event_bus.connect(&"editor_selection_changed", selection_callable)

func get_inspector_text() -> String:
	return _inspector_label.text if _inspector_label != null else ""

func _configure_position() -> void:
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -304.0
	offset_top = 16.0
	offset_right = -16.0
	offset_bottom = -16.0

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
	layout.name = "EditorPanelLayout"
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)

	_tool_button = Button.new()
	_tool_button.name = "SelectInspectToolButton"
	_tool_button.text = "Select/Inspect"
	_tool_button.toggle_mode = true
	_tool_button.button_pressed = true
	_tool_button.custom_minimum_size = Vector2(256.0, 34.0)
	layout.add_child(_tool_button)

	var separator := HSeparator.new()
	separator.name = "ToolInspectorSeparator"
	layout.add_child(separator)

	_inspector_label = Label.new()
	_inspector_label.name = "InspectorContent"
	_inspector_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	layout.add_child(_inspector_label)

func _on_editor_mode_changed(mode: StringName) -> void:
	visible = mode == &"editor"

func _on_editor_selection_changed(
	selected_node: Node,
	selected_data: Resource,
	selected_kind: StringName
) -> void:
	_selected_node = selected_node
	_selected_data = selected_data
	_selected_kind = selected_kind
	_render_inspector()

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
