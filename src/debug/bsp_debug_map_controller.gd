class_name BspDebugMapController
extends Node

signal bsp_debug_map_changed(enabled: bool, data: Resource)

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const DebugOverlayControllerScript := preload("res://src/ui/debug_overlay_controller.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const NavigationDebugOverlayScript := preload("res://src/ui/navigation_debug_overlay.gd")

@export var map_loader_path: NodePath = ^"../MapLoader"
@export var debug_overlay_controller_path: NodePath = ^"../DebugOverlayController"
@export var navigation_overlay_path: NodePath = ^"../NavigationDebugOverlay"
@export var bsp_data: BspModuleDataScript = BspModuleDataScript.new()
@export var bsp_enabled_on_ready: bool = true

var _authored_map_data: MapDataScript
var _generated_bsp_data: BspModuleDataScript
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
		_load_bsp_map(map_loader)
	else:
		map_loader.map_data = _authored_map_data
		_generated_bsp_data = null

	if not enabled:
		map_loader.load_map()
	_set_debug_overlay_for_bsp(enabled)
	_set_navigation_overlay_bsp_data(_generated_bsp_data if enabled else null)
	_is_bsp_enabled = enabled
	emit_signal(&"bsp_debug_map_changed", _is_bsp_enabled, get_bsp_debug_data())

func is_bsp_enabled() -> bool:
	return _is_bsp_enabled

func get_bsp_data() -> BspModuleDataScript:
	return _resolved_bsp_data()

func get_bsp_debug_data() -> BspModuleDataScript:
	if _generated_bsp_data != null:
		return _generated_bsp_data

	return _resolved_bsp_data()

func get_generated_bsp_data() -> BspModuleDataScript:
	return _generated_bsp_data

func commit_generated_bsp_edits() -> bool:
	if not _is_bsp_enabled or _generated_bsp_data == null:
		return false

	var map_loader := _resolve_map_loader()
	if map_loader == null:
		return false

	map_loader.map_data = BspRoomProcessorScript.compile_to_map_data(_generated_bsp_data)
	map_loader.load_map()
	_set_navigation_overlay_bsp_data(_generated_bsp_data)
	emit_signal(&"bsp_debug_map_changed", _is_bsp_enabled, _generated_bsp_data)
	return true

func apply_bsp_parameters(
	building_size_m: Vector2,
	min_room_size_m: float,
	max_split_depth: int,
	seed: int
) -> void:
	var data := _resolved_bsp_data()
	data.building_size_m = building_size_m
	data.min_room_size_m = min_room_size_m
	data.max_split_depth = max_split_depth
	data.seed = seed
	if _is_bsp_enabled:
		var map_loader := _resolve_map_loader()
		if map_loader != null:
			_load_bsp_map(map_loader)
		_set_navigation_overlay_bsp_data(_generated_bsp_data)
	emit_signal(&"bsp_debug_map_changed", _is_bsp_enabled, get_bsp_debug_data())

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

func _resolve_navigation_overlay() -> NavigationDebugOverlayScript:
	var configured_overlay := get_node_or_null(navigation_overlay_path) as NavigationDebugOverlayScript
	if configured_overlay != null:
		return configured_overlay

	return get_parent().get_node_or_null("NavigationDebugOverlay") as NavigationDebugOverlayScript if get_parent() != null else null

func _resolved_bsp_data() -> BspModuleDataScript:
	if bsp_data == null:
		bsp_data = BspModuleDataScript.new()
	return bsp_data

func _load_bsp_map(map_loader: MapLoaderScript) -> void:
	_generated_bsp_data = BspRoomProcessorScript.generate(_resolved_bsp_data())
	map_loader.map_data = BspRoomProcessorScript.compile_to_map_data(_generated_bsp_data)
	map_loader.load_map()

func _set_navigation_overlay_bsp_data(data: BspModuleDataScript) -> void:
	var navigation_overlay := _resolve_navigation_overlay()
	if navigation_overlay == null:
		return

	navigation_overlay.set_bsp_debug_data(data)

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
