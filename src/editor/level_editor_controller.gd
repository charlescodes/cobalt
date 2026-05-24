class_name LevelEditorController
extends Node

const EditorSnappingResolverScript := preload("res://src/editor/editor_snapping_resolver.gd")
const EditorToolScript := preload("res://src/editor/tools/editor_tool.gd")

@export var camera_path: NodePath = ^"../CameraRig/PitchPivot/Camera3D"
@export var active_source_path: NodePath = ^"../BspDebugMapController"
@export var active_method_name: StringName = &"is_bsp_enabled"
@export var panel_path: NodePath = ^"../InteractionUI/BspDebugPanel"
@export var tool_overlay_path: NodePath
@export var editor_debug_overlay_path: NodePath = ^"../NavigationDebugOverlay"
@export var default_tool_id: StringName = &"select"

var _camera: Camera3D
var _active_source: Node
var _panel: Node
var _tool_overlay: Control
var _editor_debug_overlay: Node
var _tools: Dictionary = {}
var _active_tool_id: StringName = &"select"
var _active_tool: EditorToolScript

func _enter_tree() -> void:
	_active_tool_id = default_tool_id

func _ready() -> void:
	_resolve_nodes()
	set_active_tool(_active_tool_id)

func _process(_delta: float) -> void:
	_resolve_nodes()
	if not is_editor_active():
		_clear_editor_snap_overlay()
	if _tool_overlay != null and _active_tool != null:
		_active_tool.draw_overlay(_tool_overlay)

func _unhandled_input(event: InputEvent) -> void:
	if not is_editor_active():
		if _active_tool != null:
			_active_tool.deactivate()
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var motion_position: Variant = _ground_point_from_screen(motion.position)
		if motion_position is Vector3 and _active_tool != null:
			var modifiers := _modifiers_from_event(event)
			_update_editor_snap_overlay(motion_position as Vector3, modifiers)
			_active_tool.on_mouse_motion(motion_position as Vector3, modifiers)
			if _should_capture_mouse_motion(modifiers):
				_mark_input_handled()
		else:
			_clear_editor_snap_overlay()
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var world_position: Variant = _ground_point_from_screen(mouse_event.position)
	if not (world_position is Vector3) or _active_tool == null:
		return

	var modifiers := _modifiers_from_event(event)
	_update_editor_snap_overlay(world_position as Vector3, modifiers)
	if mouse_event.pressed:
		_active_tool.on_left_click_down(world_position as Vector3, modifiers)
	else:
		_active_tool.on_left_click_up(world_position as Vector3, modifiers)
	_mark_input_handled()

func register_tool(tool_id: StringName, tool: EditorToolScript) -> void:
	if tool == null:
		return

	_tools[tool_id] = tool
	if _active_tool == null and _active_tool_id == tool_id:
		set_active_tool(tool_id)

func unregister_tool(tool_id: StringName) -> void:
	var tool := get_tool(tool_id)
	if tool != null:
		tool.deactivate()
	_tools.erase(tool_id)
	if _active_tool_id == tool_id:
		_active_tool_id = &""
		_active_tool = null

func get_tool(tool_id: StringName) -> EditorToolScript:
	var tool: Variant = _tools.get(tool_id)
	return tool as EditorToolScript

func get_active_tool_id() -> StringName:
	return _active_tool_id

func set_active_tool(tool_id: StringName) -> bool:
	var next_tool := get_tool(tool_id)
	if next_tool == null:
		_active_tool_id = tool_id
		return false
	if _active_tool == next_tool:
		_active_tool_id = tool_id
		return true

	if _active_tool != null:
		_active_tool.deactivate()

	_active_tool_id = tool_id
	_active_tool = next_tool
	_active_tool.activate(self)
	_clear_editor_snap_overlay()
	return true

func is_editor_active() -> bool:
	if active_source_path.is_empty():
		return true
	if _active_source == null:
		_active_source = get_node_or_null(active_source_path)
	if _active_source == null:
		return false
	if active_method_name != &"" and _active_source.has_method(active_method_name):
		return bool(_active_source.call(active_method_name))
	return true

