class_name BspRoomProcessor
extends RefCounted

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const GroundDataScript := preload("res://src/maps/ground_data.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const SPLIT_X: int = 0
const SPLIT_Z: int = 1
const EPSILON: float = 0.001
const SPLIT_STEP_M: float = 0.5

static func generate(data: BspModuleDataScript) -> BspModuleDataScript:
	var source := data if data != null else BspModuleDataScript.new()
	var result := _copy_config(source)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(maxi(source.seed, 0))

	var root := BspModuleDataScript.BspNode.new()
	root.id = &"root"
	root.bounds = _building_bounds(source)
	_split_node(root, 0, result, rng)

	result.root_node = root
	result.rooms.clear()
	result.partitions.clear()
	result.doors.clear()
	_gather_rooms(root, result.rooms)
	_gather_partitions(root, result)
	return result

static func compile_to_walls(data: BspModuleDataScript) -> Array[WallSegmentDataScript]:
	if data == null:
		return []

	var source := data if data.root_node != null else generate(data)
	var raw_walls := _raw_walls(source)
	var walls: Array[WallSegmentDataScript] = []
	for raw_wall in raw_walls:
		_append_wall_fragments(raw_wall, source, walls)

	return walls

static func compile_to_map_data(data: BspModuleDataScript) -> MapDataScript:
	var generated := generate(data)
	var grounds: Array[GroundDataScript] = [_ground_data(generated)]
	var walls: Array[WallSegmentDataScript] = compile_to_walls(generated)
	var objects: Array[WorldObjectDataScript] = [
		_player_data(generated),
		_npc_data(generated, walls),
	]
	return MapDataScript.new(generated.map_id, grounds, walls, objects)

static func _split_node(
	node: BspModuleDataScript.BspNode,
	depth: int,
	data: BspModuleDataScript,
	rng: RandomNumberGenerator
) -> void:
	if depth >= data.max_split_depth:
		return

	var axis := _choose_split_axis(node.bounds, data.min_room_size_m, rng)
	if axis == -1:
		return

	var split_position := _split_position(node.bounds, axis, data.min_room_size_m, rng)
	if axis == SPLIT_X:
		if split_position <= node.bounds.position.x + EPSILON:
			return
		if split_position >= node.bounds.position.x + node.bounds.size.x - EPSILON:
			return
	else:
		if split_position <= node.bounds.position.y + EPSILON:
			return
		if split_position >= node.bounds.position.y + node.bounds.size.y - EPSILON:
			return

	node.split_axis = axis
	node.split_position = split_position
	node.left_child = BspModuleDataScript.BspNode.new()
	node.right_child = BspModuleDataScript.BspNode.new()
	node.left_child.id = StringName("%s_l" % String(node.id))
	node.right_child.id = StringName("%s_r" % String(node.id))

	if axis == SPLIT_X:
		var left_width := split_position - node.bounds.position.x
		var right_width := node.bounds.size.x - left_width
		node.left_child.bounds = Rect2(node.bounds.position, Vector2(left_width, node.bounds.size.y))
		node.right_child.bounds = Rect2(
			Vector2(split_position, node.bounds.position.y),
			Vector2(right_width, node.bounds.size.y)
		)
	else:
		var top_depth := split_position - node.bounds.position.y
		var bottom_depth := node.bounds.size.y - top_depth
		node.left_child.bounds = Rect2(node.bounds.position, Vector2(node.bounds.size.x, top_depth))
		node.right_child.bounds = Rect2(
			Vector2(node.bounds.position.x, split_position),
			Vector2(node.bounds.size.x, bottom_depth)
		)

	_split_node(node.left_child, depth + 1, data, rng)
	_split_node(node.right_child, depth + 1, data, rng)

static func _choose_split_axis(bounds: Rect2, min_size_m: float, rng: RandomNumberGenerator) -> int:
	var can_split_x := bounds.size.x >= min_size_m * 2.0
	var can_split_z := bounds.size.y >= min_size_m * 2.0
	if not can_split_x and not can_split_z:
		return -1
	if can_split_x and not can_split_z:
		return SPLIT_X
	if can_split_z and not can_split_x:
		return SPLIT_Z
	if bounds.size.x > bounds.size.y * 1.35:
		return SPLIT_X
	if bounds.size.y > bounds.size.x * 1.35:
		return SPLIT_Z
	return SPLIT_X if rng.randi_range(0, 1) == 0 else SPLIT_Z

static func _split_position(
	bounds: Rect2,
	axis: int,
	min_size_m: float,
	rng: RandomNumberGenerator
) -> float:
	var start := bounds.position.x if axis == SPLIT_X else bounds.position.y
	var span := bounds.size.x if axis == SPLIT_X else bounds.size.y
	var low := start + min_size_m
	var high := start + span - min_size_m
	if is_equal_approx(low, high):
		return low

	var value := rng.randf_range(low, high)
	return clampf(snappedf(value, SPLIT_STEP_M), low, high)

static func _gather_rooms(node: BspModuleDataScript.BspNode, rooms: Array[BspModuleDataScript.BspRoom]) -> void:
	if node == null:
		return
	if node.is_leaf():
		var room := BspModuleDataScript.BspRoom.new()
		room.id = node.id
		room.bounds = node.bounds
		rooms.append(room)
		return

	_gather_rooms(node.left_child, rooms)
	_gather_rooms(node.right_child, rooms)

static func _gather_partitions(node: BspModuleDataScript.BspNode, data: BspModuleDataScript) -> void:
	if node == null or node.is_leaf():
		return

	var partition := BspModuleDataScript.BspPartition.new()
	partition.id = StringName("partition_%02d" % data.partitions.size())
	partition.axis = node.split_axis
	if node.split_axis == SPLIT_X:
		partition.start_position = Vector3(node.split_position, 0.0, node.bounds.position.y)
		partition.end_position = Vector3(
			node.split_position,
			0.0,
			node.bounds.position.y + node.bounds.size.y
		)
	else:
		partition.start_position = Vector3(node.bounds.position.x, 0.0, node.split_position)
		partition.end_position = Vector3(
			node.bounds.position.x + node.bounds.size.x,
			0.0,
			node.split_position
		)

	var door_position: Variant = _default_door_position(node, data.rooms, data.door_width_m, partition)
	data.partitions.append(partition)
	if door_position is Vector3:
		var door := BspModuleDataScript.BspDoor.new()
		door.id = StringName("door_%02d" % data.doors.size())
		door.partition_id = partition.id
		door.position = door_position as Vector3
		door.width_m = data.door_width_m
		data.doors.append(door)

	_gather_partitions(node.left_child, data)
	_gather_partitions(node.right_child, data)

static func _default_door_position(
	node: BspModuleDataScript.BspNode,
	rooms: Array[BspModuleDataScript.BspRoom],
	door_width_m: float,
	partition: BspModuleDataScript.BspPartition
) -> Variant:
	var best_center := 0.0
	var best_score := INF
	var has_candidate := false
	var partition_center := _segment_mid_axis(partition.start_position, partition.end_position, node.split_axis)

	for left_room in rooms:
		if not _room_touches_partition(left_room, node, true):
			continue
		for right_room in rooms:
			if not _room_touches_partition(right_room, node, false):
				continue
			var overlap := _room_overlap_along_partition(left_room, right_room, node.split_axis)
			if overlap.y - overlap.x < door_width_m + EPSILON:
				continue
			var center := (overlap.x + overlap.y) * 0.5
			var score := absf(center - partition_center)
			if score < best_score:
				best_score = score
				best_center = center
				has_candidate = true
				partition.left_room_id = left_room.id
				partition.right_room_id = right_room.id

	if not has_candidate:
		return null

	if node.split_axis == SPLIT_X:
		return Vector3(node.split_position, 0.0, best_center)
	return Vector3(best_center, 0.0, node.split_position)

static func _room_touches_partition(
	room: BspModuleDataScript.BspRoom,
	node: BspModuleDataScript.BspNode,
	is_left_side: bool
) -> bool:
	if node.split_axis == SPLIT_X:
		var edge := room.bounds.position.x + room.bounds.size.x if is_left_side else room.bounds.position.x
		return absf(edge - node.split_position) <= EPSILON

	var z_edge := room.bounds.position.y + room.bounds.size.y if is_left_side else room.bounds.position.y
	return absf(z_edge - node.split_position) <= EPSILON

static func _room_overlap_along_partition(
	left_room: BspModuleDataScript.BspRoom,
	right_room: BspModuleDataScript.BspRoom,
	axis: int
) -> Vector2:
	if axis == SPLIT_X:
		return Vector2(
			maxf(left_room.bounds.position.y, right_room.bounds.position.y),
			minf(
				left_room.bounds.position.y + left_room.bounds.size.y,
				right_room.bounds.position.y + right_room.bounds.size.y
			)
		)

	return Vector2(
		maxf(left_room.bounds.position.x, right_room.bounds.position.x),
		minf(
			left_room.bounds.position.x + left_room.bounds.size.x,
			right_room.bounds.position.x + right_room.bounds.size.x
		)
	)

static func _segment_mid_axis(start: Vector3, end: Vector3, split_axis: int) -> float:
	if split_axis == SPLIT_X:
		return (start.z + end.z) * 0.5
	return (start.x + end.x) * 0.5

static func _raw_walls(data: BspModuleDataScript) -> Array[Dictionary]:
	var walls: Array[Dictionary] = []
	var bounds := _building_bounds(data)
	var x0 := bounds.position.x
	var x1 := bounds.position.x + bounds.size.x
	var z0 := bounds.position.y
	var z1 := bounds.position.y + bounds.size.y
	walls.append(_raw_wall(&"", Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0)))
	walls.append(_raw_wall(&"", Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1)))
	walls.append(_raw_wall(&"", Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1)))
	walls.append(_raw_wall(&"", Vector3(x0, 0.0, z1), Vector3(x0, 0.0, z0)))

	for partition in data.partitions:
		walls.append(_raw_wall(partition.id, partition.start_position, partition.end_position))

	return walls

