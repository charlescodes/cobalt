extends RefCounted

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const GroundDataScript := preload("res://src/maps/ground_data.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var data := BspModuleDataScript.new()
	data.map_id = "bsp_test"
	data.building_size_m = Vector2(20.0, 16.0)
	data.min_room_size_m = 4.0
	data.max_split_depth = 3
	data.seed = 4242

	var first := BspRoomProcessorScript.generate(data)
	var second := BspRoomProcessorScript.generate(data)
	if _room_signature(first) != _room_signature(second):
		return ctx.fail("BSP generation is not deterministic for a fixed seed.")

	if first.rooms.is_empty():
		return ctx.fail("BSP generation did not produce rooms.")
	var building_bounds := Rect2(data.building_size_m * -0.5, data.building_size_m)
	for room in first.rooms:
		if room.bounds.position.x < building_bounds.position.x - 0.001:
			return ctx.fail("BSP room escaped the building bounds.")
		if room.bounds.position.y < building_bounds.position.y - 0.001:
			return ctx.fail("BSP room escaped the building bounds.")
		if room.bounds.end.x > building_bounds.end.x + 0.001:
			return ctx.fail("BSP room escaped the building bounds.")
		if room.bounds.end.y > building_bounds.end.y + 0.001:
			return ctx.fail("BSP room escaped the building bounds.")
		if room.bounds.size.x < data.min_room_size_m - 0.001:
			return ctx.fail("BSP room width is smaller than min_room_size_m.")
		if room.bounds.size.y < data.min_room_size_m - 0.001:
			return ctx.fail("BSP room depth is smaller than min_room_size_m.")

	if first.partitions.is_empty() or first.doors.is_empty():
		return ctx.fail("BSP generation did not produce internal partitions and default doors.")
	var exterior_exit_count := 0
	for door in first.doors:
		if door.is_exterior_exit:
			exterior_exit_count += 1
	if exterior_exit_count != 1:
		return ctx.fail("BSP generation should produce exactly one exterior exit.")

	var route_room_ids := BspRoomProcessorScript.exterior_route_room_ids(first, first.rooms[0].id)
	if route_room_ids.is_empty() or route_room_ids[0] != first.rooms[0].id:
		return ctx.fail("BSP exterior room route did not start from the requested room.")
	var route_points := BspRoomProcessorScript.exterior_route_points_for_room(first, first.rooms[0].id)
	if route_points.size() < 2:
		return ctx.fail("BSP exterior room route did not produce drawable route points.")
	var first_room_lookup := BspRoomProcessorScript.room_at_position(first, first.rooms[0].center_position())
	if first_room_lookup == null or first_room_lookup.id != first.rooms[0].id:
		return ctx.fail("BSP room lookup did not resolve a room center.")

	var interest_sockets := BspRoomProcessorScript.compile_interest_sockets(first)
	var door_socket_count := 0
	var object_socket_count := 0
	var exit_socket_count := 0
	for socket in interest_sockets:
		var socket_position: Variant = socket.get("position")
		if not (socket_position is Vector3):
			return ctx.fail("BSP interest socket is missing a world position.")
		match socket.get("kind", &""):
			&"door_socket":
				door_socket_count += 1
			&"object_socket":
				object_socket_count += 1
			&"exterior_exit_socket":
				exit_socket_count += 1
	if door_socket_count == 0 or object_socket_count < 2 or exit_socket_count != 1:
		return ctx.fail("BSP interest sockets should describe doors, spawns, and one exterior exit.")

	var walls: Array[WallSegmentDataScript] = BspRoomProcessorScript.compile_to_walls(first)
	if walls.size() <= 4:
		return ctx.fail("BSP compilation did not produce internal wall fragments.")
	for wall in walls:
		if not wall.is_valid_segment():
			return ctx.fail("BSP compilation produced an invalid wall segment.")
	for door in first.doors:
		for wall in walls:
			if _point_on_wall(door.position, wall):
				return ctx.fail("BSP wall compilation did not carve a 1m door gap.")

	var map_data := BspRoomProcessorScript.compile_to_map_data(data)
	if map_data.map_id != "bsp_test":
		return ctx.fail("BSP MapData did not preserve map_id.")
	if map_data.grounds.size() != 1:
		return ctx.fail("BSP MapData should contain one buffered ground.")
	var ground := map_data.grounds[0] as GroundDataScript
	if ground == null:
		return ctx.fail("BSP MapData ground has the wrong type.")
	if not is_equal_approx(ground.size_m.x, data.building_size_m.x + 4.0):
		return ctx.fail("BSP ground does not include the 2m X buffer on each side.")
	if not is_equal_approx(ground.size_m.z, data.building_size_m.y + 4.0):
		return ctx.fail("BSP ground does not include the 2m Z buffer on each side.")
	if map_data.static_walls.size() != walls.size():
		return ctx.fail("BSP MapData wall count does not match compiled walls.")
	if map_data.world_objects.size() != 2:
		return ctx.fail("BSP MapData should contain PC and NPC objects.")

	var pc := map_data.world_objects[0] as WorldObjectDataScript
	var npc := map_data.world_objects[1] as WorldObjectDataScript
	if pc == null or pc.object_id != &"pc_001" or pc.object_kind != &"player_character":
		return ctx.fail("BSP MapData did not create the expected PC.")
	if npc == null or npc.object_id != &"npc_001" or npc.object_kind != &"non_player_character":
		return ctx.fail("BSP MapData did not create the expected NPC.")

	var ground_bounds := Rect2(
		Vector2(-ground.size_m.x * 0.5, -ground.size_m.z * 0.5),
		Vector2(ground.size_m.x, ground.size_m.z)
	)
	if not ground_bounds.has_point(Vector2(npc.position.x, npc.position.z)):
		return ctx.fail("BSP NPC spawn is outside the buffered ground.")
	if building_bounds.has_point(Vector2(npc.position.x, npc.position.z)):
		return ctx.fail("BSP NPC spawn should be outside the generated building.")
	if _distance_to_walls(npc.position, map_data.static_walls) < data.npc_wall_clearance_m:
		return ctx.fail("BSP NPC spawn is too close to a generated wall.")

	return true

func _room_signature(data: BspModuleDataScript) -> String:
	var parts: PackedStringArray = []
	for room in data.rooms:
		parts.append("%s:%s:%s" % [room.id, room.bounds.position, room.bounds.size])
	return "|".join(parts)

func _point_on_wall(point: Vector3, wall: WallSegmentDataScript) -> bool:
	var total := wall.start_position.distance_to(wall.end_position)
	var split := wall.start_position.distance_to(point) + point.distance_to(wall.end_position)
	return absf(total - split) <= 0.01

func _distance_to_walls(position: Vector3, walls: Array[WallSegmentDataScript]) -> float:
	var best := INF
	var point := Vector2(position.x, position.z)
	for wall in walls:
		best = minf(best, _point_to_segment_distance_2d(
			point,
			Vector2(wall.start_position.x, wall.start_position.z),
			Vector2(wall.end_position.x, wall.end_position.z)
		))
	return best

func _point_to_segment_distance_2d(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + (segment * t))
