class_name BspRoomProcessor
extends RefCounted

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const EditorSnappingResolverScript := preload("res://src/editor/editor_snapping_resolver.gd")
const GroundDataScript := preload("res://src/maps/ground_data.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const SPLIT_X: int = 0
const SPLIT_Z: int = 1
const EPSILON: float = 0.001
const SPLIT_STEP_M: float = 0.5
const EDIT_SNAP_M: float = EditorSnappingResolverScript.DEFAULT_STEP_M
const SIDE_PICK_DISTANCE_M: float = 0.75
const PERIMETER_NORTH: StringName = &"perimeter_north"
const PERIMETER_EAST: StringName = &"perimeter_east"
const PERIMETER_SOUTH: StringName = &"perimeter_south"
const PERIMETER_WEST: StringName = &"perimeter_west"

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
	_add_exterior_exit(result)
	return result

static func compile_to_walls(data: BspModuleDataScript) -> Array[WallSegmentDataScript]:
	if data == null:
		return []

	var source := _generated_source(data)
	var raw_walls := _raw_walls(source)
	var walls: Array[WallSegmentDataScript] = []
	for raw_wall in raw_walls:
		_append_wall_fragments(raw_wall, source, walls)

	return walls

static func compile_to_map_data(data: BspModuleDataScript) -> MapDataScript:
	var generated := _generated_source(data)
	var grounds: Array[GroundDataScript] = [_ground_data(generated)]
	var walls: Array[WallSegmentDataScript] = compile_to_walls(generated)
	var objects: Array[WorldObjectDataScript] = [
		_player_data(generated),
		_npc_data(generated, walls),
	]
	return MapDataScript.new(generated.map_id, grounds, walls, objects)

static func room_at_position(
	data: BspModuleDataScript,
	position: Vector3
) -> BspModuleDataScript.BspRoom:
	var source := _generated_source(data)
	var point := Vector2(position.x, position.z)
	for room in source.rooms:
		if _rect_has_point_inclusive(room.bounds, point):
			return room

	return null

static func nearest_room_side(
	data: BspModuleDataScript,
	room_id: StringName,
	position: Vector3,
	max_distance_m: float = SIDE_PICK_DISTANCE_M
) -> Dictionary:
	var source := _generated_source(data)
	var room := _room_by_id(source, room_id)
	if room == null:
		return _failure_result(&"room_not_found")

	var candidates := [
		_room_side_result(source, room, &"north", position),
		_room_side_result(source, room, &"east", position),
		_room_side_result(source, room, &"south", position),
		_room_side_result(source, room, &"west", position),
	]
	var best := {}
	var best_distance := INF
	for candidate in candidates:
		var distance := float(candidate.get("distance_m", INF))
		if distance < best_distance:
			best = candidate
			best_distance = distance

	if best.is_empty() or best_distance > max_distance_m:
		return _failure_result(&"side_not_found")

	best["ok"] = true
	return best

static func nearest_resizable_room_side(
	data: BspModuleDataScript,
	position: Vector3,
	max_distance_m: float = SIDE_PICK_DISTANCE_M
) -> Dictionary:
	var source := _generated_source(data)
	var best := {}
	var best_distance := INF
	for room in source.rooms:
		for side in [&"north", &"east", &"south", &"west"]:
			var candidate := _room_side_result(source, room, side, position)
			if (candidate.get("partition_id", &"") as StringName) == &"":
				continue
			if bool(candidate.get("is_perimeter", false)):
				continue

			var distance := float(candidate.get("distance_m", INF))
			if distance < best_distance:
				best = candidate
				best_distance = distance

	if best.is_empty() or best_distance > max_distance_m:
		return _failure_result(&"side_not_found")

	best["ok"] = true
	return best

static func nearest_resizable_room_side_for_room(
	data: BspModuleDataScript,
	room_id: StringName,
	position: Vector3,
	max_distance_m: float = SIDE_PICK_DISTANCE_M
) -> Dictionary:
	var source := _generated_source(data)
	var room := _room_by_id(source, room_id)
	if room == null:
		return _failure_result(&"room_not_found")

	var best := {}
	var best_distance := INF
	for side in [&"north", &"east", &"south", &"west"]:
		var candidate := _room_side_result(source, room, side, position)
		if (candidate.get("partition_id", &"") as StringName) == &"":
			continue
		if bool(candidate.get("is_perimeter", false)):
			continue

		var distance := float(candidate.get("distance_m", INF))
		if distance < best_distance:
			best = candidate
			best_distance = distance

	if best.is_empty() or best_distance > max_distance_m:
		return _failure_result(&"side_not_found")

	best["ok"] = true
	return best

static func room_side_info(
	data: BspModuleDataScript,
	room_id: StringName,
	side: StringName
) -> Dictionary:
	var source := _generated_source(data)
	var room := _room_by_id(source, room_id)
	if room == null:
		return _failure_result(&"room_not_found")

	var side_position: Variant = _room_side_center(room, side)
	if side_position == null:
		return _failure_result(&"invalid_side")

	var result := _room_side_result(source, room, side, side_position as Vector3)
	result["ok"] = true
	return result

static func toggle_manual_door_at_position(
	data: BspModuleDataScript,
	room_id: StringName,
	position: Vector3,
	max_distance_m: float = SIDE_PICK_DISTANCE_M
) -> Dictionary:
	if data == null or data.root_node == null:
		return _failure_result(&"no_generated_bsp")

	var manual_door := _manual_door_near_room(data, room_id, position, max_distance_m)
	if manual_door != null:
		var removed_id := manual_door.id
		data.doors.erase(manual_door)
		return {
			"ok": true,
			"action": &"removed",
			"door_id": removed_id,
		}

	var side_info := nearest_room_side(data, room_id, position, max_distance_m)
	if not bool(side_info.get("ok", false)):
		return side_info

	var partition_id := side_info.get("partition_id", &"") as StringName
	if partition_id == &"":
		return _failure_result(&"side_without_partition")

	var wall := _raw_wall_for_partition(data, partition_id)
	if wall.is_empty():
		return _failure_result(&"wall_not_found")

	var door_width := maxf(data.door_width_m, 0.1)
	var snapped_position: Variant = _snapped_door_position_on_wall(
		position,
		wall.get("start", Vector3.ZERO) as Vector3,
		wall.get("end", Vector3.ZERO) as Vector3,
		door_width,
		EDIT_SNAP_M
	)
	if not (snapped_position is Vector3):
		return _failure_result(&"side_too_short")

	if _door_overlaps_existing(data, partition_id, snapped_position as Vector3, door_width, null):
		return _failure_result(&"door_overlap")

	var door := BspModuleDataScript.BspDoor.new()
	door.id = _next_manual_door_id(data)
	door.partition_id = partition_id
	door.position = snapped_position as Vector3
	door.width_m = door_width
	door.is_manual = true
	data.doors.append(door)
	return {
		"ok": true,
		"action": &"added",
		"door_id": door.id,
		"position": door.position,
		"side": side_info.get("side", &""),
	}

static func resize_room_side_to_position(
	data: BspModuleDataScript,
	room_id: StringName,
	side: StringName,
	position: Vector3,
	snap_m: float = EDIT_SNAP_M
) -> Dictionary:
	if data == null or data.root_node == null:
		return _failure_result(&"no_generated_bsp")

	var side_info := room_side_info(data, room_id, side)
	if not bool(side_info.get("ok", false)):
		return side_info
	if bool(side_info.get("is_perimeter", false)):
		return _failure_result(&"perimeter_resize_unsupported")

	var partition_id := side_info.get("partition_id", &"") as StringName
	var partition := _partition_by_id(data, partition_id)
	if partition == null or partition.node_id == &"":
		return _failure_result(&"partition_not_found")

	var node := _node_by_id(data.root_node, partition.node_id)
	if node == null or node.is_leaf():
		return _failure_result(&"split_not_found")

	var coordinate := position.x if partition.axis == SPLIT_X else position.z
	var snapped_coordinate := snappedf(coordinate, maxf(snap_m, EPSILON))
	var resize_result := _move_split_node(data, node, snapped_coordinate)
	if not bool(resize_result.get("ok", false)):
		return resize_result

	_refresh_generated_topology_preserving_manual_doors(data)
	resize_result["partition_id"] = partition_id
	resize_result["side"] = side
	return resize_result

static func manual_door_count(data: BspModuleDataScript) -> int:
	var source := _generated_source(data)
	var count := 0
	for door in source.doors:
		if door.is_manual:
			count += 1
	return count

static func exterior_route_room_ids(
	data: BspModuleDataScript,
	start_room_id: StringName
) -> Array[StringName]:
	var source := _generated_source(data)
	var start_room := _room_by_id(source, start_room_id)
	var exit_room := _exterior_exit_room(source)
	if start_room == null or exit_room == null:
		var empty_route: Array[StringName] = []
		return empty_route

	if start_room.id == exit_room.id:
		var direct_route: Array[StringName] = [start_room.id]
		return direct_route

	var adjacency := _room_adjacency(source)
	var frontier: Array[StringName] = [start_room.id]
	var visited := {start_room.id: true}
	var previous := {}

	while not frontier.is_empty():
		var current: StringName = frontier.pop_front()
		var neighbors: Array = adjacency.get(current, [])
		for neighbor_variant in neighbors:
			var neighbor: StringName = neighbor_variant
			if visited.has(neighbor):
				continue

			visited[neighbor] = true
			previous[neighbor] = current
			if neighbor == exit_room.id:
				return _reconstruct_room_route(start_room.id, exit_room.id, previous)
			frontier.append(neighbor)

	var empty_route: Array[StringName] = []
	return empty_route

static func exterior_route_points_for_room(
	data: BspModuleDataScript,
	start_room_id: StringName
) -> PackedVector3Array:
	var source := _generated_source(data)
	var room_ids := exterior_route_room_ids(source, start_room_id)
	var points := PackedVector3Array()
	if room_ids.is_empty():
		return points

	for room_index in range(room_ids.size()):
		var room := _room_by_id(source, room_ids[room_index])
		if room != null:
			points.append(room.center_position())

		if room_index >= room_ids.size() - 1:
			continue

		var door := _door_between_rooms(source, room_ids[room_index], room_ids[room_index + 1])
		if door != null:
			points.append(door.position)

	var exit_door := _exterior_exit_for_room(source, room_ids[room_ids.size() - 1])
	if exit_door != null:
		points.append(exit_door.position)
		points.append(_outside_exit_anchor(source, exit_door))

	return points

static func exterior_route_points_for_position(
	data: BspModuleDataScript,
	position: Vector3
) -> PackedVector3Array:
	var source := _generated_source(data)
	var room := room_at_position(source, position)
	if room == null:
		return PackedVector3Array()

	return exterior_route_points_for_room(source, room.id)

static func compile_interest_sockets(data: BspModuleDataScript) -> Array[Dictionary]:
	var source := _generated_source(data)
	var sockets: Array[Dictionary] = []
	for door in source.doors:
		sockets.append({
			"id": door.id,
			"kind": &"exterior_exit_socket" if door.is_exterior_exit else &"door_socket",
			"is_manual": door.is_manual,
			"position": door.position,
			"width_m": door.width_m,
			"room_ids": _door_room_ids(source, door),
		})

	var player_position := _player_spawn_position(source)
	var player_room := room_at_position(source, player_position)
	sockets.append({
		"id": &"pc_spawn_socket",
		"kind": &"object_socket",
		"object_kind": &"player_character",
		"position": player_position,
		"room_id": player_room.id if player_room != null else &"",
	})

	var walls: Array[WallSegmentDataScript] = compile_to_walls(source)
	var npc_position := _npc_spawn_position(source, walls)
	sockets.append({
		"id": &"npc_spawn_socket",
		"kind": &"object_socket",
		"object_kind": &"non_player_character",
		"position": npc_position,
		"room_id": &"exterior",
	})

	return sockets

static func _generated_source(data: BspModuleDataScript) -> BspModuleDataScript:
	var source := data if data != null else BspModuleDataScript.new()
	return source if source.root_node != null else generate(source)

static func _failure_result(reason: StringName) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}

