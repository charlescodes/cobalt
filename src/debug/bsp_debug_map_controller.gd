class_name BspDebugMapController
extends Node

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")

@export var map_loader_path: NodePath = ^"../MapLoader"
@export var bsp_data: BspModuleDataScript = BspModuleDataScript.new()

var _authored_map_data: MapDataScript
var _is_bsp_enabled: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay"):
		set_bsp_enabled(not _is_bsp_enabled)
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func set_bsp_enabled(enabled: bool) -> void:
	if enabled == _is_bsp_enabled:
		return

	var map_loader := _resolve_map_loader()
	if map_loader == null:
		return

	if _authored_map_data == null:
		_authored_map_data = map_loader.map_data

	if enabled:
		map_loader.map_data = BspRoomProcessorScript.compile_to_map_data(_resolved_bsp_data())
	else:
		map_loader.map_data = _authored_map_data

	map_loader.load_map()
	_is_bsp_enabled = enabled

func is_bsp_enabled() -> bool:
	return _is_bsp_enabled

func _resolve_map_loader() -> MapLoaderScript:
	var configured_loader := get_node_or_null(map_loader_path) as MapLoaderScript
	if configured_loader != null:
		return configured_loader

	return get_parent().get_node_or_null("MapLoader") as MapLoaderScript if get_parent() != null else null

func _resolved_bsp_data() -> BspModuleDataScript:
	return bsp_data if bsp_data != null else BspModuleDataScript.new()