static func _raw_wall(partition_id: StringName, start: Vector3, end: Vector3) -> Dictionary:
	return {
		"partition_id": partition_id,
		"start": start,
		"end": end,
	}

static func _append_wall_fragments(
	raw_wall: Dictionary,
	data: BspModuleDataScript,
	walls: Array[WallSegmentDataScript]
) -> void:
	var start := raw_wall.get("start", Vector3.ZERO) as Vector3
	var end := raw_wall.get("end", Vector3.ZERO) as Vector3
	var partition_id := raw_wall.get("partition_id", &"") as StringName
	if start.distance_to(end) <= EPSILON:
		return

	var doors := _doors_for_partition(data, partition_id)
	if doors.is_empty():
		walls.append(_wall_data(start, end, data))
		return

	doors.sort_custom(func(a: BspModuleDataScript.BspDoor, b: BspModuleDataScript.BspDoor) -> bool:
		return start.distance_to(a.position) < start.distance_to(b.position)
	)

	var direction := (end - start).normalized()
	var current_start := start
	for door in doors:
		var half_width := maxf(door.width_m, data.door_width_m) * 0.5
		var door_start := door.position - (direction * half_width)
		var door_end := door.position + (direction * half_width)
		if _point_on_segment(door_start, start, end) and current_start.distance_to(door_start) > data.wall_thickness_m:
			walls.append(_wall_data(current_start, door_start, data))
		current_start = door_end

	if _point_on_segment(current_start, start, end) and current_start.distance_to(end) > data.wall_thickness_m:
		walls.append(_wall_data(current_start, end, data))

