class_name BspBuildingGenerator
extends RefCounted

const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")

const DEFAULT_WIDTH_M: float = 10.0
const DEFAULT_DEPTH_M: float = 8.0
const DEFAULT_MIN_ROOM_SIZE_M: float = 2.0
const DEFAULT_TARGET_ROOM_COUNT: int = 5
const DEFAULT_SEED: int = 1
const DEFAULT_WALL_HEIGHT_M: float = 2.2
const DEFAULT_WALL_THICKNESS_M: float = 0.18
const DEFAULT_WALL_COLOR: Color = Color(0.35, 0.34, 0.32, 1.0)
const DEFAULT_DOOR_WIDTH_M: float = 1.0
const DEFAULT_DOOR_SOCKET_COLOR: Color = Color(0.82, 0.9, 0.84, 1.0)
const DOOR_EDGE_CLEARANCE_M: float = 0.5
const MIN_WALL_SEGMENT_M: float = 0.01

static func default_parameters() -> Dictionary:
	return {
		"width_m": DEFAULT_WIDTH_M,
		"depth_m": DEFAULT_DEPTH_M,
		"min_room_size_m": DEFAULT_MIN_ROOM_SIZE_M,
		"target_room_count": DEFAULT_TARGET_ROOM_COUNT,
		"seed": DEFAULT_SEED,
		"wall_height_m": DEFAULT_WALL_HEIGHT_M,
		"wall_thickness_m": DEFAULT_WALL_THICKNESS_M,
		"wall_color": DEFAULT_WALL_COLOR,
		"door_width_m": DEFAULT_DOOR_WIDTH_M,
		"door_socket_color": DEFAULT_DOOR_SOCKET_COLOR,
	}

static func generate(origin: Vector3, parameters: Dictionary = {}) -> Dictionary:
	var clean_parameters := _clean_parameters(parameters)
	var width_m := float(clean_parameters.get("width_m", DEFAULT_WIDTH_M))
	var depth_m := float(clean_parameters.get("depth_m", DEFAULT_DEPTH_M))
	var min_room_size_m := float(clean_parameters.get("min_room_size_m", DEFAULT_MIN_ROOM_SIZE_M))
	var target_room_count := int(clean_parameters.get("target_room_count", DEFAULT_TARGET_ROOM_COUNT))
	var door_width_m := float(clean_parameters.get("door_width_m", DEFAULT_DOOR_WIDTH_M))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(clean_parameters.get("seed", DEFAULT_SEED))

	var half_width := width_m * 0.5
	var half_depth := depth_m * 0.5
	var root_rect := {
		"min_x": origin.x - half_width,
		"max_x": origin.x + half_width,
		"min_z": origin.z - half_depth,
		"max_z": origin.z + half_depth,
	}
	var leaves: Array[Dictionary] = [root_rect]
	var partitions: Array[Dictionary] = []

	while leaves.size() < target_room_count:
		var candidate_indices := _split_candidate_indices(leaves, min_room_size_m)
		if candidate_indices.is_empty():
			break

		var leaf_index := _choose_split_candidate(leaves, candidate_indices, rng)
		var split := _split_rect(leaves[leaf_index], min_room_size_m, rng)
		if split.is_empty():
			break

		leaves.remove_at(leaf_index)
		leaves.append(split.get("a", {}))
		leaves.append(split.get("b", {}))
		partitions.append(split.get("partition", {}))

	var walls: Array[WallDataScript] = []
	var door_sockets: Array[DoorSocketDataScript] = []
	_append_outer_walls(walls, door_sockets, root_rect, clean_parameters, rng)
	for partition in partitions:
		_append_partition_wall(walls, door_sockets, partition, clean_parameters)

	return {
		"origin": Vector3(origin.x, 0.0, origin.z),
		"bounds": root_rect,
		"rooms": _rooms_from_leaves(leaves),
		"walls": walls,
		"door_sockets": door_sockets,
	}

