class_name BspEditorContext
extends RefCounted

const BspDebugMapControllerScript := preload("res://src/debug/bsp_debug_map_controller.gd")
const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const NavigationDebugOverlayScript := preload("res://src/ui/navigation_debug_overlay.gd")

var _bsp_controller: BspDebugMapControllerScript
var _navigation_overlay: NavigationDebugOverlayScript
var _selected_room_id: StringName = &""
var _is_selection_context_locked: bool = false

func set_bsp_controller(controller: Node) -> void:
	_bsp_controller = controller as BspDebugMapControllerScript

func set_navigation_overlay(overlay: Node) -> void:
	_navigation_overlay = overlay as NavigationDebugOverlayScript
	if _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)

func is_active() -> bool:
	return _bsp_controller != null and _bsp_controller.is_bsp_enabled()

func get_selected_room_id() -> StringName:
	return _selected_room_id

func is_selection_context_locked() -> bool:
	return _is_selection_context_locked

func set_selected_room_id(room_id: StringName) -> void:
	_selected_room_id = room_id
	_is_selection_context_locked = false
	if _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)

func lock_selected_room_id(room_id: StringName) -> void:
	_selected_room_id = room_id
	_is_selection_context_locked = room_id != &""
	if _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)

func lock_current_selection() -> bool:
	if _selected_room_id == &"":
		return false

	lock_selected_room_id(_selected_room_id)
	return true

func unlock_selection_context() -> void:
	_is_selection_context_locked = false

func clear_selection_context() -> void:
	_selected_room_id = &""
	_is_selection_context_locked = false
	if _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)

func set_hovered_bsp_segment(target: Dictionary) -> void:
	if _navigation_overlay == null:
		return
	if _navigation_overlay.has_method(&"set_bsp_editor_hover_segment"):
		_navigation_overlay.call(&"set_bsp_editor_hover_segment", target)

func clear_hovered_bsp_segment() -> void:
	if _navigation_overlay == null:
		return
	if _navigation_overlay.has_method(&"clear_bsp_editor_hover_segment"):
		_navigation_overlay.call(&"clear_bsp_editor_hover_segment")

func current_bsp_data() -> BspModuleDataScript:
	if _bsp_controller == null:
		return null

	return _bsp_controller.get_generated_bsp_data()

func commit_edits() -> bool:
	if _bsp_controller == null:
		return false

	var committed := _bsp_controller.commit_generated_bsp_edits()
	if committed and _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)
	return committed
