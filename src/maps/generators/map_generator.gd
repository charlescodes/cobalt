class_name MapGenerator
extends Resource

const MapDataScript := preload("res://src/maps/map_data.gd")

@export var generator_id: StringName = &""
@export var enabled: bool = true

func generate(input_map_data: MapDataScript) -> MapDataScript:
	return input_map_data
