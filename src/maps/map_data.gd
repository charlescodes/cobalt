class_name MapData
extends Resource

const GroundDataScript := preload("res://src/environment/ground_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

@export var map_id: String = ""
@export var grounds: Array[GroundDataScript] = []
@export var static_walls: Array[WallDataScript] = []
@export var door_sockets: Array[DoorSocketDataScript] = []
@export var world_objects: Array[WorldObjectDataScript] = []

func _init(
	p_map_id: String = "",
	p_grounds: Array[GroundDataScript] = [],
	p_static_walls: Array[WallDataScript] = [],
	p_world_objects: Array[WorldObjectDataScript] = [],
	p_door_sockets: Array[DoorSocketDataScript] = []
) -> void:
	map_id = p_map_id
	grounds = p_grounds
	static_walls = p_static_walls
	world_objects = p_world_objects
	door_sockets = p_door_sockets
