class_name BspDoorTool
extends "res://src/editor/tools/editor_tool.gd"

const BspEditorContextScript := preload("res://src/editor/tools/bsp_editor_context.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const BspRoomSelectToolScript := preload("res://src/editor/tools/bsp_room_select_tool.gd")

var _context: BspEditorContextScript
var _select_tool: BspRoomSelectToolScript

func _init(
	context: BspEditorContextScript = null,
	select_tool: BspRoomSelectToolScript = null
) -> void:
	_context = context
	_select_tool = select_tool

func set_context(context: BspEditorContextScript) -> void:
	_context = context

func set_select_tool(select_tool: BspRoomSelectToolScript) -> void:
	_select_tool = select_tool

func on_left_click_down(raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	if _context != null and _context.get_selected_room_id() == &"":
		if _select_tool != null:
			_select_tool.select_room_at_position(raycast_hit)
		return

	toggle_manual_door_at_position(raycast_hit)

func uses_snapping_grid() -> bool:
	return true

func toggle_manual_door_at_position(position: Vector3) -> bool:
	if _context == null:
		return false

	var data := _context.current_bsp_data()
	if data == null or _context.get_selected_room_id() == &"":
		return false

	var result := BspRoomProcessorScript.toggle_manual_door_at_position(
		data,
		_context.get_selected_room_id(),
		position
	)
	if not bool(result.get("ok", false)):
		return false

	return _context.commit_edits()
