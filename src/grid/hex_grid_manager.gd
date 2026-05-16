class_name HexGridManager
extends Node3D

const HexDataScript := preload("res://src/grid/hex_data.gd")
const HexViewScript := preload("res://src/grid/hex_view.gd")

@export_range(1, 128, 1) var width: int = 6
@export_range(1, 128, 1) var length: int = 6
@export var default_terrain_id: StringName = &"grass"
@export var default_walkable: bool = true
@export var generate_on_ready: bool = true

var _hexes: Dictionary = {}

func _ready() -> void:
	if generate_on_ready:
		build_grid()

func build_grid() -> Dictionary:
	clear_hex_views()
	_hexes = generate_hex_data(width, length, default_terrain_id, default_walkable)
	instantiate_hex_views(_hexes, self)
	return _hexes

func get_hexes() -> Dictionary:
	return _hexes

static func generate_hex_data(
	map_width: int,
	map_length: int,
	terrain_id: StringName = &"grass",
	is_walkable: bool = true
) -> Dictionary:
	var hexes: Dictionary = {}
	if map_width <= 0 or map_length <= 0:
		return hexes

	for q in range(map_width):
		for r in range(map_length):
			var data := HexDataScript.new(q, r, -q - r, terrain_id, is_walkable)
			hexes[data.key()] = data

	return hexes

static func instantiate_hex_views(hexes: Dictionary, parent: Node3D) -> void:
	for data: HexDataScript in hexes.values():
		var view := HexViewScript.new()
		view.hex_data = data
		parent.add_child(view)
		view.apply_data()

func clear_hex_views() -> void:
	for child in get_children():
		if child is HexViewScript:
			child.queue_free()
