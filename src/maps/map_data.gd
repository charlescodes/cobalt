class_name MapData
extends Resource

const GroundDataScript := preload("res://src/maps/ground_data.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

@export var map_id: String = ""
@export var grounds: Array[GroundDataScript] = []
@export var static_walls: Array[WallSegmentDataScript] = []
@export var world_objects: Array[WorldObjectDataScript] = []

func _init(
	p_map_id: String = "",
	p_grounds: Array[GroundDataScript] = [],
	p_static_walls: Array[WallSegmentDataScript] = [],
	p_world_objects: Array[WorldObjectDataScript] = []
) -> void:
	map_id = p_map_id
	grounds = p_grounds
	static_walls = p_static_walls
	world_objects = p_world_objects