static func _room_side_result(
	data: BspModuleDataScript,
	room: BspModuleDataScript.BspRoom,
	side: StringName,
	position: Vector3
) -> Dictionary:
	var segment := _room_side_segment(room, side)
	var start := segment[0] as Vector3
	var end := segment[1] as Vector3
	var closest := _closest_point_on_segment_2d(position, start, end)
	var partition_id := _partition_id_for_room_side(data, room, side)
	var is_perimeter := _is_perimeter_id(partition_id)
	var result := {
		"ok": false,
		"room_id": room.id,
		"side": side,
		"partition_id": partition_id,
		"is_perimeter": is_perimeter,
		"start": start,
		"end": end,
		"position": closest,
		"distance_m": _distance_2d(position, closest),
		"axis": SPLIT_X if side == &"east" or side == &"west" else SPLIT_Z,
	}
	var partition := _partition_by_id(data, partition_id)
	if partition != null:
		result["partition_start"] = partition.start_position
		result["partition_end"] = partition.end_position

	return result

static func _room_side_segment(
	room: BspModuleDataScript.BspRoom,
	side: StringName
) -> Array[Vector3]:
	var x0 := room.bounds.position.x
	var x1 := room.bounds.end.x
	var z0 := room.bounds.position.y
	var z1 := room.bounds.end.y
	match side:
		&"north":
			return [Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0)]
		&"east":
			return [Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1)]
		&"west":
			return [Vector3(x0, 0.0, z1), Vector3(x0, 0.0, z0)]
		_:
			return [Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1)]