static func _doors_for_partition(
	data: BspModuleDataScript,
	partition_id: StringName
) -> Array[BspModuleDataScript.BspDoor]:
	var doors: Array[BspModuleDataScript.BspDoor] = []
	if partition_id == &"":
		return doors

	for door in data.doors:
		if door.partition_id == partition_id:
			doors.append(door)

	return doors

static func _point_on_segment(point: Vector3, start: Vector3, end: Vector3) -> bool:
	var total := start.distance_to(end)
	var split := start.distance_to(point) + point.distance_to(end)
	return absf(total - split) <= 0.01

static func _wall_data(start: Vector3, end: Vector3, data: BspModuleDataScript) -> WallSegmentDataScript:
	return WallSegmentDataScript.new(
		start,
		end,
		data.wall_height_m,
		data.wall_thickness_m,
		data.wall_color
	)

static func _ground_data(data: BspModuleDataScript) -> GroundDataScript:
	var building_size := _building_bounds(data).size
	return GroundDataScript.new(
		&"Ground",
		Vector3(0.0, data.ground_thickness_m * -0.5, 0.0),
		Vector3(
			building_size.x + (data.ground_buffer_m * 2.0),
			data.ground_thickness_m,
			building_size.y + (data.ground_buffer_m * 2.0)
		),
		data.ground_color
	)

