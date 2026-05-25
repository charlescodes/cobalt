class_name BspResizeTool
extends "res://src/editor/tools/editor_tool.gd"

const BspEditorContextScript := preload("res://src/editor/tools/bsp_editor_context.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const EditorSnappingResolverScript := preload("res://src/editor/editor_snapping_resolver.gd")

const RESIZE_SIDE_PICK_DISTANCE_M: float = 2.5
const LOCKED_RESIZE_SIDE_PICK_DISTANCE_M: float = 0.75
const RESIZE_HOVER_DISTANCE_M: float = 0.4

var _context: BspEditorContextScript
var _is_resizing: bool = false
var _resize_side: StringName = &""
var _last_resize_split_position: float = INF
var _hover_target: Dictionary = {}

func _init(context: BspEditorContextScript = null) -> void:
	_context = context

func set_context(context: BspEditorContextScript) -> void:
	_context = context

func activate(_editor_controller: Node) -> void:
	if _context != null:
		_context.lock_current_selection()

func deactivate() -> void:
	_end_resize()
	_clear_hover_target()

func on_mouse_motion(raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	if _is_resizing:
		resize_selected_side_to_position(_resize_side, raycast_hit)
		_update_hover_target_for_active_side()
		return

	_update_hover_target(raycast_hit)

func on_left_click_down(raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	begin_resize_at_position(raycast_hit)

func on_left_click_up(_raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	_end_resize()
	_update_hover_target(_raycast_hit)

func on_cancel(_modifiers: Dictionary) -> void:
	_end_resize()
	_clear_hover_target()
	if _context != null:
		_context.clear_selection_context()

func uses_snapping_grid() -> bool:
	return true

func get_snapping_context(_raw_pos: Vector3, _modifiers: Dictionary) -> Dictionary:
	return {&"elevation_y": 0.0}

func begin_resize_at_position(position: Vector3) -> void:
	if _context == null:
		return

	var data := _context.current_bsp_data()
	if data == null:
		return

	if _context.get_selected_room_id() != &"" and not _context.is_selection_context_locked():
		_context.lock_current_selection()

	var side_info := {}
	if _context.is_selection_context_locked():
		side_info = BspRoomProcessorScript.nearest_resizable_room_side_for_room(
			data,
			_context.get_selected_room_id(),
			position,
			LOCKED_RESIZE_SIDE_PICK_DISTANCE_M
		)
		if not bool(side_info.get("ok", false)):
			if _is_outside_locked_room_context(position):
				_context.clear_selection_context()
				_clear_hover_target()
			return
	else:
		side_info = BspRoomProcessorScript.nearest_resizable_room_side(
			data,
			position,
			RESIZE_SIDE_PICK_DISTANCE_M
		)
	if not bool(side_info.get("ok", false)):
		var room := BspRoomProcessorScript.room_at_position(data, position)
		if room != null:
			_context.lock_selected_room_id(room.id)
		else:
			_context.clear_selection_context()
			_clear_hover_target()
		return

	var room_id := side_info.get("room_id", &"") as StringName
	if room_id == &"":
		return

	_context.lock_selected_room_id(room_id)
	_resize_side = side_info.get("side", &"") as StringName
	_is_resizing = _resize_side != &""
	_last_resize_split_position = INF
	_set_hover_target_from_side_info(side_info)
	if _is_resizing:
		resize_selected_side_to_position(_resize_side, position)

func resize_selected_side_to_position(side: StringName, position: Vector3) -> bool:
	if _context == null:
		return false

	var data := _context.current_bsp_data()
	if data == null or _context.get_selected_room_id() == &"" or side == &"":
		return false
	if not _context.is_selection_context_locked():
		_context.lock_current_selection()

	var snapped_position := EditorSnappingResolverScript.snap_vector3(
		position,
		get_snapping_step()
	)
	var result := BspRoomProcessorScript.resize_room_side_to_position(
		data,
		_context.get_selected_room_id(),
		side,
		snapped_position,
		get_snapping_step()
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

func _update_hover_target(position: Vector3) -> void:
	if _context == null:
		_clear_hover_target()
		return

	var data := _context.current_bsp_data()
	if data == null:
		_clear_hover_target()
		return

	var side_info := {}
	if _context.is_selection_context_locked() and _context.get_selected_room_id() != &"":
		side_info = BspRoomProcessorScript.nearest_resizable_room_side_for_room(
			data,
			_context.get_selected_room_id(),
			position,
			RESIZE_HOVER_DISTANCE_M
		)
	else:
		side_info = BspRoomProcessorScript.nearest_resizable_room_side(
			data,
			position,
			RESIZE_HOVER_DISTANCE_M
		)

	if bool(side_info.get("ok", false)):
		_set_hover_target_from_side_info(side_info)
	else:
		_clear_hover_target()

func _update_hover_target_for_active_side() -> void:
	if _context == null or _context.get_selected_room_id() == &"" or _resize_side == &"":
		_clear_hover_target()
		return

	var data := _context.current_bsp_data()
	if data == null:
		_clear_hover_target()
		return

	var side_info := BspRoomProcessorScript.room_side_info(
		data,
		_context.get_selected_room_id(),
		_resize_side
	)
	if bool(side_info.get("ok", false)):
		_set_hover_target_from_side_info(side_info)
	else:
		_clear_hover_target()

func _set_hover_target_from_side_info(side_info: Dictionary) -> void:
	var start_value: Variant = side_info.get("partition_start")
	var end_value: Variant = side_info.get("partition_end")
	if not (start_value is Vector3) or not (end_value is Vector3):
		start_value = side_info.get("start", Vector3.ZERO)
		end_value = side_info.get("end", Vector3.ZERO)
	if not (start_value is Vector3) or not (end_value is Vector3):
		_clear_hover_target()
		return

	_hover_target = {
		&"kind": &"bsp_split",
		&"room_id": side_info.get("room_id", &"") as StringName,
		&"side": side_info.get("side", &"") as StringName,
		&"partition_id": side_info.get("partition_id", &"") as StringName,
		&"start": start_value as Vector3,
		&"end": end_value as Vector3,
	}
	if _context != null:
		_context.set_hovered_bsp_segment(_hover_target)

func _clear_hover_target() -> void:
	_hover_target.clear()
	if _context != null:
		_context.clear_hovered_bsp_segment()

func _is_outside_locked_room_context(position: Vector3) -> bool:
	if _context == null or not _context.is_selection_context_locked():
		return false

	var data := _context.current_bsp_data()
	var room_id := _context.get_selected_room_id()
	if data == null or room_id == &"":
		return true

	var side_info := BspRoomProcessorScript.nearest_resizable_room_side_for_room(
		data,
		room_id,
		position,
		LOCKED_RESIZE_SIDE_PICK_DISTANCE_M
	)
	if bool(side_info.get("ok", false)):
		return false

	var room := BspRoomProcessorScript.room_at_position(data, position)
	return room == null or room.id != room_id