static func _room_side_center(
	room: BspModuleDataScript.BspRoom,
	side: StringName
) -> Variant:
	if side != &"north" and side != &"east" and side != &"south" and side != &"west":
		return null

	var segment := _room_side_segment(room, side)
	return ((segment[0] as Vector3) + (segment[1] as Vector3)) * 0.5

static func _partition_id_for_room_side(
	data: BspModuleDataScript,
	room: BspModuleDataScript.BspRoom,
	side: StringName
) -> StringName:
	var bounds := _building_bounds(data)
	match side:
		&"north":
			if absf(room.bounds.position.y - bounds.position.y) <= EPSILON:
				return PERIMETER_NORTH
		&"east":
			if absf(room.bounds.end.x - bounds.end.x) <= EPSILON:
				return PERIMETER_EAST
		&"west":
			if absf(room.bounds.position.x - bounds.position.x) <= EPSILON:
				return PERIMETER_WEST
		_:
			if absf(room.bounds.end.y - bounds.end.y) <= EPSILON:
				return PERIMETER_SOUTH

	var desired_axis := SPLIT_X if side == &"east" or side == &"west" else SPLIT_Z
	var desired_coordinate := _room_side_coordinate(room, side)
	var desired_range := _room_side_range(room, side)
	for partition in data.partitions:
		if partition.axis != desired_axis:
			continue
		var partition_coordinate := partition.start_position.x if desired_axis == SPLIT_X else partition.start_position.z
		if absf(partition_coordinate - desired_coordinate) > EPSILON:
			continue
		var partition_range := _segment_axis_range(partition.start_position, partition.end_position, desired_axis)
		if _ranges_overlap(desired_range, partition_range):
			return partition.id

	return &""

static func _room_side_coordinate(room: BspModuleDataScript.BspRoom, side: StringName) -> float:
	match side:
		&"north":
			return room.bounds.position.y
		&"east":
			return room.bounds.end.x
		&"west":
			return room.bounds.position.x
		_:
			return room.bounds.end.y

static func _room_side_range(room: BspModuleDataScript.BspRoom, side: StringName) -> Vector2:
	if side == &"east" or side == &"west":
		return Vector2(room.bounds.position.y, room.bounds.end.y)
	return Vector2(room.bounds.position.x, room.bounds.end.x)