static func _clean_parameters(parameters: Dictionary) -> Dictionary:
	var width_m := clampf(float(parameters.get("width_m", DEFAULT_WIDTH_M)), 4.0, 24.0)
	var depth_m := clampf(float(parameters.get("depth_m", DEFAULT_DEPTH_M)), 4.0, 24.0)
	var min_room_size_m := clampf(
		float(parameters.get("min_room_size_m", DEFAULT_MIN_ROOM_SIZE_M)),
		1.0,
		6.0
	)
	var shortest_side := minf(width_m, depth_m)
	min_room_size_m = minf(min_room_size_m, maxf(1.0, shortest_side * 0.5))
	return {
		"width_m": width_m,
		"depth_m": depth_m,
		"min_room_size_m": min_room_size_m,
		"target_room_count": clampi(int(parameters.get("target_room_count", DEFAULT_TARGET_ROOM_COUNT)), 1, 16),
		"seed": max(1, int(parameters.get("seed", DEFAULT_SEED))),
		"wall_height_m": clampf(float(parameters.get("wall_height_m", DEFAULT_WALL_HEIGHT_M)), 0.25, 8.0),
		"wall_thickness_m": clampf(float(parameters.get("wall_thickness_m", DEFAULT_WALL_THICKNESS_M)), 0.05, 2.0),
		"wall_color": parameters.get("wall_color", DEFAULT_WALL_COLOR),
		"door_width_m": clampf(float(parameters.get("door_width_m", DEFAULT_DOOR_WIDTH_M)), 0.5, 3.0),
		"door_socket_color": parameters.get("door_socket_color", DEFAULT_DOOR_SOCKET_COLOR),
	}

static func _split_candidate_indices(leaves: Array[Dictionary], min_room_size_m: float) -> Array[int]:
	var candidates: Array[int] = []
	for index in range(leaves.size()):
		if _can_split_rect(leaves[index], min_room_size_m):
			candidates.append(index)
	return candidates

static func _choose_split_candidate(
	leaves: Array[Dictionary],
	candidate_indices: Array[int],
	rng: RandomNumberGenerator
) -> int:
	var largest_area := 0.0
	var largest_indices: Array[int] = []
	for candidate_index in candidate_indices:
		var area := _rect_width(leaves[candidate_index]) * _rect_depth(leaves[candidate_index])
		if area > largest_area + 0.001:
			largest_area = area
			largest_indices = [candidate_index]
		elif is_equal_approx(area, largest_area):
			largest_indices.append(candidate_index)

	if largest_indices.is_empty():
		return candidate_indices[0]

	return largest_indices[rng.randi_range(0, largest_indices.size() - 1)]

static func _can_split_rect(rect: Dictionary, min_room_size_m: float) -> bool:
	return (
		_rect_width(rect) >= min_room_size_m * 2.0
		or _rect_depth(rect) >= min_room_size_m * 2.0
	)

