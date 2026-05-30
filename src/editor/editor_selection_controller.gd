class_name EditorSelectionController
extends Node

const EditorSelectionHighlighterScript := preload("res://src/editor/editor_selection_highlighter.gd")
const MapBuilderScript := preload("res://src/maps/map_builder.gd")

@export var camera_path: NodePath = ^"../CameraRig/PitchPivot/Camera3D"
@export_range(1.0, 500.0, 1.0) var max_ray_distance_m: float = 100.0
@export_flags_3d_physics var collision_mask: int = 1

var _camera: Camera3D
var _is_editor_mode: bool = false
var _selected_node: Node
var _selected_data: Resource
var _selected_kind: StringName = &""
var _highlighter: EditorSelectionHighlighterScript

func _ready() -> void:
	_camera = _resolve_camera()
	_highlighter = EditorSelectionHighlighterScript.new()
	_highlighter.name = "EditorSelectionHighlighter"
	add_child(_highlighter)

	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	var mode_callable := Callable(self, "_on_editor_mode_changed")
	var map_loaded_callable := Callable(self, "_on_editor_map_loaded")
	if event_bus.has_signal(&"editor_mode_changed") and not event_bus.is_connected(&"editor_mode_changed", mode_callable):
		event_bus.connect(&"editor_mode_changed", mode_callable)
	if event_bus.has_signal(&"editor_map_loaded") and not event_bus.is_connected(&"editor_map_loaded", map_loaded_callable):
		event_bus.connect(&"editor_map_loaded", map_loaded_callable)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_editor_mode:
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		select_at_screen(mouse_event.position)
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func select_at_screen(screen_position: Vector2) -> bool:
	if not _is_editor_mode:
		return false

	var hit := _raycast_editor_selectable_at(screen_position)
	if hit.is_empty():
		clear_selection()
		return false

	_set_selection(
		hit.get("node") as Node,
		hit.get("data") as Resource,
		hit.get("kind", &"") as StringName
	)
	return true

func clear_selection() -> void:
	if _selected_node == null and _selected_data == null and _selected_kind == &"":
		return

	_selected_node = null
	_selected_data = null
	_selected_kind = &""
	if _highlighter != null:
		_highlighter.clear()
	_emit_selection_changed()

func get_selected_node() -> Node:
	return _selected_node

func get_selected_data() -> Resource:
	return _selected_data

func get_selected_kind() -> StringName:
	return _selected_kind

func _set_selection(selected_node: Node, selected_data: Resource, selected_kind: StringName) -> void:
	_selected_node = selected_node
	_selected_data = selected_data
	_selected_kind = selected_kind
	if _highlighter != null:
		_highlighter.highlight(_selected_node)
	_emit_selection_changed()

func _raycast_editor_selectable_at(screen_position: Vector2) -> Dictionary:
	if _camera == null:
		_camera = _resolve_camera()
		if _camera == null:
			return {}

	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + (_camera.project_ray_normal(screen_position) * max_ray_distance_m)
	var excluded: Array[RID] = []

	for _attempt in range(32):
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, collision_mask)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = excluded

		var result := _camera.get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			return {}

		var collider := result.get("collider") as Object
		var selectable := _find_editor_selectable(collider)
		if not selectable.is_empty():
			return selectable

		var collision_object := collider as CollisionObject3D
		if collision_object == null:
			return {}
		excluded.append(collision_object.get_rid())

	return {}

func _find_editor_selectable(collider: Object) -> Dictionary:
	var node := collider as Node
	while node != null:
		if node.has_meta(MapBuilderScript.EDITOR_KIND_META):
			var root := node.get_meta(MapBuilderScript.EDITOR_ROOT_META, node) as Node
			var data := node.get_meta(MapBuilderScript.EDITOR_SOURCE_META, null) as Resource
			var kind_value: Variant = node.get_meta(MapBuilderScript.EDITOR_KIND_META, &"")
			var kind: StringName = kind_value if kind_value is StringName else StringName(str(kind_value))
			return {
				"node": root if root != null else node,
				"data": data,
				"kind": kind,
			}

		node = node.get_parent()

	return {}

func _on_editor_mode_changed(mode: StringName) -> void:
	_is_editor_mode = mode == &"editor"
	if not _is_editor_mode:
		clear_selection()

func _on_editor_map_loaded(_map_data: Resource, _path: String) -> void:
	clear_selection()

func _resolve_camera() -> Camera3D:
	var configured_camera := get_node_or_null(camera_path) as Camera3D
	if configured_camera != null:
		return configured_camera

	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null

func _emit_selection_changed() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_selection_changed", _selected_node, _selected_data, _selected_kind)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
