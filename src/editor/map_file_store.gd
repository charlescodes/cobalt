class_name MapFileStore
extends RefCounted

const GroundDataScript := preload("res://src/environment/ground_data.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")

const MAP_DIRECTORY := "res://data/editor_maps"
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
	if map_data == null:
		return ""
	if _ensure_map_directory() != OK:
		return ""

	var path := map_path_for_name(requested_name)
	var result := ResourceSaver.save(map_data, path)
	return path if result == OK else ""

func load_map(requested_name: String) -> MapDataScript:
	var path := map_path_for_name(requested_name)
	if not ResourceLoader.exists(path):
		return null

	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapDataScript

func map_path_for_name(requested_name: String) -> String:
	return "%s/%s.tres" % [MAP_DIRECTORY, sanitize_filename(requested_name)]

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

func _ensure_map_directory() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAP_DIRECTORY))
