class_name ObjectInspectorPanel
extends "res://src/ui/floating_panel.gd"

var _target: Node
var _summary_label: Label
var _rows: VBoxContainer
var _rendered_values: Dictionary = {}

func _init() -> void:
	title = "Inspector"
	default_position = Vector2(520.0, 16.0)
	default_size = Vector2(360.0, 420.0)
	min_panel_size = Vector2(280.0, 180.0)
	start_visible = false
	allow_close = true
	allow_collapse = true
	allow_resize = true

func inspect_target(target: Node, screen_position: Vector2 = Vector2(-1.0, -1.0)) -> void:
	_target = target
	if screen_position.x >= 0.0 and screen_position.y >= 0.0 and not visible:
		position = screen_position + Vector2(14.0, 14.0)
	_render_target()
	show()
	call_deferred("fit_to_viewport")

func get_inspected_target() -> Node:
	return _target

func get_rendered_value(key: String) -> String:
	return str(_rendered_values.get(key, ""))

func _build_panel_content(content: VBoxContainer) -> void:
	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary_label)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 3)
	content.add_child(_rows)
	_render_target()

func _on_floating_panel_ready() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	var inspector_callable := Callable(self, "_on_interaction_inspector_requested")
	if event_bus.has_signal(&"interaction_inspector_requested") and not event_bus.is_connected(
		&"interaction_inspector_requested",
		inspector_callable
	):
		event_bus.connect(&"interaction_inspector_requested", inspector_callable)

func _on_interaction_inspector_requested(target: Node, screen_position: Vector2) -> void:
	inspect_target(target, screen_position)

func _render_target() -> void:
	if _summary_label == null or _rows == null:
		return

	for child in _rows.get_children():
		child.free()
	_rendered_values.clear()

	if _target == null:
		_summary_label.text = "No selected target"
		title = "Inspector"
		return

	title = "Inspector: %s" % _target.name
	_summary_label.text = "%s\n%s" % [_target.name, _target.get_path()]
	_add_section("Target")
	_add_row("name", _target.name)
	_add_row("class", _target.get_class())
	_add_row("script", _script_name(_target))
	_add_row("parent", _node_name(_target.get_parent()))
	_add_target_value("target_domain")
	_add_target_value("interaction_enabled")
	_add_target_value("input_ray_pickable")

	var data := _target_data(_target)
	if data != null:
		_add_section("Data")
		_add_row("data_script", _script_name(data))
		_add_resource_rows(data)

func _add_target_value(property_name: String) -> void:
	var value: Variant
	if property_name == "target_domain" and _target.has_method("get_target_domain"):
		value = _target.call("get_target_domain")
	elif property_name == "interaction_enabled" and _target.has_method("is_interaction_enabled"):
		value = _target.call("is_interaction_enabled")
	else:
		value = _target.get(property_name)
	if value != null:
		_add_row(property_name, _format_value(value))

func _add_resource_rows(resource: Resource) -> void:
	for property in resource.get_property_list():
		var property_name := str(property.get("name", ""))
		if property_name.is_empty() or property_name.begins_with("resource_"):
			continue
		if property_name == "script":
			continue
		var usage := int(property.get("usage", 0))
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		_add_row(property_name, _format_value(resource.get(property_name)))

func _add_section(section_title: String) -> void:
	var label := Label.new()
	label.text = section_title.to_upper()
	label.add_theme_color_override("font_color", Color(0.62, 0.74, 0.78, 1.0))
	_rows.add_child(label)

func _add_row(key: String, value: Variant) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_rows.add_child(row)

	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(122.0, 0.0)
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(key_label)

	var value_label := Label.new()
	var value_text := str(value)
	value_label.text = value_text
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)
	_rendered_values[key] = value_text

func _target_data(target: Node) -> Resource:
	if target == null:
		return null
	if target.has_method("get_target_data"):
		return target.call("get_target_data") as Resource
	return target.get("target_data") as Resource

func _format_value(value: Variant) -> String:
	if value is Vector3:
		var vector := value as Vector3
		return "(%.2f, %.2f, %.2f)" % [vector.x, vector.y, vector.z]
	if value is Vector2:
		var vector2 := value as Vector2
		return "(%.2f, %.2f)" % [vector2.x, vector2.y]
	if value is Color:
		return "#%s" % (value as Color).to_html(true)
	if value is Node:
		return _node_name(value as Node)
	if value is Resource:
		return _script_name(value as Resource)
	if value is Array:
		return "Array[%d]" % (value as Array).size()
	if value is Dictionary:
		return "Dictionary[%d]" % (value as Dictionary).size()
	return str(value)

func _node_name(node: Node) -> String:
	return "<none>" if node == null else String(node.name)

func _script_name(object: Object) -> String:
	if object == null:
		return "<none>"
	var script := object.get_script() as Script
	if script == null:
		return object.get_class()
	var path := script.resource_path
	return path.get_file() if not path.is_empty() else object.get_class()

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