static func _segment_axis_range(start: Vector3, end: Vector3, split_axis: int) -> Vector2:
	if split_axis == SPLIT_X:
		return Vector2(minf(start.z, end.z), maxf(start.z, end.z))
	return Vector2(minf(start.x, end.x), maxf(start.x, end.x))

static func _ranges_overlap(first: Vector2, second: Vector2) -> bool:
	return minf(first.y, second.y) - maxf(first.x, second.x) > EPSILON

static func _raw_wall_for_partition(data: BspModuleDataScript, partition_id: StringName) -> Dictionary:
	for raw_wall in _raw_walls(data):
		if raw_wall.get("partition_id", &"") == partition_id:
			return raw_wall
	return {}

static func _snapped_door_position_on_wall(
	position: Vector3,
	start: Vector3,
	end: Vector3,
	door_width_m: float,
	snap_m: float
) -> Variant:
	var direction := end - start
	direction.y = 0.0
	var length := direction.length()
	if length < door_width_m + EPSILON:
		return null

	direction = direction.normalized()
	var half_width := door_width_m * 0.5
	var raw_distance := (position - start).dot(direction)
	if raw_distance < half_width or raw_distance > length - half_width:
		return null
	var snapped_distance := snappedf(raw_distance, maxf(snap_m, EPSILON))
	if snapped_distance < half_width or snapped_distance > length - half_width:
		return null
	return start + (direction * snapped_distance)

static func _manual_door_near_room(
	data: BspModuleDataScript,
	room_id: StringName,
	position: Vector3,
	max_distance_m: float
) -> BspModuleDataScript.BspDoor:
	var best_door: BspModuleDataScript.BspDoor
	var best_distance := INF
	for door in data.doors:
		if not door.is_manual:
			continue
		var room_ids := _door_room_ids(data, door)
		if not room_ids.has(room_id):
			continue
		var distance := _distance_2d(position, door.position)
		var threshold := maxf(max_distance_m, door.width_m * 0.5)
		if distance <= threshold and distance < best_distance:
			best_door = door
			best_distance = distance

	return best_door

static func _door_overlaps_existing(
	data: BspModuleDataScript,
	partition_id: StringName,
	position: Vector3,
	width_m: float,
	ignored_door: BspModuleDataScript.BspDoor
) -> bool:
	for door in data.doors:
		if door == ignored_door:
			continue
		if door.partition_id != partition_id:
			continue
		var min_spacing := maxf(width_m, door.width_m)
		if _distance_2d(position, door.position) < min_spacing - EPSILON:
			return true
	return false

static func _next_manual_door_id(data: BspModuleDataScript) -> StringName:
	var index := 0
	while true:
		var candidate := StringName("manual_door_%02d" % index)
		if not _door_id_exists(data, candidate):
			return candidate
		index += 1

	return &"manual_door"

static func _door_id_exists(data: BspModuleDataScript, door_id: StringName) -> bool:
	for door in data.doors:
		if door.id == door_id:
			return true
	return false

static func _move_split_node(
	data: BspModuleDataScript,
	node: BspModuleDataScript.BspNode,
	new_split_position: float
) -> Dictionary:
	if node == null or node.is_leaf():
		return _failure_result(&"split_not_found")

	var axis := node.split_axis
	var start := node.bounds.position.x if axis == SPLIT_X else node.bounds.position.y
	var end := node.bounds.end.x if axis == SPLIT_X else node.bounds.end.y
	var left_min := _min_span_for_node(node.left_child, axis, data.min_room_size_m)
	var right_min := _min_span_for_node(node.right_child, axis, data.min_room_size_m)
	if end - start < left_min + right_min - EPSILON:
		return _failure_result(&"split_too_small")

	var min_split := start + left_min
	var max_split := end - right_min
	if new_split_position < min_split - EPSILON or new_split_position > max_split + EPSILON:
		return _failure_result(&"min_room_size")

	var clamped_split := _clamp_ordered(new_split_position, min_split, max_split)
	if absf(clamped_split - node.split_position) <= EPSILON:
		return _failure_result(&"unchanged")

	node.split_position = clamped_split
	if axis == SPLIT_X:
		_fit_subtree_to_bounds(
			node.left_child,
			Rect2(node.bounds.position, Vector2(clamped_split - node.bounds.position.x, node.bounds.size.y)),
			data
		)
		_fit_subtree_to_bounds(
			node.right_child,
			Rect2(Vector2(clamped_split, node.bounds.position.y), Vector2(node.bounds.end.x - clamped_split, node.bounds.size.y)),
			data
		)
	else:
		_fit_subtree_to_bounds(
			node.left_child,
			Rect2(node.bounds.position, Vector2(node.bounds.size.x, clamped_split - node.bounds.position.y)),
			data
		)
		_fit_subtree_to_bounds(
			node.right_child,
			Rect2(Vector2(node.bounds.position.x, clamped_split), Vector2(node.bounds.size.x, node.bounds.end.y - clamped_split)),
			data
		)

	return {
		"ok": true,
		"action": &"resized",
		"split_position": clamped_split,
	}

