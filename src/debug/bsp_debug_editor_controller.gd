class_name BspDebugEditorController
extends Node

const BspDebugMapControllerScript := preload("res://src/debug/bsp_debug_map_controller.gd")
const BspDebugPanelScript := preload("res://src/ui/bsp_debug_panel.gd")
const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const NavigationDebugOverlayScript := preload("res://src/ui/navigation_debug_overlay.gd")

const MODE_SELECT: StringName = &"select"
const MODE_DOOR: StringName = &"door"
const MODE_RESIZE: StringName = &"resize"

@export var camera_path: NodePath = ^"../CameraRig/PitchPivot/Camera3D"
@export var bsp_controller_path: NodePath = ^"../BspDebugMapController"
@export var navigation_overlay_path: NodePath = ^"../NavigationDebugOverlay"
@export var panel_path: NodePath = ^"../InteractionUI/BspDebugPanel"

var _camera: Camera3D
var _bsp_controller: BspDebugMapControllerScript
var _navigation_overlay: NavigationDebugOverlayScript
var _panel: BspDebugPanelScript
var _edit_mode: StringName = MODE_SELECT
var _selected_room_id: StringName = &""
var _is_resizing: bool = false
var _resize_side: StringName = &""
var _last_resize_split_position: float = INF

func _ready() -> void:
	_resolve_nodes()

func _process(_delta: float) -> void:
	_resolve_nodes()

func _unhandled_input(event: InputEvent) -> void:
	if not is_editor_active():
		_is_resizing = false
		return

	if event is InputEventMouseMotion:
		if _is_resizing:
			var motion := event as InputEventMouseMotion
			var motion_position: Variant = _ground_point_from_screen(motion.position)
			if motion_position is Vector3:
				resize_selected_side_to_position(_resize_side, motion_position as Vector3)
				_mark_input_handled()
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not mouse_event.pressed:
		if _is_resizing:
			_is_resizing = false
			_resize_side = &""
			_last_resize_split_position = INF
			_mark_input_handled()
		return

	var world_position: Variant = _ground_point_from_screen(mouse_event.position)
	if not (world_position is Vector3):
		return

	match _edit_mode:
		MODE_DOOR:
			if _selected_room_id == &"":
				select_room_at_position(world_position as Vector3)
			else:
				toggle_manual_door_at_position(world_position as Vector3)
			_mark_input_handled()
		MODE_RESIZE:
			_begin_resize_at_position(world_position as Vector3)
			_mark_input_handled()
		_:
			select_room_at_position(world_position as Vector3)
			_mark_input_handled()

func is_editor_active() -> bool:
	return _bsp_controller != null and _bsp_controller.is_bsp_enabled()

func get_edit_mode() -> StringName:
	return _edit_mode

func set_edit_mode(mode: StringName) -> void:
	if mode != MODE_SELECT and mode != MODE_DOOR and mode != MODE_RESIZE:
		return

	_edit_mode = mode
	_is_resizing = false
	_resize_side = &""

func get_selected_room_id() -> StringName:
	return _selected_room_id

func select_room_at_position(position: Vector3) -> bool:
	var data := _current_bsp_data()
	if data == null:
		_set_selected_room(&"")
		return false

	var room := BspRoomProcessorScript.room_at_position(data, position)
	if room == null:
		_set_selected_room(&"")
		return false

	_set_selected_room(room.id)
	return true

func toggle_manual_door_at_position(position: Vector3) -> bool:
	var data := _current_bsp_data()
	if data == null or _selected_room_id == &"":
		return false

	var result := BspRoomProcessorScript.toggle_manual_door_at_position(data, _selected_room_id, position)
	if not bool(result.get("ok", false)):
		return false

	return _commit_edits()

func resize_selected_side_to_position(side: StringName, position: Vector3) -> bool:
	var data := _current_bsp_data()
	if data == null or _selected_room_id == &"" or side == &"":
		return false

	var result := BspRoomProcessorScript.resize_room_side_to_position(data, _selected_room_id, side, position)
	if not bool(result.get("ok", false)):
		return false

	var split_position := float(result.get("split_position", INF))
	if is_equal_approx(split_position, _last_resize_split_position):
		return false

	_last_resize_split_position = split_position
	return _commit_edits()

func _begin_resize_at_position(position: Vector3) -> void:
	if _selected_room_id == &"":
		if not select_room_at_position(position):
			return

	var data := _current_bsp_data()
	if data == null:
		return

	var side_info := BspRoomProcessorScript.nearest_room_side(data, _selected_room_id, position)
	if not bool(side_info.get("ok", false)):
		return
	if bool(side_info.get("is_perimeter", false)):
		return

	_resize_side = side_info.get("side", &"") as StringName
	_is_resizing = _resize_side != &""
	_last_resize_split_position = INF
	if _is_resizing:
		resize_selected_side_to_position(_resize_side, position)

func _set_selected_room(room_id: StringName) -> void:
	_selected_room_id = room_id
	if _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)

func _commit_edits() -> bool:
	if _bsp_controller == null:
		return false

	var committed := _bsp_controller.commit_generated_bsp_edits()
	if committed and _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)
	return committed

func _current_bsp_data() -> BspModuleDataScript:
	if _bsp_controller == null:
		return null

	return _bsp_controller.get_generated_bsp_data()

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
	if _bsp_controller == null:
		_bsp_controller = get_node_or_null(bsp_controller_path) as BspDebugMapControllerScript
	if _navigation_overlay == null:
		_navigation_overlay = get_node_or_null(navigation_overlay_path) as NavigationDebugOverlayScript
	if _panel == null:
		_panel = get_node_or_null(panel_path) as BspDebugPanelScript
		if _panel != null:
			_edit_mode = _panel.get_edit_mode()
			var mode_callable := Callable(self, "_on_panel_edit_mode_changed")
			if not _panel.edit_mode_changed.is_connected(mode_callable):
				_panel.edit_mode_changed.connect(mode_callable)

func _on_panel_edit_mode_changed(mode: StringName) -> void:
	set_edit_mode(mode)

func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