static func _split_rect(rect: Dictionary, min_room_size_m: float, rng: RandomNumberGenerator) -> Dictionary:
	var can_split_vertical := _rect_width(rect) >= min_room_size_m * 2.0
	var can_split_horizontal := _rect_depth(rect) >= min_room_size_m * 2.0
	if not can_split_vertical and not can_split_horizontal:
		return {}

	var split_vertical := can_split_vertical
	if can_split_vertical and can_split_horizontal:
		var width_m := _rect_width(rect)
		var depth_m := _rect_depth(rect)
		if width_m > depth_m * 1.25:
			split_vertical = true
		elif depth_m > width_m * 1.25:
			split_vertical = false
		else:
			split_vertical = rng.randi_range(0, 1) == 0
	elif can_split_horizontal:
		split_vertical = false

	if split_vertical:
		var split_x := rng.randf_range(
			float(rect.get("min_x")) + min_room_size_m,
			float(rect.get("max_x")) - min_room_size_m
		)
		var door_z := _door_coordinate(
			float(rect.get("min_z")),
			float(rect.get("max_z")),
			DEFAULT_DOOR_WIDTH_M,
			rng
		)
		return {
			"a": {
				"min_x": rect.get("min_x"),
				"max_x": split_x,
				"min_z": rect.get("min_z"),
				"max_z": rect.get("max_z"),
			},
			"b": {
				"min_x": split_x,
				"max_x": rect.get("max_x"),
				"min_z": rect.get("min_z"),
				"max_z": rect.get("max_z"),
			},
			"partition": {
				"start": Vector3(split_x, 0.0, float(rect.get("min_z"))),
				"end": Vector3(split_x, 0.0, float(rect.get("max_z"))),
				"door_position": Vector3(split_x, 0.0, door_z),
			},
		}

	var split_z := rng.randf_range(
		float(rect.get("min_z")) + min_room_size_m,
		float(rect.get("max_z")) - min_room_size_m
	)
	var door_x := _door_coordinate(
		float(rect.get("min_x")),
		float(rect.get("max_x")),
		DEFAULT_DOOR_WIDTH_M,
		rng
	)
	return {
		"a": {
			"min_x": rect.get("min_x"),
			"max_x": rect.get("max_x"),
			"min_z": rect.get("min_z"),
			"max_z": split_z,
		},
		"b": {
			"min_x": rect.get("min_x"),
			"max_x": rect.get("max_x"),
			"min_z": split_z,
			"max_z": rect.get("max_z"),
		},
		"partition": {
			"start": Vector3(float(rect.get("min_x")), 0.0, split_z),
			"end": Vector3(float(rect.get("max_x")), 0.0, split_z),
			"door_position": Vector3(door_x, 0.0, split_z),
		},
	}

