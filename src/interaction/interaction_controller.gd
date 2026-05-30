class_name InteractionController
extends Node

const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")

@export var camera_path: NodePath = ^"../CameraRig/PitchPivot/Camera3D"
@export_range(1.0, 500.0, 1.0) var max_ray_distance_m: float = 100.0
@export_flags_3d_physics var collision_mask: int = 1

var _camera: Camera3D
var _current_target: InteractionTargetScript
var _targeting_source: InteractionTargetScript
var _targeting_action_id: StringName = &""
var _is_interaction_pointer_captured: bool = false
var _is_gameplay_input_enabled: bool = true

func _ready() -> void:
	_camera = _resolve_camera()
	var event_bus := _get_event_bus()
	if event_bus == null:
		return
	var action_callable := Callable(self, "_handle_interaction_action_requested")
	var capture_callable := Callable(self, "_handle_interaction_pointer_capture_changed")
	var cancel_callable := Callable(self, "_handle_interaction_ui_cancel_requested")
	var mode_callable := Callable(self, "_handle_editor_mode_changed")
	if not event_bus.is_connected(&"interaction_action_requested", action_callable):
		event_bus.connect(&"interaction_action_requested", action_callable)
	if not event_bus.is_connected(&"interaction_pointer_capture_changed", capture_callable):
		event_bus.connect(&"interaction_pointer_capture_changed", capture_callable)
	if not event_bus.is_connected(&"interaction_ui_cancel_requested", cancel_callable):
		event_bus.connect(&"interaction_ui_cancel_requested", cancel_callable)
	if event_bus.has_signal(&"editor_mode_changed") and not event_bus.is_connected(&"editor_mode_changed", mode_callable):
		event_bus.connect(&"editor_mode_changed", mode_callable)

func _input(event: InputEvent) -> void:
	if not _is_gameplay_input_enabled:
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return

	if _is_interaction_pointer_captured:
		_request_interaction_ui_cancel()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
	elif is_targeting_interaction():
		cancel_targeting()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func _physics_process(_delta: float) -> void:
	if not _is_gameplay_input_enabled:
		clear_hover()
		return

	if _is_interaction_pointer_captured:
		return

	if not is_targeting_interaction() and _should_pause_hover():
		clear_hover()
		return

	if _camera == null:
		_camera = _resolve_camera()
		if _camera == null:
			clear_hover()
			return

	var required_domain := InteractionActionResolverScript.DOMAIN_MOVE_TARGET if is_targeting_interaction() else &""
	_set_hover_target(_raycast_interaction_target(required_domain))

func _unhandled_input(event: InputEvent) -> void:
	if not _is_gameplay_input_enabled:
		return

	if _is_interaction_pointer_captured:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if is_targeting_interaction():
				try_confirm_targeting_target(_current_target)
				get_viewport().set_input_as_handled()
				return

			_request_menu_for_current_target(mouse_event.position)

func clear_hover() -> void:
	_set_hover_target(null)

func is_interaction_pointer_captured() -> bool:
	return _is_interaction_pointer_captured

func is_gameplay_input_enabled() -> bool:
	return _is_gameplay_input_enabled

func is_targeting_interaction() -> bool:
	return _targeting_source != null

func start_targeting(source: Node, action_id: StringName) -> bool:
	if not _is_gameplay_input_enabled:
		return false

	var source_target := source as InteractionTargetScript
	if source_target == null or action_id != InteractionActionResolverScript.ACTION_MOVE:
		return false
	if not MoveTargetResolverScript.can_start_move(source_target):
		return false

	_targeting_source = source_target
	_targeting_action_id = action_id
	clear_hover()
	_emit_event(&"interaction_targeting_started", [_targeting_source, _targeting_action_id])
	return true

func cancel_targeting() -> void:
	if not is_targeting_interaction():
		return

	var source := _targeting_source
	var action_id := _targeting_action_id
	_targeting_source = null
	_targeting_action_id = &""
	_emit_event(&"interaction_targeting_cancelled", [source, action_id])

func try_confirm_targeting_target(target: Node) -> bool:
	if not _is_gameplay_input_enabled:
		return false
	if not is_targeting_interaction():
		return false
	if _targeting_action_id != InteractionActionResolverScript.ACTION_MOVE:
		return false
	var validation := MoveTargetResolverScript.validate_move(_targeting_source, target)
	if not bool(validation.get("ok", false)):
		_emit_event(&"interaction_targeting_failed", [
			_targeting_source,
			target,
			_targeting_action_id,
			validation.get("reason", &"invalid_request"),
			validation,
		])
		return false

	var actor := MoveTargetResolverScript.get_actor_node(_targeting_source)
	var actor_data := MoveTargetResolverScript.get_target_data(_targeting_source)
	var destination_data := MoveTargetResolverScript.get_target_data(target)
	_targeting_source = null
	_targeting_action_id = &""
	_emit_event(&"move_requested", [actor, actor_data, destination_data])
	return true

