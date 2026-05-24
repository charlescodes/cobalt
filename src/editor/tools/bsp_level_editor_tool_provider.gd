class_name BspLevelEditorToolProvider
extends Node

const BspDoorToolScript := preload("res://src/editor/tools/bsp_door_tool.gd")
const BspEditorContextScript := preload("res://src/editor/tools/bsp_editor_context.gd")
const BspResizeToolScript := preload("res://src/editor/tools/bsp_resize_tool.gd")
const BspRoomSelectToolScript := preload("res://src/editor/tools/bsp_room_select_tool.gd")
const LevelEditorControllerScript := preload("res://src/editor/level_editor_controller.gd")

const TOOL_SELECT: StringName = &"select"
const TOOL_DOOR: StringName = &"door"
const TOOL_RESIZE: StringName = &"resize"

@export var level_editor_controller_path: NodePath = ^".."
@export var bsp_controller_path: NodePath = ^"../../BspDebugMapController"
@export var navigation_overlay_path: NodePath = ^"../../NavigationDebugOverlay"

var _context: BspEditorContextScript = BspEditorContextScript.new()
var _level_editor_controller: LevelEditorControllerScript
var _bsp_controller: Node
var _navigation_overlay: Node
var _registered: bool = false

func _ready() -> void:
	_resolve_nodes()
	_register_tools()

func _process(_delta: float) -> void:
	_resolve_nodes()
	_register_tools()

func _register_tools() -> void:
	if _registered or _level_editor_controller == null:
		return

	var select_tool := BspRoomSelectToolScript.new(_context)
	_level_editor_controller.register_tool(TOOL_SELECT, select_tool)
	_level_editor_controller.register_tool(
		TOOL_DOOR,
		BspDoorToolScript.new(_context, select_tool)
	)
	_level_editor_controller.register_tool(
		TOOL_RESIZE,
		BspResizeToolScript.new(_context)
	)
	_registered = true

func _resolve_nodes() -> void:
	if _level_editor_controller == null:
		_level_editor_controller = get_node_or_null(
			level_editor_controller_path
		) as LevelEditorControllerScript
	if _bsp_controller == null:
		_bsp_controller = get_node_or_null(bsp_controller_path)
		_context.set_bsp_controller(_bsp_controller)
	if _navigation_overlay == null:
		_navigation_overlay = get_node_or_null(navigation_overlay_path)
		_context.set_navigation_overlay(_navigation_overlay)