static func _append_outer_walls(
	walls: Array[WallDataScript],
	door_sockets: Array[DoorSocketDataScript],
	rect: Dictionary,
	parameters: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	var min_x := float(rect.get("min_x"))
	var max_x := float(rect.get("max_x"))
	var min_z := float(rect.get("min_z"))
	var max_z := float(rect.get("max_z"))
	var edges := [
		{
			"start": Vector3(min_x, 0.0, min_z),
			"end": Vector3(max_x, 0.0, min_z),
		},
		{
			"start": Vector3(max_x, 0.0, min_z),
			"end": Vector3(max_x, 0.0, max_z),
		},
		{
			"start": Vector3(max_x, 0.0, max_z),
			"end": Vector3(min_x, 0.0, max_z),
		},
		{
			"start": Vector3(min_x, 0.0, max_z),
			"end": Vector3(min_x, 0.0, min_z),
		},
	]
	var door_edge_index := rng.randi_range(0, edges.size() - 1)
	for edge_index in range(edges.size()):
		var edge: Dictionary = edges[edge_index]
		if edge_index == door_edge_index:
			var door_position := _segment_midpoint(edge.get("start"), edge.get("end"))
			_append_wall_with_door(
				walls,
				door_sockets,
				edge.get("start"),
				edge.get("end"),
				door_position,
				parameters
			)
		else:
			_append_wall(walls, edge.get("start"), edge.get("end"), parameters)

static func _append_partition_wall(
	walls: Array[WallDataScript],
	door_sockets: Array[DoorSocketDataScript],
	partition: Dictionary,
	parameters: Dictionary
) -> void:
	_append_wall_with_door(
		walls,
		door_sockets,
		partition.get("start", Vector3.ZERO),
		partition.get("end", Vector3.ZERO),
		partition.get("door_position", Vector3.ZERO),
		parameters
	)

static func _append_wall_with_door(
	walls: Array[WallDataScript],
	door_sockets: Array[DoorSocketDataScript],
	start_position: Vector3,
	end_position: Vector3,
	door_position: Vector3,
	parameters: Dictionary
) -> void:
	var direction := end_position - start_position
	var length := direction.length()
	if length <= MIN_WALL_SEGMENT_M:
		return

	direction /= length
	var door_width_m := minf(float(parameters.get("door_width_m", DEFAULT_DOOR_WIDTH_M)), maxf(0.1, length - 0.1))
	var half_width := door_width_m * 0.5
	var clean_door_position := _project_point_to_segment(door_position, start_position, end_position)
	clean_door_position = _clamp_door_position(clean_door_position, start_position, end_position, half_width)
	var gap_start := clean_door_position - (direction * half_width)
	var gap_end := clean_door_position + (direction * half_width)
	_append_wall(walls, start_position, gap_start, parameters)
	_append_wall(walls, gap_end, end_position, parameters)
	door_sockets.append(DoorSocketDataScript.new(
		&"",
		clean_door_position,
		door_width_m,
		atan2(direction.x, direction.z),
		parameters.get("door_socket_color", DEFAULT_DOOR_SOCKET_COLOR)
	))

static func _append_wall(
	walls: Array[WallDataScript],
	start_position: Vector3,
	end_position: Vector3,
	parameters: Dictionary
) -> void:
	if start_position.distance_to(end_position) <= MIN_WALL_SEGMENT_M:
		return

	walls.append(WallDataScript.new(
		Vector3(start_position.x, 0.0, start_position.z),
		Vector3(end_position.x, 0.0, end_position.z),
		float(parameters.get("wall_height_m", DEFAULT_WALL_HEIGHT_M)),
		float(parameters.get("wall_thickness_m", DEFAULT_WALL_THICKNESS_M)),
		parameters.get("wall_color", DEFAULT_WALL_COLOR)
	))

static func _door_coordinate(
	min_value: float,
	max_value: float,
	door_width_m: float,
	rng: RandomNumberGenerator
) -> float:
	var half_width := door_width_m * 0.5
	var low := min_value + half_width + DOOR_EDGE_CLEARANCE_M
	var high := max_value - half_width - DOOR_EDGE_CLEARANCE_M
	if low >= high:
		return (min_value + max_value) * 0.5

	return rng.randf_range(low, high)

static func _clamp_door_position(
	door_position: Vector3,
	start_position: Vector3,
	end_position: Vector3,
	half_width: float
) -> Vector3:
	var direction := end_position - start_position
	var length := direction.length()
	if length <= MIN_WALL_SEGMENT_M:
		return door_position

	direction /= length
	var distance_along := (door_position - start_position).dot(direction)
	var clamped_distance := clampf(distance_along, half_width, maxf(half_width, length - half_width))
	return start_position + (direction * clamped_distance)

static func _project_point_to_segment(point: Vector3, start_position: Vector3, end_position: Vector3) -> Vector3:
	var direction := end_position - start_position
	var length_squared := direction.length_squared()
	if length_squared <= 0.000001:
		return start_position

	var t := clampf((point - start_position).dot(direction) / length_squared, 0.0, 1.0)
	return start_position + (direction * t)

static func _rooms_from_leaves(leaves: Array[Dictionary]) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	for index in range(leaves.size()):
		var leaf := leaves[index]
		rooms.append({
			"room_index": index,
			"min_x": leaf.get("min_x"),
			"max_x": leaf.get("max_x"),
			"min_z": leaf.get("min_z"),
			"max_z": leaf.get("max_z"),
			"center": Vector3(
				(float(leaf.get("min_x")) + float(leaf.get("max_x"))) * 0.5,
				0.0,
				(float(leaf.get("min_z")) + float(leaf.get("max_z"))) * 0.5
			),
			"size": Vector2(_rect_width(leaf), _rect_depth(leaf)),
		})
	return rooms

static func _rect_width(rect: Dictionary) -> float:
	return float(rect.get("max_x")) - float(rect.get("min_x"))

static func _rect_depth(rect: Dictionary) -> float:
	return float(rect.get("max_z")) - float(rect.get("min_z"))

static func _segment_midpoint(start_position: Vector3, end_position: Vector3) -> Vector3:
	return (start_position + end_position) * 0.5
