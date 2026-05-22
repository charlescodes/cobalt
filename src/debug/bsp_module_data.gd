class_name BspModuleData
extends Resource

class BspNode:
	extends RefCounted

	var id: StringName = &""
	var bounds: Rect2 = Rect2()
	var split_axis: int = -1
	var split_position: float = 0.0
	var left_child: BspNode
	var right_child: BspNode

	func is_leaf() -> bool:
		return left_child == null and right_child == null

class BspRoom:
	extends RefCounted

	var id: StringName = &""
	var bounds: Rect2 = Rect2()

	func center_position() -> Vector3:
		var center := bounds.position + (bounds.size * 0.5)
		return Vector3(center.x, 0.0, center.y)

class BspPartition:
	extends RefCounted

	var id: StringName = &""
	var axis: int = -1
	var start_position: Vector3 = Vector3.ZERO
	var end_position: Vector3 = Vector3.ZERO
	var left_room_id: StringName = &""
	var right_room_id: StringName = &""

class BspDoor:
	extends RefCounted

	var id: StringName = &""
	var partition_id: StringName = &""
	var position: Vector3 = Vector3.ZERO
	var width_m: float = 1.0
	var is_exterior_exit: bool = false

@export var map_id: String = "bsp_debug"
@export var building_size_m: Vector2 = Vector2(18.0, 14.0)
@export_range(2.0, 12.0, 0.25) var min_room_size_m: float = 4.0
@export_range(1, 8, 1) var max_split_depth: int = 3
@export var seed: int = 1337
@export_range(0.0, 8.0, 0.25) var ground_buffer_m: float = 2.0
@export_range(0.5, 3.0, 0.1) var door_width_m: float = 1.0
@export var exterior_exit_side: StringName = &"south"
@export_range(0.25, 8.0, 0.05) var wall_height_m: float = 2.2
@export_range(0.05, 2.0, 0.01) var wall_thickness_m: float = 0.18
@export_range(0.05, 1.0, 0.01) var ground_thickness_m: float = 0.1
@export_range(0.1, 2.0, 0.05) var npc_wall_clearance_m: float = 0.7
@export_range(1, 256, 1) var npc_spawn_attempts: int = 64
@export var wall_color: Color = Color(0.34, 0.33, 0.31, 1.0)
@export var ground_color: Color = Color(0.19, 0.22, 0.2, 1.0)
@export var player_color: Color = Color(0.1, 0.25, 1.0, 1.0)
@export var npc_color: Color = Color(0.45, 0.45, 0.45, 1.0)
@export var actor_size_m: Vector3 = Vector3(0.5, 1.83, 0.5)

var root_node: BspNode
var rooms: Array[BspRoom] = []
var partitions: Array[BspPartition] = []
var doors: Array[BspDoor] = []