static func _fit_subtree_to_bounds(
	node: BspModuleDataScript.BspNode,
	bounds: Rect2,
	data: BspModuleDataScript
) -> void:
	if node == null:
		return

	var old_bounds := node.bounds
	node.bounds = bounds
	if node.is_leaf():
		return

	var axis := node.split_axis
	var old_start := old_bounds.position.x if axis == SPLIT_X else old_bounds.position.y
	var old_span := old_bounds.size.x if axis == SPLIT_X else old_bounds.size.y
	var new_start := bounds.position.x if axis == SPLIT_X else bounds.position.y
	var new_span := bounds.size.x if axis == SPLIT_X else bounds.size.y
	var ratio := 0.5
	if old_span > EPSILON:
		ratio = clampf((node.split_position - old_start) / old_span, 0.0, 1.0)

	var left_min := _min_span_for_node(node.left_child, axis, data.min_room_size_m)
	var right_min := _min_span_for_node(node.right_child, axis, data.min_room_size_m)
	var split_position := new_start + (new_span * ratio)
	split_position = snappedf(split_position, SPLIT_STEP_M)
	split_position = _clamp_ordered(split_position, new_start + left_min, new_start + new_span - right_min)
	node.split_position = split_position

	if axis == SPLIT_X:
		_fit_subtree_to_bounds(
			node.left_child,
			Rect2(bounds.position, Vector2(split_position - bounds.position.x, bounds.size.y)),
			data
		)
		_fit_subtree_to_bounds(
			node.right_child,
			Rect2(Vector2(split_position, bounds.position.y), Vector2(bounds.end.x - split_position, bounds.size.y)),
			data
		)
	else:
		_fit_subtree_to_bounds(
			node.left_child,
			Rect2(bounds.position, Vector2(bounds.size.x, split_position - bounds.position.y)),
			data
		)
		_fit_subtree_to_bounds(
			node.right_child,
			Rect2(Vector2(bounds.position.x, split_position), Vector2(bounds.size.x, bounds.end.y - split_position)),
			data
		)

static func _min_span_for_node(
	node: BspModuleDataScript.BspNode,
	axis: int,
	min_room_size_m: float
) -> float:
	if node == null or node.is_leaf():
		return min_room_size_m
	if node.split_axis == axis:
		return (
			_min_span_for_node(node.left_child, axis, min_room_size_m)
			+ _min_span_for_node(node.right_child, axis, min_room_size_m)
		)

	return maxf(
		_min_span_for_node(node.left_child, axis, min_room_size_m),
		_min_span_for_node(node.right_child, axis, min_room_size_m)
	)

static func _refresh_generated_topology_preserving_manual_doors(data: BspModuleDataScript) -> void:
	var manual_doors: Array[BspModuleDataScript.BspDoor] = []
	for door in data.doors:
		if door.is_manual:
			manual_doors.append(_copy_door(door))

	data.rooms.clear()
	data.partitions.clear()
	data.doors.clear()
	_gather_rooms(data.root_node, data.rooms)
	_gather_partitions(data.root_node, data)
	_add_exterior_exit(data)

	for manual_door in manual_doors:
		var normalized_door: Variant = _normalized_manual_door(data, manual_door)
		if not (normalized_door is BspModuleDataScript.BspDoor):
			continue
		var door := normalized_door as BspModuleDataScript.BspDoor
		if _door_overlaps_existing(data, door.partition_id, door.position, door.width_m, null):
			continue
		data.doors.append(door)

static func _copy_door(door: BspModuleDataScript.BspDoor) -> BspModuleDataScript.BspDoor:
	var copy := BspModuleDataScript.BspDoor.new()
	copy.id = door.id
	copy.partition_id = door.partition_id
	copy.position = door.position
	copy.width_m = door.width_m
	copy.is_exterior_exit = door.is_exterior_exit
	copy.is_manual = door.is_manual
	return copy

static func _normalized_manual_door(
	data: BspModuleDataScript,
	door: BspModuleDataScript.BspDoor
) -> Variant:
	var wall := _raw_wall_for_partition(data, door.partition_id)
	if wall.is_empty():
		return null

	var start := wall.get("start", Vector3.ZERO) as Vector3
	var end := wall.get("end", Vector3.ZERO) as Vector3
	var normalized_position: Variant = _snapped_door_position_on_wall(
		door.position,
		start,
		end,
		door.width_m,
		EDIT_SNAP_M
	)
	if not (normalized_position is Vector3):
		return null

	var copy := _copy_door(door)
	copy.position = normalized_position as Vector3
	copy.is_manual = true
	copy.is_exterior_exit = false
	return copy

static func _node_by_id(
	node: BspModuleDataScript.BspNode,
	node_id: StringName
) -> BspModuleDataScript.BspNode:
	if node == null:
		return null
	if node.id == node_id:
		return node

	var left_match := _node_by_id(node.left_child, node_id)
	if left_match != null:
		return left_match
	return _node_by_id(node.right_child, node_id)

static func _closest_point_on_segment_2d(point: Vector3, start: Vector3, end: Vector3) -> Vector3:
	var point_2d := Vector2(point.x, point.z)
	var start_2d := Vector2(start.x, start.z)
	var end_2d := Vector2(end.x, end.z)
	var segment := end_2d - start_2d
	var length_squared := segment.length_squared()
	if length_squared <= EPSILON:
		return start

	var t := clampf((point_2d - start_2d).dot(segment) / length_squared, 0.0, 1.0)
	var closest := start_2d + (segment * t)
	return Vector3(closest.x, 0.0, closest.y)

