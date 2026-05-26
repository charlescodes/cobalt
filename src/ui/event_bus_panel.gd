class_name EventBusPanel
extends "res://src/ui/floating_panel.gd"

const FALLBACK_SIGNAL_NAMES: Array[StringName] = [
	&"hover_target_changed",
	&"interaction_menu_requested",
	&"interaction_inspector_requested",
	&"interaction_action_requested",
	&"interaction_pointer_capture_changed",
	&"interaction_ui_cancel_requested",
	&"interaction_targeting_started",
	&"interaction_targeting_cancelled",
	&"interaction_targeting_failed",
	&"move_requested",
	&"movement_started",
	&"movement_step_reached",
	&"movement_completed",
	&"movement_failed",
	&"examined_output",
]

@export var max_events: int = 80

var _event_bus: Node
var _summary_label: Label
var _event_label: Label
var _pause_button: Button
var _is_paused: bool = false
var _events: Array[String] = []
var _event_count: int = 0

func _init() -> void:
	title = "EventBus"
	default_position = Vector2(16.0, 176.0)
	default_size = Vector2(480.0, 260.0)
	min_panel_size = Vector2(320.0, 150.0)
	start_visible = true
	allow_close = false
	allow_collapse = true
	allow_resize = true

func _process(_delta: float) -> void:
	if _event_bus == null:
		_connect_event_bus()

func get_event_count() -> int:
	return _event_count

func get_latest_line() -> String:
	return "" if _events.is_empty() else _events[_events.size() - 1]

func clear_events() -> void:
	_events.clear()
	_event_count = 0
	_render_events()

func _build_panel_content(content: VBoxContainer) -> void:
	var toolbar := HBoxContainer.new()
	toolbar.name = "Toolbar"
	toolbar.add_theme_constant_override("separation", 8)
	content.add_child(toolbar)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_summary_label)

	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.toggle_mode = true
	_pause_button.toggled.connect(_on_pause_toggled)
	toolbar.add_child(_pause_button)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(clear_events)
	toolbar.add_child(clear_button)

	_event_label = Label.new()
	_event_label.name = "Events"
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	content.add_child(_event_label)
	_render_events()

func _on_floating_panel_ready() -> void:
	_connect_event_bus()

func _connect_event_bus() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null or event_bus == _event_bus:
		return

	_event_bus = event_bus
	for signal_name in _event_signal_names(_event_bus):
		if not _event_bus.has_signal(signal_name):
			continue
		var arity := _signal_arity(_event_bus, signal_name)
		var callable := _callable_for_arity(arity, signal_name)
		if callable.is_null():
			continue
		if not _event_bus.is_connected(signal_name, callable):
			_event_bus.connect(signal_name, callable)
	_render_events()

func _event_signal_names(event_bus: Node) -> Array[StringName]:
	if event_bus.has_method("get_event_signal_names"):
		var value: Variant = event_bus.call("get_event_signal_names")
		if value is Array:
			var names: Array[StringName] = []
			for item in value:
				names.append(StringName(str(item)))
			return names
	return FALLBACK_SIGNAL_NAMES

func _signal_arity(event_bus: Node, signal_name: StringName) -> int:
	for signal_info in event_bus.get_signal_list():
		if signal_info.get("name") != signal_name:
			continue
		var args: Array = signal_info.get("args", [])
		return args.size()
	return 0

func _callable_for_arity(arity: int, signal_name: StringName) -> Callable:
	match arity:
		0:
			return Callable(self, "_on_event_bus_signal_0").bind(signal_name)
		1:
			return Callable(self, "_on_event_bus_signal_1").bind(signal_name)
		2:
			return Callable(self, "_on_event_bus_signal_2").bind(signal_name)
		3:
			return Callable(self, "_on_event_bus_signal_3").bind(signal_name)
		4:
			return Callable(self, "_on_event_bus_signal_4").bind(signal_name)
		5:
			return Callable(self, "_on_event_bus_signal_5").bind(signal_name)
	return Callable()

func _on_event_bus_signal_0(signal_name: StringName) -> void:
	_record_event(signal_name, [])

func _on_event_bus_signal_1(arg0: Variant, signal_name: StringName) -> void:
	_record_event(signal_name, [arg0])

func _on_event_bus_signal_2(arg0: Variant, arg1: Variant, signal_name: StringName) -> void:
	_record_event(signal_name, [arg0, arg1])

func _on_event_bus_signal_3(
	arg0: Variant,
	arg1: Variant,
	arg2: Variant,
	signal_name: StringName
) -> void:
	_record_event(signal_name, [arg0, arg1, arg2])

func _on_event_bus_signal_4(
	arg0: Variant,
	arg1: Variant,
	arg2: Variant,
	arg3: Variant,
	signal_name: StringName
) -> void:
	_record_event(signal_name, [arg0, arg1, arg2, arg3])

func _on_event_bus_signal_5(
	arg0: Variant,
	arg1: Variant,
	arg2: Variant,
	arg3: Variant,
	arg4: Variant,
	signal_name: StringName
) -> void:
	_record_event(signal_name, [arg0, arg1, arg2, arg3, arg4])

func _record_event(signal_name: StringName, args: Array) -> void:
	if _is_paused:
		return

	_event_count += 1
	var timestamp := float(Time.get_ticks_msec()) / 1000.0
	var line := "%7.2f  %s%s" % [timestamp, signal_name, _format_args(args)]
	_events.append(line)
	while _events.size() > max_events:
		_events.pop_front()
	_render_events()

func _format_args(args: Array) -> String:
	if args.is_empty():
		return ""

	var values: Array[String] = []
	for arg in args:
		values.append(_format_value(arg))
	return "  " + ", ".join(PackedStringArray(values))

func _format_value(value: Variant) -> String:
	if value == null:
		return "<null>"
	if value is Node:
		var node := value as Node
		return "%s:%s" % [node.name, node.get_class()]
	if value is Resource:
		var resource := value as Resource
		var script_name := _script_name(resource)
		var object_id: Variant = resource.get("object_id")
		if object_id != null and object_id != &"":
			return "%s(%s)" % [script_name, object_id]
		return script_name
	if value is Vector3:
		var vector := value as Vector3
		return "(%.2f, %.2f, %.2f)" % [vector.x, vector.y, vector.z]
	if value is PackedVector3Array:
		return "PackedVector3Array[%d]" % (value as PackedVector3Array).size()
	if value is Dictionary:
		return "Dictionary[%d]" % (value as Dictionary).size()
	if value is Array:
		return "Array[%d]" % (value as Array).size()
	return str(value)

func _render_events() -> void:
	if _summary_label != null:
		var source_name: String = "<missing>" if _event_bus == null else String(_event_bus.name)
		_summary_label.text = "%s events=%d" % [source_name, _event_count]
	if _event_label == null:
		return

	if _events.is_empty():
		_event_label.text = "Waiting for events"
		return

	_event_label.text = "\n".join(PackedStringArray(_events))

func _on_pause_toggled(is_pressed: bool) -> void:
	_is_paused = is_pressed
	if _pause_button != null:
		_pause_button.text = "Resume" if _is_paused else "Pause"

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
