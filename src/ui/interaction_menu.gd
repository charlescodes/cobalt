class_name InteractionMenu
extends PanelContainer

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")

var _target: Node
var _action_list: VBoxContainer
var _has_pointer_capture: bool = false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	_configure_style()
	_ensure_layout()
	var event_bus := _get_event_bus()
	if event_bus != null:
		var menu_callable := Callable(self, "_on_interaction_menu_requested")
		var hover_callable := Callable(self, "_on_hover_target_changed")
		var cancel_callable := Callable(self, "_on_interaction_ui_cancel_requested")
		if not event_bus.is_connected(&"interaction_menu_requested", menu_callable):
			event_bus.connect(&"interaction_menu_requested", menu_callable)
		if not event_bus.is_connected(&"hover_target_changed", hover_callable):
			event_bus.connect(&"hover_target_changed", hover_callable)
		if not event_bus.is_connected(&"interaction_ui_cancel_requested", cancel_callable):
			event_bus.connect(&"interaction_ui_cancel_requested", cancel_callable)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed:
			_close_menu()

func _exit_tree() -> void:
	_set_pointer_capture(false)

func _on_interaction_menu_requested(target: Node, screen_position: Vector2) -> void:
	_target = target
	_render_actions(InteractionActionResolverScript.get_actions(target))
	position = screen_position
	show()
	_set_pointer_capture(true)
	call_deferred("_fit_to_content_and_viewport")

func _on_hover_target_changed(target: Node) -> void:
	if visible and target != _target:
		_close_menu()

func _on_interaction_ui_cancel_requested() -> void:
	if visible:
		_close_menu()

func _on_action_pressed(action_id: StringName) -> void:
	var selected_target := _target
	_close_menu()
	if selected_target == null:
		return

	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"interaction_action_requested", selected_target, action_id)

func _ensure_layout() -> void:
	_action_list = get_node_or_null("ActionList") as VBoxContainer
	if _action_list != null:
		return

	_action_list = VBoxContainer.new()
	_action_list.name = "ActionList"
	_action_list.add_theme_constant_override("separation", 2)
	add_child(_action_list)

func _render_actions(actions: Array[Dictionary]) -> void:
	for child in _action_list.get_children():
		child.free()

	if actions.is_empty():
		var empty_button := Button.new()
		empty_button.text = "No actions"
		empty_button.disabled = true
		empty_button.custom_minimum_size = Vector2(132.0, 30.0)
		_action_list.add_child(empty_button)
		return

	for action in actions:
		var action_id: StringName = action.get("id", &"")
		var button := Button.new()
		button.text = str(action.get("label", action_id))
		button.custom_minimum_size = Vector2(132.0, 30.0)
		button.pressed.connect(_on_action_pressed.bind(action_id))
		_action_list.add_child(button)

func _fit_to_content_and_viewport() -> void:
	size = get_combined_minimum_size()
	var viewport_size := get_viewport_rect().size
	position.x = clampf(position.x, 0.0, maxf(0.0, viewport_size.x - size.x))
	position.y = clampf(position.y, 0.0, maxf(0.0, viewport_size.y - size.y))

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.06, 0.065, 0.94)
	panel_style.border_color = Color(0.25, 0.28, 0.29, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 6.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 6.0
	panel_style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", panel_style)

func _close_menu() -> void:
	hide()
	_target = null
	_set_pointer_capture(false)

func _set_pointer_capture(is_captured: bool) -> void:
	if _has_pointer_capture == is_captured:
		return

	_has_pointer_capture = is_captured
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"interaction_pointer_capture_changed", is_captured)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