static func _distance_2d(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

static func _room_by_id(
	data: BspModuleDataScript,
	room_id: StringName
) -> BspModuleDataScript.BspRoom:
	for room in data.rooms:
		if room.id == room_id:
			return room

	return null

static func _room_adjacency(data: BspModuleDataScript) -> Dictionary:
	var adjacency := {}
	for room in data.rooms:
		adjacency[room.id] = []

	for partition in data.partitions:
		if partition.left_room_id == &"" or partition.right_room_id == &"":
			continue
		if not adjacency.has(partition.left_room_id) or not adjacency.has(partition.right_room_id):
			continue

		(adjacency[partition.left_room_id] as Array).append(partition.right_room_id)
		(adjacency[partition.right_room_id] as Array).append(partition.left_room_id)

	return adjacency

static func _reconstruct_room_route(
	start_room_id: StringName,
	exit_room_id: StringName,
	previous: Dictionary
) -> Array[StringName]:
	var route: Array[StringName] = []
	var cursor := exit_room_id
	while cursor != &"":
		route.push_front(cursor)
		if cursor == start_room_id:
			return route

		cursor = previous.get(cursor, &"")

	var empty_route: Array[StringName] = []
	return empty_route

static func _door_between_rooms(
	data: BspModuleDataScript,
	from_room_id: StringName,
	to_room_id: StringName
) -> BspModuleDataScript.BspDoor:
	for door in data.doors:
		if door.is_exterior_exit:
			continue

		var room_ids := _door_room_ids(data, door)
		if room_ids.has(from_room_id) and room_ids.has(to_room_id):
			return door

	return null

static func _exterior_exit_room(data: BspModuleDataScript) -> BspModuleDataScript.BspRoom:
	var exterior_exit := _exterior_exit(data)
	if exterior_exit == null:
		return null

	return _room_for_exterior_exit(data, exterior_exit)

static func _exterior_exit_for_room(
	data: BspModuleDataScript,
	room_id: StringName
) -> BspModuleDataScript.BspDoor:
	for door in data.doors:
		if not door.is_exterior_exit:
			continue

		var room := _room_for_exterior_exit(data, door)
		if room != null and room.id == room_id:
			return door

	return null

static func _room_for_exterior_exit(
	data: BspModuleDataScript,
	exterior_exit: BspModuleDataScript.BspDoor
) -> BspModuleDataScript.BspRoom:
	var bounds := _building_bounds(data)
	var side := _side_for_perimeter_id(exterior_exit.partition_id)
	for room in data.rooms:
		if not _room_touches_exterior_side(room, bounds, side):
			continue
		match side:
			&"north", &"south":
				if _scalar_in_range(exterior_exit.position.x, room.bounds.position.x, room.bounds.end.x):
					return room
			_:
				if _scalar_in_range(exterior_exit.position.z, room.bounds.position.y, room.bounds.end.y):
					return room

	return null

static func _door_room_ids(
	data: BspModuleDataScript,
	door: BspModuleDataScript.BspDoor
) -> Array[StringName]:
	if door.is_exterior_exit:
		var exterior_room := _room_for_exterior_exit(data, door)
		var exterior_room_ids: Array[StringName] = [&"exterior"]
		if exterior_room != null:
			exterior_room_ids.push_front(exterior_room.id)
		return exterior_room_ids

	var partition := _partition_by_id(data, door.partition_id)
	if partition == null:
		if _is_perimeter_id(door.partition_id):
			var perimeter_room := _room_for_perimeter_door(data, door)
			var perimeter_room_ids: Array[StringName] = [&"exterior"]
			if perimeter_room != null:
				perimeter_room_ids.push_front(perimeter_room.id)
			return perimeter_room_ids

		var empty_room_ids: Array[StringName] = []
		return empty_room_ids

	var room_ids: Array[StringName] = []
	if partition.left_room_id != &"":
		room_ids.append(partition.left_room_id)
	if partition.right_room_id != &"":
		room_ids.append(partition.right_room_id)
	return room_ids

static func _room_for_perimeter_door(
	data: BspModuleDataScript,
	door: BspModuleDataScript.BspDoor
) -> BspModuleDataScript.BspRoom:
	var bounds := _building_bounds(data)
	var side := _side_for_perimeter_id(door.partition_id)
	for room in data.rooms:
		if not _room_touches_exterior_side(room, bounds, side):
			continue
		match side:
			&"north", &"south":
				if _scalar_in_range(door.position.x, room.bounds.position.x, room.bounds.end.x):
					return room
			_:
				if _scalar_in_range(door.position.z, room.bounds.position.y, room.bounds.end.y):
					return room

	return null

static func _partition_by_id(
	data: BspModuleDataScript,
	partition_id: StringName
) -> BspModuleDataScript.BspPartition:
	for partition in data.partitions:
		if partition.id == partition_id:
			return partition

	return null

static func _outside_exit_anchor(
	data: BspModuleDataScript,
	exterior_exit: BspModuleDataScript.BspDoor
) -> Vector3:
	var building_bounds := _building_bounds(data)
	var ground_bounds := _ground_bounds(data)
	var margin := maxf(data.actor_size_m.x, data.actor_size_m.z) * 0.5
	var side := _side_for_perimeter_id(exterior_exit.partition_id)
	return _fallback_external_position(data, exterior_exit.position, side, margin, building_bounds, ground_bounds)

static func _rect_has_point_inclusive(rect: Rect2, point: Vector2) -> bool:
	return (
		_scalar_in_range(point.x, rect.position.x, rect.end.x)
		and _scalar_in_range(point.y, rect.position.y, rect.end.y)
	)

static func _scalar_in_range(value: float, start: float, end: float) -> bool:
	return value >= minf(start, end) - EPSILON and value <= maxf(start, end) + EPSILON

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
	partition.node_id = node.id
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

static func _add_exterior_exit(data: BspModuleDataScript) -> void:
	if data.rooms.is_empty():
		return

	var bounds := _building_bounds(data)
	var side := _normalized_exit_side(data.exterior_exit_side)
	var exit_room := _best_exit_room(data.rooms, bounds, side)
	if exit_room == null:
		return

	var door := BspModuleDataScript.BspDoor.new()
	door.id = StringName("exit_%02d" % data.doors.size())
	door.partition_id = _perimeter_id_for_side(side)
	door.width_m = data.door_width_m
	door.is_exterior_exit = true
	door.position = _exit_position_for_room(exit_room, bounds, side, door.width_m)
	data.doors.append(door)

static func _normalized_exit_side(side: StringName) -> StringName:
	match side:
		PERIMETER_NORTH, &"north":
			return &"north"
		PERIMETER_EAST, &"east":
			return &"east"
		PERIMETER_WEST, &"west":
			return &"west"
		_:
			return &"south"

static func _best_exit_room(
	rooms: Array[BspModuleDataScript.BspRoom],
	bounds: Rect2,
	side: StringName
) -> BspModuleDataScript.BspRoom:
	var best_room: BspModuleDataScript.BspRoom
	var best_score := INF
	for room in rooms:
		if not _room_touches_exterior_side(room, bounds, side):
			continue

		var center := room.bounds.position + (room.bounds.size * 0.5)
		var score := absf(center.x) if side == &"north" or side == &"south" else absf(center.y)
		if score < best_score:
			best_room = room
			best_score = score

	return best_room

static func _room_touches_exterior_side(
	room: BspModuleDataScript.BspRoom,
	bounds: Rect2,
	side: StringName
) -> bool:
	match side:
		&"north":
			return absf(room.bounds.position.y - bounds.position.y) <= EPSILON
		&"east":
			return absf(room.bounds.end.x - bounds.end.x) <= EPSILON
		&"west":
			return absf(room.bounds.position.x - bounds.position.x) <= EPSILON
		_:
			return absf(room.bounds.end.y - bounds.end.y) <= EPSILON

static func _exit_position_for_room(
	room: BspModuleDataScript.BspRoom,
	bounds: Rect2,
	side: StringName,
	door_width_m: float
) -> Vector3:
	var half_width := door_width_m * 0.5
	var room_center := room.bounds.position + (room.bounds.size * 0.5)
	match side:
		&"north":
			var north_x := _clamp_ordered(room_center.x, room.bounds.position.x + half_width, room.bounds.end.x - half_width)
			return Vector3(north_x, 0.0, bounds.position.y)
		&"east":
			var east_z := _clamp_ordered(room_center.y, room.bounds.position.y + half_width, room.bounds.end.y - half_width)
			return Vector3(bounds.end.x, 0.0, east_z)
		&"west":
			var west_z := _clamp_ordered(room_center.y, room.bounds.position.y + half_width, room.bounds.end.y - half_width)
			return Vector3(bounds.position.x, 0.0, west_z)
		_:
			var south_x := _clamp_ordered(room_center.x, room.bounds.position.x + half_width, room.bounds.end.x - half_width)
			return Vector3(south_x, 0.0, bounds.end.y)

static func _perimeter_id_for_side(side: StringName) -> StringName:
	match side:
		&"north":
			return PERIMETER_NORTH
		&"east":
			return PERIMETER_EAST
		&"west":
			return PERIMETER_WEST
		_:
			return PERIMETER_SOUTH

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
	walls.append(_raw_wall(PERIMETER_NORTH, Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0)))
	walls.append(_raw_wall(PERIMETER_EAST, Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1)))
	walls.append(_raw_wall(PERIMETER_SOUTH, Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1)))
	walls.append(_raw_wall(PERIMETER_WEST, Vector3(x0, 0.0, z1), Vector3(x0, 0.0, z0)))

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
	var exterior_exit := _exterior_exit(data)
	if exterior_exit != null:
		var exterior_position: Variant = _npc_external_spawn_position(data, walls, rng, exterior_exit)
		if exterior_position is Vector3:
			return exterior_position as Vector3

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

