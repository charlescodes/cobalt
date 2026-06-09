class_name EditorModeController
extends Node

const DevMenuScript := preload("res://src/editor/dev_menu.gd")
const MapFileStoreScript := preload("res://src/editor/map_file_store.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")
const WorldMapDataScript := preload("res://src/maps/world_map_data.gd")

const MODE_GAME: StringName = &"game"
const MODE_EDITOR: StringName = &"editor"
const MODE_WORLD_EDITOR: StringName = &"world_editor"
const DEFAULT_WORLD_SIZE_M: float = 500000.0

@export var map_loader_path: NodePath = ^"../MapLoader"
@export var dev_menu_path: NodePath = ^"../InteractionUI/DevMenu"
@export var start_mode: StringName = MODE_EDITOR

var _mode: StringName = MODE_EDITOR
var _dev_menu: DevMenuScript
var _map_file_store := MapFileStoreScript.new()
var _editor_map_active: bool = false
var _local_editor_map_data: MapDataScript
var _world_map_data: WorldMapDataScript

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
	_emit_mode_changed()
	if _mode == MODE_EDITOR:
		_ensure_editor_map_active(previous_mode == MODE_WORLD_EDITOR or _current_map_is_world_map())
	elif _mode == MODE_WORLD_EDITOR:
		_ensure_world_map_active()

func get_mode() -> StringName:
	return _mode

func has_editor_map_active() -> bool:
	return _editor_map_active

func save_current_map(requested_name: String = "") -> String:
	if _mode == MODE_WORLD_EDITOR or _current_map_is_world_map():
		return save_world_map(requested_name)

	return save_local_map(requested_name)

func save_local_map(requested_name: String = "") -> String:
	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		_set_menu_status("No map to save")
		return ""
	var local_map_data := map_loader.get_local_map_data()
	if local_map_data == null:
		_set_menu_status("Cannot save world map as local")
		return ""

	var filename := _menu_filename_if_empty(requested_name)
	var path := _map_file_store.save_local_map(local_map_data, filename)
	if path.is_empty():
		_set_menu_status("Save local failed")
		return ""

	_set_menu_status("Saved %s" % path)
	_emit_editor_map_saved(local_map_data, path)
	return path

func save_world_map(requested_name: String = "") -> String:
	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		_set_menu_status("No world map to save")
		return ""
	var world_map_data := map_loader.get_world_map_data()
	if world_map_data == null:
		_set_menu_status("Cannot save local map as world")
		return ""

	var filename := _menu_filename_if_empty(requested_name)
	var path := _map_file_store.save_world_map(world_map_data, filename)
	if path.is_empty():
		_set_menu_status("Save world failed")
		return ""

	_set_menu_status("Saved %s" % path)
	_emit_editor_map_saved(world_map_data, path)
	return path

func load_map(requested_name: String = "") -> Resource:
	if _mode == MODE_WORLD_EDITOR or _current_map_is_world_map():
		return load_world_map(requested_name)

	return load_local_map(requested_name)

func load_local_map(requested_name: String = "") -> MapDataScript:
	var filename := _menu_filename_if_empty(requested_name)
	var loaded_map := _map_file_store.load_local_map(filename)
	if loaded_map == null:
		_set_menu_status("Load local failed")
		return null

	var map_loader := _resolve_map_loader()
	if map_loader == null:
		_set_menu_status("MapLoader missing")
		return null

	_editor_map_active = true
	_local_editor_map_data = loaded_map
	_mode = MODE_EDITOR
	if _dev_menu != null:
		_dev_menu.set_mode(_mode)
	_emit_mode_changed()

	map_loader.replace_map_data(loaded_map, true)
	var path := _map_file_store.local_map_path_for_name(filename)
	_set_menu_status("Loaded %s" % path)
	_emit_editor_map_loaded(loaded_map, path)
	return loaded_map

func load_world_map(requested_name: String = "") -> WorldMapDataScript:
	var filename := _menu_filename_if_empty(requested_name)
	var loaded_map := _map_file_store.load_world_map(filename)
	if loaded_map == null:
		_set_menu_status("Load world failed")
		return null

	var map_loader := _resolve_map_loader()
	if map_loader == null:
		_set_menu_status("MapLoader missing")
		return null

	_cache_local_editor_map()
	_world_map_data = loaded_map
	_mode = MODE_WORLD_EDITOR
	if _dev_menu != null:
		_dev_menu.set_mode(_mode)
	_emit_mode_changed()

	map_loader.replace_map_data(loaded_map, false)
	var path := _map_file_store.world_map_path_for_name(filename)
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
	_emit_mode_changed()
	if _mode == MODE_EDITOR:
		_ensure_editor_map_active()
	elif _mode == MODE_WORLD_EDITOR:
		_ensure_world_map_active()

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
		if active_loader != null and active_loader.get_local_map_data() != null:
			return

	var map_loader := _resolve_map_loader()
	if map_loader == null:
		return
	if map_loader.map_data == null:
		_load_blank_editor_map()
		return
	if map_loader.is_world_map_loaded() and _local_editor_map_data != null:
		map_loader.replace_map_data(_local_editor_map_data, true)
		_emit_editor_map_loaded(_local_editor_map_data, _local_editor_map_data.resource_path)
		return
	var local_map_data := map_loader.get_local_map_data()
	if local_map_data == null:
		_load_blank_editor_map()
		return

	_editor_map_active = true
	_local_editor_map_data = local_map_data
	_emit_editor_map_loaded(local_map_data, local_map_data.resource_path)

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

func _create_default_world_map() -> WorldMapDataScript:
	var geology_data := WorldGeologyDataScript.new(
		"cobalt_world",
		Vector2(DEFAULT_WORLD_SIZE_M, DEFAULT_WORLD_SIZE_M)
	)
	return WorldMapDataScript.new("world_macro", geology_data)

func _cache_local_editor_map() -> void:
	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		return
	var local_map_data := map_loader.get_local_map_data()
	if local_map_data == null:
		return

	_local_editor_map_data = local_map_data
	_editor_map_active = true

func _emit_editor_map_loaded(map_data: Resource, path: String) -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_map_loaded", map_data, path)

func _emit_editor_map_saved(map_data: Resource, path: String) -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_map_saved", map_data, path)

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

func _current_map_is_world_map() -> bool:
	var map_loader := _resolve_map_loader()
	return map_loader != null and map_loader.is_world_map_loaded()

func _emit_mode_changed() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_mode_changed", _mode)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
