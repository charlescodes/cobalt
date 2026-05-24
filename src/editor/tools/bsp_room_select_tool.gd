class_name BspRoomSelectTool
extends "res://src/editor/tools/editor_tool.gd"

const BspEditorContextScript := preload("res://src/editor/tools/bsp_editor_context.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")

var _context: BspEditorContextScript

func _init(context: BspEditorContextScript = null) -> void:
	_context = context

func set_context(context: BspEditorContextScript) -> void:
	_context = context

func on_left_click_down(raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	select_room_at_position(raycast_hit)

func select_room_at_position(position: Vector3) -> bool:
	if _context == null:
		return false

	var data := _context.current_bsp_data()
	if data == null:
		_context.set_selected_room_id(&"")
		return false

	var room := BspRoomProcessorScript.room_at_position(data, position)
	if room == null:
		_context.set_selected_room_id(&"")
		return false

	_context.set_selected_room_id(room.id)
	return true