static func _exterior_exit(data: BspModuleDataScript) -> BspModuleDataScript.BspDoor:
	for door in data.doors:
		if door.is_exterior_exit:
			return door
	return null

static func _npc_external_spawn_position(
	data: BspModuleDataScript,
	walls: Array[WallSegmentDataScript],
	rng: RandomNumberGenerator,
	exterior_exit: BspModuleDataScript.BspDoor
) -> Variant:
	var building_bounds := _building_bounds(data)
	var ground_bounds := _ground_bounds(data)
	var margin := maxf(data.actor_size_m.x, data.actor_size_m.z) * 0.5
	var pc_position := _player_spawn_position(data)
	var side := _side_for_perimeter_id(exterior_exit.partition_id)

	for _attempt in range(data.npc_spawn_attempts):
		var position := _random_external_position(data, rng, exterior_exit.position, side, margin, building_bounds, ground_bounds)
		if position.distance_to(pc_position) < 1.0:
			continue
		if _building_bounds(data).has_point(Vector2(position.x, position.z)):
			continue
		if _distance_to_walls(position, walls) >= data.npc_wall_clearance_m:
			return position

	var fallback := _fallback_external_position(data, exterior_exit.position, side, margin, building_bounds, ground_bounds)
	return fallback if not building_bounds.has_point(Vector2(fallback.x, fallback.z)) else null

