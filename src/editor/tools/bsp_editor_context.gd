class_name BspEditorContext
extends RefCounted

const BspDebugMapControllerScript := preload("res://src/debug/bsp_debug_map_controller.gd")
const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const NavigationDebugOverlayScript := preload("res://src/ui/navigation_debug_overlay.gd")

var _bsp_controller: BspDebugMapControllerScript
var _navigation_overlay: NavigationDebugOverlayScript
var _selected_room_id: StringName = &""

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

func set_selected_room_id(room_id: StringName) -> void:
	_selected_room_id = room_id
	if _navigation_overlay != null:
		_navigation_overlay.set_selected_bsp_room_id(_selected_room_id)

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