static func _player_data(data: BspModuleDataScript) -> WorldObjectDataScript:
	return WorldObjectDataScript.new(
		&"pc_001",
		&"player_character",
		_player_spawn_position(data),
		data.actor_size_m,
		data.player_color
	)

static func _npc_data(
	data: BspModuleDataScript,
	walls: Array[WallSegmentDataScript]
) -> WorldObjectDataScript:
	return WorldObjectDataScript.new(
		&"npc_001",
		&"non_player_character",
		_npc_spawn_position(data, walls),
		data.actor_size_m,
		data.npc_color
	)

static func _player_spawn_position(data: BspModuleDataScript) -> Vector3:
	if data.rooms.is_empty():
		return Vector3.ZERO

	var best_room: BspModuleDataScript.BspRoom = data.rooms[0]
	var best_area := best_room.bounds.size.x * best_room.bounds.size.y
	for room in data.rooms:
		var area := room.bounds.size.x * room.bounds.size.y
		if area > best_area:
			best_room = room
			best_area = area
	return best_room.center_position()

static func _npc_spawn_position(
	data: BspModuleDataScript,
	walls: Array[WallSegmentDataScript]
) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(maxi(data.seed + 9151, 0))
	var ground_bounds := _ground_bounds(data)
	var margin := maxf(data.actor_size_m.x, data.actor_size_m.z) * 0.5
	var pc_position := _player_spawn_position(data)

	for _attempt in range(data.npc_spawn_attempts):
		var position := Vector3(
			rng.randf_range(ground_bounds.position.x + margin, ground_bounds.end.x - margin),
			0.0,
			rng.randf_range(ground_bounds.position.y + margin, ground_bounds.end.y - margin)
		)
		if position.distance_to(pc_position) < 1.0:
			continue
		if _distance_to_walls(position, walls) >= data.npc_wall_clearance_m:
			return position

	return Vector3(ground_bounds.position.x + margin, 0.0, ground_bounds.position.y + margin)

static func _distance_to_walls(position: Vector3, walls: Array[WallSegmentDataScript]) -> float:
	var best := INF
	var point := Vector2(position.x, position.z)
	for wall in walls:
		best = minf(best, _point_to_segment_distance_2d(
			point,
			Vector2(wall.start_position.x, wall.start_position.z),
			Vector2(wall.end_position.x, wall.end_position.z)
		))
	return best

static func _point_to_segment_distance_2d(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= EPSILON:
		return point.distance_to(start)

	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + (segment * t))

static func _copy_config(source: BspModuleDataScript) -> BspModuleDataScript:
	var result := BspModuleDataScript.new()
	result.map_id = source.map_id
	result.building_size_m = source.building_size_m
	result.min_room_size_m = source.min_room_size_m
	result.max_split_depth = source.max_split_depth
	result.seed = source.seed
	result.ground_buffer_m = source.ground_buffer_m
	result.door_width_m = source.door_width_m
	result.wall_height_m = source.wall_height_m
	result.wall_thickness_m = source.wall_thickness_m
	result.ground_thickness_m = source.ground_thickness_m
	result.npc_wall_clearance_m = source.npc_wall_clearance_m
	result.npc_spawn_attempts = source.npc_spawn_attempts
	result.wall_color = source.wall_color
	result.ground_color = source.ground_color
	result.player_color = source.player_color
	result.npc_color = source.npc_color
	result.actor_size_m = source.actor_size_m
	return result

static func _building_bounds(data: BspModuleDataScript) -> Rect2:
	var size := Vector2(
		maxf(data.building_size_m.x, data.min_room_size_m * 2.0),
		maxf(data.building_size_m.y, data.min_room_size_m * 2.0)
	)
	return Rect2(size * -0.5, size)

static func _ground_bounds(data: BspModuleDataScript) -> Rect2:
	var building_size := _building_bounds(data).size
	var ground_size := Vector2(
		building_size.x + (data.ground_buffer_m * 2.0),
		building_size.y + (data.ground_buffer_m * 2.0)
	)
	return Rect2(ground_size * -0.5, ground_size)