static func _random_external_position(
	data: BspModuleDataScript,
	rng: RandomNumberGenerator,
	exit_position: Vector3,
	side: StringName,
	margin: float,
	building_bounds: Rect2,
	ground_bounds: Rect2
) -> Vector3:
	var lateral_span := maxf(data.ground_buffer_m, data.door_width_m)
	match side:
		&"north":
			return Vector3(
				_rand_range_ordered(rng, exit_position.x - lateral_span, exit_position.x + lateral_span, ground_bounds.position.x + margin, ground_bounds.end.x - margin),
				0.0,
				_rand_range_ordered(rng, ground_bounds.position.y + margin, building_bounds.position.y - margin)
			)
		&"east":
			return Vector3(
				_rand_range_ordered(rng, building_bounds.end.x + margin, ground_bounds.end.x - margin),
				0.0,
				_rand_range_ordered(rng, exit_position.z - lateral_span, exit_position.z + lateral_span, ground_bounds.position.y + margin, ground_bounds.end.y - margin)
			)
		&"west":
			return Vector3(
				_rand_range_ordered(rng, ground_bounds.position.x + margin, building_bounds.position.x - margin),
				0.0,
				_rand_range_ordered(rng, exit_position.z - lateral_span, exit_position.z + lateral_span, ground_bounds.position.y + margin, ground_bounds.end.y - margin)
			)
		_:
			return Vector3(
				_rand_range_ordered(rng, exit_position.x - lateral_span, exit_position.x + lateral_span, ground_bounds.position.x + margin, ground_bounds.end.x - margin),
				0.0,
				_rand_range_ordered(rng, building_bounds.end.y + margin, ground_bounds.end.y - margin)
			)

static func _fallback_external_position(
	data: BspModuleDataScript,
	exit_position: Vector3,
	side: StringName,
	margin: float,
	building_bounds: Rect2,
	ground_bounds: Rect2
) -> Vector3:
	var offset := maxf(data.npc_wall_clearance_m + margin, data.door_width_m)
	match side:
		&"north":
			return Vector3(
				_clamp_ordered(exit_position.x, ground_bounds.position.x + margin, ground_bounds.end.x - margin),
				0.0,
				_clamp_ordered(building_bounds.position.y - offset, ground_bounds.position.y + margin, building_bounds.position.y - margin)
			)
		&"east":
			return Vector3(
				_clamp_ordered(building_bounds.end.x + offset, building_bounds.end.x + margin, ground_bounds.end.x - margin),
				0.0,
				_clamp_ordered(exit_position.z, ground_bounds.position.y + margin, ground_bounds.end.y - margin)
			)
		&"west":
			return Vector3(
				_clamp_ordered(building_bounds.position.x - offset, ground_bounds.position.x + margin, building_bounds.position.x - margin),
				0.0,
				_clamp_ordered(exit_position.z, ground_bounds.position.y + margin, ground_bounds.end.y - margin)
			)
		_:
			return Vector3(
				_clamp_ordered(exit_position.x, ground_bounds.position.x + margin, ground_bounds.end.x - margin),
				0.0,
				_clamp_ordered(building_bounds.end.y + offset, building_bounds.end.y + margin, ground_bounds.end.y - margin)
			)

static func _side_for_perimeter_id(perimeter_id: StringName) -> StringName:
	match perimeter_id:
		PERIMETER_NORTH:
			return &"north"
		PERIMETER_EAST:
			return &"east"
		PERIMETER_WEST:
			return &"west"
		_:
			return &"south"

static func _is_perimeter_id(partition_id: StringName) -> bool:
	return (
		partition_id == PERIMETER_NORTH
		or partition_id == PERIMETER_EAST
		or partition_id == PERIMETER_SOUTH
		or partition_id == PERIMETER_WEST
	)

static func _rand_range_ordered(
	rng: RandomNumberGenerator,
	min_value: float,
	max_value: float,
	clamp_min: float = -INF,
	clamp_max: float = INF
) -> float:
	var clamp_low := minf(clamp_min, clamp_max)
	var clamp_high := maxf(clamp_min, clamp_max)
	var low := maxf(minf(min_value, max_value), clamp_low)
	var high := minf(maxf(min_value, max_value), clamp_high)
	if high < low:
		var midpoint := (low + high) * 0.5
		low = midpoint
		high = midpoint
	return rng.randf_range(low, high) if high > low else low

static func _clamp_ordered(value: float, min_value: float, max_value: float) -> float:
	return clampf(value, minf(min_value, max_value), maxf(min_value, max_value))

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
	result.exterior_exit_side = source.exterior_exit_side
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
