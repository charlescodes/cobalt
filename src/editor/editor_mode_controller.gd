class_name EditorModeController
extends Node

const DevMenuScript := preload("res://src/editor/dev_menu.gd")
const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const GroundDataScript := preload("res://src/environment/ground_data.gd")
const MapFileStoreScript := preload("res://src/editor/map_file_store.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const MODE_GAME: StringName = &"game"
const MODE_EDITOR: StringName = &"editor"
const MODE_WORLD_EDITOR: StringName = &"world_editor"
const DEFAULT_WORLD_SIZE_M: float = 500000.0
const DEFAULT_WORLD_GROUND_HEIGHT_M: float = 0.1

@export var map_loader_path: NodePath = ^"../MapLoader"
@export var dev_menu_path: NodePath = ^"../InteractionUI/DevMenu"
@export var start_mode: StringName = MODE_EDITOR

var _mode: StringName = MODE_EDITOR
var _dev_menu: DevMenuScript
var _map_file_store := MapFileStoreScript.new()
var _editor_map_active: bool = false
var _local_editor_map_data: MapDataScript
var _world_map_data: MapDataScript

func _ready() -> void:
	_mode = start_mode if _is_known_mode(start_mode) else MODE_EDITOR
	_dev_menu = get_node_or_null(dev_menu_path) as DevMenuScript
	if _dev_menu != null:
		_dev_menu.hide_menu()
		_connect_dev_menu()
		_dev_menu.set_mode(_mode)

	call_deferred("_finish_startup")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_dev_menu"):
		toggle_dev_menu()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func toggle_dev_menu() -> void:
	if _dev_menu != null:
		_dev_menu.toggle_menu()

func set_dev_menu_visible(is_visible: bool) -> void:
	if _dev_menu == null:
		return
	if is_visible:
		_dev_menu.show_menu()
	else:
		_dev_menu.hide_menu()

func enter_game_mode() -> void:
	set_mode(MODE_GAME)

func enter_editor_mode() -> void:
	set_mode(MODE_EDITOR)

func enter_world_editor_mode() -> void:
	set_mode(MODE_WORLD_EDITOR)

func set_mode(next_mode: StringName) -> void:
	if not _is_known_mode(next_mode):
		return

	var previous_mode := _mode
	if previous_mode != MODE_WORLD_EDITOR:
		_cache_local_editor_map()
	_mode = next_mode
	if _dev_menu != null:
		_dev_menu.set_mode(_mode)
	if _mode == MODE_EDITOR:
		_ensure_editor_map_active(previous_mode == MODE_WORLD_EDITOR)
	elif _mode == MODE_WORLD_EDITOR:
		_ensure_world_map_active()
	_emit_mode_changed()

func get_mode() -> StringName:
	return _mode

func has_editor_map_active() -> bool:
	return _editor_map_active

func save_current_map(requested_name: String = "") -> String:
	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		_set_menu_status("No map to save")
		return ""

	var filename := _menu_filename_if_empty(requested_name)
	var path := _map_file_store.save_map(map_loader.map_data, filename)
	if path.is_empty():
		_set_menu_status("Save failed")
		return ""

	_set_menu_status("Saved %s" % path)
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_map_saved", map_loader.map_data, path)
	return path

func load_map(requested_name: String = "") -> MapDataScript:
	var filename := _menu_filename_if_empty(requested_name)
	var loaded_map := _map_file_store.load_map(filename)
	if loaded_map == null:
		_set_menu_status("Load failed")
		return null

	var map_loader := _resolve_map_loader()
	if map_loader == null:
		_set_menu_status("MapLoader missing")
		return null

	_editor_map_active = true
	_local_editor_map_data = loaded_map
	map_loader.replace_map_data(loaded_map, true)
	var path := _map_file_store.map_path_for_name(filename)
	_set_menu_status("Loaded %s" % path)
	_emit_editor_map_loaded(loaded_map, path)
	return loaded_map

func _connect_dev_menu() -> void:
	var game_callable := Callable(self, "enter_game_mode")
	var editor_callable := Callable(self, "enter_editor_mode")
	var world_editor_callable := Callable(self, "enter_world_editor_mode")
	var save_callable := Callable(self, "save_current_map")
	var load_callable := Callable(self, "load_map")
	if not _dev_menu.is_connected(&"game_mode_requested", game_callable):
		_dev_menu.connect(&"game_mode_requested", game_callable)
	if not _dev_menu.is_connected(&"editor_mode_requested", editor_callable):
		_dev_menu.connect(&"editor_mode_requested", editor_callable)
	if not _dev_menu.is_connected(&"world_editor_mode_requested", world_editor_callable):
		_dev_menu.connect(&"world_editor_mode_requested", world_editor_callable)
	if not _dev_menu.is_connected(&"save_map_requested", save_callable):
		_dev_menu.connect(&"save_map_requested", save_callable)
	if not _dev_menu.is_connected(&"load_map_requested", load_callable):
		_dev_menu.connect(&"load_map_requested", load_callable)

func _finish_startup() -> void:
	if _mode == MODE_EDITOR:
		_ensure_editor_map_active()
	elif _mode == MODE_WORLD_EDITOR:
		_ensure_world_map_active()
	_emit_mode_changed()

func _ensure_editor_map_active(force_restore_local_map: bool = false) -> void:
	if force_restore_local_map and _local_editor_map_data != null:
		var map_loader := _resolve_map_loader()
		if map_loader == null:
			return

		_editor_map_active = true
		map_loader.replace_map_data(_local_editor_map_data, true)
		_emit_editor_map_loaded(_local_editor_map_data, _local_editor_map_data.resource_path)
		return

	if _editor_map_active:
		var active_loader := _resolve_map_loader()
		if active_loader != null and active_loader.map_data != null and active_loader.map_data.world_geology == null:
			return

	var map_loader := _resolve_map_loader()
	if map_loader == null:
		return
	if map_loader.map_data == null:
		_load_blank_editor_map()
		return

	_editor_map_active = true
	_local_editor_map_data = map_loader.map_data
	_emit_editor_map_loaded(map_loader.map_data, map_loader.map_data.resource_path)

func _load_blank_editor_map() -> void:
	var map_loader := _resolve_map_loader()
	if map_loader == null:
		return

	var blank_map := _map_file_store.create_blank_editor_map()
	_editor_map_active = true
	_local_editor_map_data = blank_map
	map_loader.replace_map_data(blank_map, true)
	_emit_editor_map_loaded(blank_map, "")

func _ensure_world_map_active() -> void:
	_cache_local_editor_map()
	var map_loader := _resolve_map_loader()
	if map_loader == null:
		return

	if _world_map_data == null:
		_world_map_data = _create_default_world_map()

	map_loader.replace_map_data(_world_map_data, false)
	_emit_editor_map_loaded(_world_map_data, "")

func _create_default_world_map() -> MapDataScript:
	var geology_data := WorldGeologyDataScript.new(
		"cobalt_world",
		Vector2(DEFAULT_WORLD_SIZE_M, DEFAULT_WORLD_SIZE_M)
	)
	var ground := GroundDataScript.new(
		&"world_macro_ground",
		Vector3(0.0, -(DEFAULT_WORLD_GROUND_HEIGHT_M * 0.5), 0.0),
		Vector3(DEFAULT_WORLD_SIZE_M, DEFAULT_WORLD_GROUND_HEIGHT_M, DEFAULT_WORLD_SIZE_M),
		Color(0.09, 0.11, 0.1, 1.0)
	)
	var grounds: Array[GroundDataScript] = []
	var walls: Array[WallDataScript] = []
	var objects: Array[WorldObjectDataScript] = []
	var door_sockets: Array[DoorSocketDataScript] = []
	grounds.append(ground)
	return MapDataScript.new("world_macro", grounds, walls, objects, door_sockets, geology_data)

func _cache_local_editor_map() -> void:
	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		return
	if map_loader.map_data.world_geology != null:
		return

	_local_editor_map_data = map_loader.map_data
	_editor_map_active = true

func _emit_editor_map_loaded(map_data: MapDataScript, path: String) -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_map_loaded", map_data, path)

func _menu_filename_if_empty(requested_name: String) -> String:
	if not requested_name.strip_edges().is_empty():
		return requested_name
	if _dev_menu != null:
		return _dev_menu.get_filename()

	return MapFileStoreScript.DEFAULT_FILENAME

func _set_menu_status(text: String) -> void:
	if _dev_menu != null:
		_dev_menu.set_status(text)

func _resolve_map_loader() -> MapLoaderScript:
	return get_node_or_null(map_loader_path) as MapLoaderScript

func _is_known_mode(mode: StringName) -> bool:
	return mode == MODE_GAME or mode == MODE_EDITOR or mode == MODE_WORLD_EDITOR

func _emit_mode_changed() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_mode_changed", _mode)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
