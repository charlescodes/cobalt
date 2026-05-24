class_name BspResizeTool
extends "res://src/editor/tools/editor_tool.gd"

const BspEditorContextScript := preload("res://src/editor/tools/bsp_editor_context.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")

const RESIZE_SIDE_PICK_DISTANCE_M: float = 2.5

var _context: BspEditorContextScript
var _is_resizing: bool = false
var _resize_side: StringName = &""
var _last_resize_split_position: float = INF

func _init(context: BspEditorContextScript = null) -> void:
	_context = context

func set_context(context: BspEditorContextScript) -> void:
	_context = context

func deactivate() -> void:
	_end_resize()

func on_mouse_motion(raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	if _is_resizing:
		resize_selected_side_to_position(_resize_side, raycast_hit)

func on_left_click_down(raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	begin_resize_at_position(raycast_hit)

func on_left_click_up(_raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	_end_resize()

func begin_resize_at_position(position: Vector3) -> void:
	if _context == null:
		return

	var data := _context.current_bsp_data()
	if data == null:
		return

	var side_info := BspRoomProcessorScript.nearest_resizable_room_side(
		data,
		position,
		RESIZE_SIDE_PICK_DISTANCE_M
	)
	if not bool(side_info.get("ok", false)):
		return

	var room_id := side_info.get("room_id", &"") as StringName
	if room_id == &"":
		return

	_context.set_selected_room_id(room_id)
	_resize_side = side_info.get("side", &"") as StringName
	_is_resizing = _resize_side != &""
	_last_resize_split_position = INF
	if _is_resizing:
		resize_selected_side_to_position(_resize_side, position)

func resize_selected_side_to_position(side: StringName, position: Vector3) -> bool:
	if _context == null:
		return false

	var data := _context.current_bsp_data()
	if data == null or _context.get_selected_room_id() == &"" or side == &"":
		return false

	var result := BspRoomProcessorScript.resize_room_side_to_position(
		data,
		_context.get_selected_room_id(),
		side,
		position
	)
	if not bool(result.get("ok", false)):
		return false

	var split_position := float(result.get("split_position", INF))
	if is_equal_approx(split_position, _last_resize_split_position):
		return false

	_last_resize_split_position = split_position
	return _context.commit_edits()

func _end_resize() -> void:
	_is_resizing = false
	_resize_side = &""
	_last_resize_split_position = INF