func get_edit_mode() -> StringName:
	return get_active_tool_id()

func set_edit_mode(mode: StringName) -> void:
	set_active_tool(mode)

func _ground_point_from_screen(screen_position: Vector2) -> Variant:
	if _camera == null:
		_camera = get_node_or_null(camera_path) as Camera3D
		if _camera == null:
			return null

	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_direction := _camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.0001:
		return null

	var distance := -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return null

	return ray_origin + (ray_direction * distance)

func _resolve_nodes() -> void:
	if _camera == null:
		_camera = get_node_or_null(camera_path) as Camera3D
	if _active_source == null and not active_source_path.is_empty():
		_active_source = get_node_or_null(active_source_path)
	if _panel == null:
		_panel = get_node_or_null(panel_path)
		if _panel != null:
			if _panel.has_method("get_edit_mode"):
				var mode: Variant = _panel.call("get_edit_mode")
				if mode is StringName:
					set_active_tool(mode as StringName)
				else:
					set_active_tool(StringName(str(mode)))

			var mode_callable := Callable(self, "_on_panel_edit_mode_changed")
			if _panel.has_signal(&"edit_mode_changed") and not _panel.is_connected(
				&"edit_mode_changed",
				mode_callable
			):
				_panel.connect(&"edit_mode_changed", mode_callable)
	if _tool_overlay == null and not tool_overlay_path.is_empty():
		_tool_overlay = get_node_or_null(tool_overlay_path) as Control
	if _editor_debug_overlay == null and not editor_debug_overlay_path.is_empty():
		_editor_debug_overlay = get_node_or_null(editor_debug_overlay_path)

func _on_panel_edit_mode_changed(mode: StringName) -> void:
	set_active_tool(mode)

func _modifiers_from_event(event: InputEvent) -> Dictionary:
	var modifiers := {
		&"shift": false,
		&"ctrl": false,
		&"alt": false,
		&"meta": false,
	}
	if event is InputEventWithModifiers:
		var modifier_event := event as InputEventWithModifiers
		modifiers[&"shift"] = modifier_event.shift_pressed
		modifiers[&"ctrl"] = modifier_event.ctrl_pressed
		modifiers[&"alt"] = modifier_event.alt_pressed
		modifiers[&"meta"] = modifier_event.meta_pressed
	if event is InputEventMouse:
		var mouse_event := event as InputEventMouse
		modifiers[&"screen_position"] = mouse_event.position
		modifiers[&"global_screen_position"] = mouse_event.global_position
		modifiers[&"button_mask"] = mouse_event.button_mask
	return modifiers

func _should_capture_mouse_motion(modifiers: Dictionary) -> bool:
	var button_mask := int(modifiers.get(&"button_mask", 0))
	return (button_mask & MOUSE_BUTTON_MASK_LEFT) != 0

func _update_editor_snap_overlay(raw_position: Vector3, modifiers: Dictionary) -> void:
	if _active_tool == null or not _active_tool.uses_snapping_grid():
		_clear_editor_snap_overlay()
		return
	if _editor_debug_overlay == null:
		_editor_debug_overlay = get_node_or_null(editor_debug_overlay_path)
		if _editor_debug_overlay == null:
			return

	var step := _active_tool.get_snapping_step()
	var context := _active_tool.get_snapping_context(raw_position, modifiers)
	var snapped_position := EditorSnappingResolverScript.snap_with_context(raw_position, context, step)
	if _editor_debug_overlay.has_method(&"set_editor_snap_grid_cursor"):
		_editor_debug_overlay.call(&"set_editor_snap_grid_cursor", raw_position, snapped_position, step)

func _clear_editor_snap_overlay() -> void:
	if _editor_debug_overlay == null:
		return
	if _editor_debug_overlay.has_method(&"clear_editor_snap_grid"):
		_editor_debug_overlay.call(&"clear_editor_snap_grid")

func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
