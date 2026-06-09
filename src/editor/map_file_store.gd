class_name MapFileStore
extends RefCounted

const GroundDataScript := preload("res://src/environment/ground_data.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")

const LOCAL_MAP_DIRECTORY := "res://data/editor_maps"
const WORLD_MAP_DIRECTORY := "res://data/world_maps"
const MAP_DIRECTORY := LOCAL_MAP_DIRECTORY
const DEFAULT_FILENAME := "editor_map"
const BLANK_EDITOR_MAP_ID := "editor_blank"
const ALLOWED_FILENAME_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

func create_blank_editor_map() -> MapDataScript:
	var grounds: Array[GroundDataScript] = []
	grounds.append(GroundDataScript.new(
		&"editor_ground",
		Vector3(0.0, -0.05, 0.0),
		Vector3(12.0, 0.1, 12.0),
		Color(0.18, 0.21, 0.19, 1.0)
	))
	return MapDataScript.new(BLANK_EDITOR_MAP_ID, grounds, [], [])

func save_map(map_data: MapDataScript, requested_name: String) -> String:
	return save_local_map(map_data, requested_name)

func save_local_map(map_data: MapDataScript, requested_name: String) -> String:
	return _save_typed_map(map_data, requested_name, LOCAL_MAP_DIRECTORY, false)

func save_world_map(map_data: MapDataScript, requested_name: String) -> String:
	return _save_typed_map(map_data, requested_name, WORLD_MAP_DIRECTORY, true)

func load_map(requested_name: String) -> MapDataScript:
	return load_local_map(requested_name)

func load_local_map(requested_name: String) -> MapDataScript:
	return _load_typed_map(requested_name, LOCAL_MAP_DIRECTORY, false)

func load_world_map(requested_name: String) -> MapDataScript:
	return _load_typed_map(requested_name, WORLD_MAP_DIRECTORY, true)

func map_path_for_name(requested_name: String) -> String:
	return local_map_path_for_name(requested_name)

func local_map_path_for_name(requested_name: String) -> String:
	return _map_path_for_name(requested_name, LOCAL_MAP_DIRECTORY)

func world_map_path_for_name(requested_name: String) -> String:
	return _map_path_for_name(requested_name, WORLD_MAP_DIRECTORY)

func sanitize_filename(requested_name: String) -> String:
	var basename := requested_name.strip_edges().replace("\\", "/").get_file()
	if basename.ends_with(".tres"):
		basename = basename.get_basename()

	var parts: PackedStringArray = []
	for index in range(basename.length()):
		var character := basename.substr(index, 1)
		if ALLOWED_FILENAME_CHARS.contains(character):
			parts.append(character.to_lower())
		elif character == " " or character == ".":
			parts.append("_")

	var sanitized := "".join(parts).strip_edges()
	return DEFAULT_FILENAME if sanitized.is_empty() else sanitized

func _save_typed_map(
	map_data: MapDataScript,
	requested_name: String,
	directory: String,
	should_be_world_map: bool
) -> String:
	if map_data == null or _is_world_map(map_data) != should_be_world_map:
		return ""
	if _ensure_map_directory(directory) != OK:
		return ""

	var path := _map_path_for_name(requested_name, directory)
	var result := ResourceSaver.save(map_data, path)
	return path if result == OK else ""

func _load_typed_map(
	requested_name: String,
	directory: String,
	should_be_world_map: bool
) -> MapDataScript:
	var path := _map_path_for_name(requested_name, directory)
	if not ResourceLoader.exists(path):
		return null

	var map_data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapDataScript
	if map_data == null or _is_world_map(map_data) != should_be_world_map:
		return null

	return map_data

func _map_path_for_name(requested_name: String, directory: String) -> String:
	return "%s/%s.tres" % [directory, sanitize_filename(requested_name)]

func _is_world_map(map_data: MapDataScript) -> bool:
	return map_data != null and map_data.world_geology != null

func _ensure_map_directory(directory: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