func _raycast_interaction_target(required_domain: StringName = &"") -> InteractionTargetScript:
	var mouse_position := get_viewport().get_mouse_position()
	return _raycast_interaction_target_at(mouse_position, required_domain)

func _raycast_interaction_target_at(
	mouse_position: Vector2,
	required_domain: StringName = &""
) -> InteractionTargetScript:
	var ray_origin := _camera.project_ray_origin(mouse_position)
	var ray_end := ray_origin + (_camera.project_ray_normal(mouse_position) * max_ray_distance_m)
	var excluded: Array[RID] = []

	for _attempt in range(32):
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, collision_mask)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.exclude = excluded

		var result := _camera.get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			return null

		var collider := result.get("collider") as Object
		var target := _find_interaction_target(collider)
		if target != null and (required_domain == &"" or target.target_domain == required_domain):
			_apply_raycast_position(target, result)
			return target

		var collision_object := collider as CollisionObject3D
		if collision_object == null:
			return null

		excluded.append(collision_object.get_rid())

	return null

func _apply_raycast_position(target: InteractionTargetScript, result: Dictionary) -> void:
	if target.target_domain != InteractionActionResolverScript.DOMAIN_MOVE_TARGET:
		return

	var data := target.target_data as MoveTargetDataScript
	var hit_position: Variant = result.get("position")
	if data == null or not (hit_position is Vector3):
		return

	data.position = hit_position

func _find_interaction_target(collider: Object) -> InteractionTargetScript:
	var node := collider as Node
	while node != null:
		if node is InteractionTargetScript:
			return node

		node = node.get_parent()

	return null

func _set_hover_target(target: InteractionTargetScript) -> void:
	if _current_target == target:
		return

	if _current_target != null:
		_current_target.set_hovered(false)

	_current_target = target

	if _current_target != null:
		_current_target.set_hovered(true)

	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"hover_target_changed", _current_target)

func _request_menu_for_current_target(screen_position: Vector2) -> void:
	if not _is_gameplay_input_enabled:
		return
	if _current_target == null or not _current_target.is_interaction_enabled():
		return

	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"interaction_menu_requested", _current_target, screen_position)
	get_viewport().set_input_as_handled()

func _handle_interaction_action_requested(target: Node, action_id: StringName) -> void:
	if not _is_gameplay_input_enabled:
		return

	if action_id == InteractionActionResolverScript.ACTION_MOVE:
		start_targeting(target, action_id)
		return

	if action_id != InteractionActionResolverScript.ACTION_EXAMINE:
		return
	if not InteractionActionResolverScript.can_examine(target):
		return

	var target_domain: StringName = &""
	if target.has_method("get_target_domain"):
		var target_domain_value: Variant = target.call("get_target_domain")
		target_domain = target_domain_value if target_domain_value is StringName else StringName(str(target_domain_value))

	var target_data: Resource
	if target.has_method("get_target_data"):
		target_data = target.call("get_target_data") as Resource

	var output := InteractionActionResolverScript.build_examine_output(target)
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"examined_output", target_domain, target_data, output)

func _handle_interaction_pointer_capture_changed(is_captured: bool) -> void:
	_is_interaction_pointer_captured = is_captured

func _handle_interaction_ui_cancel_requested() -> void:
	if is_targeting_interaction():
		cancel_targeting()

func _handle_editor_mode_changed(mode: StringName) -> void:
	_is_gameplay_input_enabled = mode != &"editor"
	if _is_gameplay_input_enabled:
		return

	clear_hover()
	if is_targeting_interaction():
		cancel_targeting()
	_request_interaction_ui_cancel()

func _request_interaction_ui_cancel() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"interaction_ui_cancel_requested")

func _resolve_camera() -> Camera3D:
	var configured_camera := get_node_or_null(camera_path) as Camera3D
	if configured_camera != null:
		return configured_camera

	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null

func _should_pause_hover() -> bool:
	return (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")

func _emit_event(signal_name: StringName, args: Array) -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	match signal_name:
		&"interaction_targeting_started":
			event_bus.emit_signal(signal_name, args[0], args[1])
		&"interaction_targeting_cancelled":
			event_bus.emit_signal(signal_name, args[0], args[1])
		&"interaction_targeting_failed":
			event_bus.emit_signal(signal_name, args[0], args[1], args[2], args[3], args[4])
		&"move_requested":
			event_bus.emit_signal(signal_name, args[0], args[1], args[2])
