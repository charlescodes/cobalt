class_name BspDebugMapController
extends Node

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const DebugOverlayControllerScript := preload("res://src/ui/debug_overlay_controller.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")

@export var map_loader_path: NodePath = ^"../MapLoader"
@export var debug_overlay_controller_path: NodePath = ^"../DebugOverlayController"
@export var bsp_data: BspModuleDataScript = BspModuleDataScript.new()
@export var bsp_enabled_on_ready: bool = true

var _authored_map_data: MapDataScript
var _authored_debug_visible: bool = false
var _has_authored_debug_visible: bool = false
var _is_bsp_enabled: bool = false

func _ready() -> void:
	if bsp_enabled_on_ready:
		call_deferred("set_bsp_enabled", true)

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
	_set_debug_overlay_for_bsp(enabled)
	_is_bsp_enabled = enabled

func is_bsp_enabled() -> bool:
	return _is_bsp_enabled

func _resolve_map_loader() -> MapLoaderScript:
	var configured_loader := get_node_or_null(map_loader_path) as MapLoaderScript
	if configured_loader != null:
		return configured_loader

	return get_parent().get_node_or_null("MapLoader") as MapLoaderScript if get_parent() != null else null

func _resolve_debug_overlay_controller() -> DebugOverlayControllerScript:
	var configured_controller := get_node_or_null(debug_overlay_controller_path) as DebugOverlayControllerScript
	if configured_controller != null:
		return configured_controller

	return get_parent().get_node_or_null("DebugOverlayController") as DebugOverlayControllerScript if get_parent() != null else null

func _resolved_bsp_data() -> BspModuleDataScript:
	return bsp_data if bsp_data != null else BspModuleDataScript.new()

func _set_debug_overlay_for_bsp(enabled: bool) -> void:
	var debug_overlay_controller := _resolve_debug_overlay_controller()
	if debug_overlay_controller == null:
		return

	if enabled:
		if not _has_authored_debug_visible:
			_authored_debug_visible = debug_overlay_controller.is_debug_visible()
			_has_authored_debug_visible = true
		debug_overlay_controller.set_debug_visible(true)
		return

	debug_overlay_controller.set_debug_visible(_authored_debug_visible)
	_has_authored_debug_visible = false
