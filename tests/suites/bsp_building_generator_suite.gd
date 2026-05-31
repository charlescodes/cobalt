extends RefCounted

const BspBuildingGeneratorScript := preload("res://src/generation/bsp_building_generator.gd")
const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var parameters := {
		"width_m": 12.0,
		"depth_m": 8.0,
		"min_room_size_m": 2.0,
		"target_room_count": 5,
		"seed": 1234,
	}
	var first := BspBuildingGeneratorScript.generate(Vector3(3.0, 0.0, -2.0), parameters)
	var second := BspBuildingGeneratorScript.generate(Vector3(3.0, 0.0, -2.0), parameters)
	if first.is_empty() or second.is_empty():
		return ctx.fail("BSP building generator returned an empty result.")

	var rooms: Array = first.get("rooms", [])
	if rooms.size() != 5:
		return ctx.fail("BSP building generator did not create the requested room count.")
	for room in rooms:
		var size: Vector2 = room.get("size", Vector2.ZERO)
		if size.x < 2.0 or size.y < 2.0:
			return ctx.fail("BSP building generator created a room below the minimum room size.")

	var walls: Array = first.get("walls", [])
	var door_sockets: Array = first.get("door_sockets", [])
	if walls.size() <= 4:
		return ctx.fail("BSP building generator did not create internal partition walls.")
	if door_sockets.size() != rooms.size():
		return ctx.fail("BSP building generator should create one exterior door plus one door per partition.")
	if not _has_exterior_socket(first):
		return ctx.fail("BSP building generator did not create an exterior door socket.")
	for wall_data in walls:
		if not (wall_data is WallDataScript):
			return ctx.fail("BSP building generator emitted a non-wall resource.")
		var wall := wall_data as WallDataScript
		if not wall.is_valid_wall() or wall.start_position.y != 0.0 or wall.end_position.y != 0.0:
			return ctx.fail("BSP building generator emitted invalid or non-flattened wall data.")
	for socket_data in door_sockets:
		if not (socket_data is DoorSocketDataScript):
			return ctx.fail("BSP building generator emitted a non-door-socket resource.")
		var socket := socket_data as DoorSocketDataScript
		if not socket.is_valid_socket() or socket.position.y != 0.0:
			return ctx.fail("BSP building generator emitted invalid or non-flattened door socket data.")

	if _result_signature(first) != _result_signature(second):
		return ctx.fail("BSP building generator is not deterministic for a fixed seed.")

	return true

func _has_exterior_socket(result: Dictionary) -> bool:
	var bounds: Dictionary = result.get("bounds", {})
	var min_x := float(bounds.get("min_x", 0.0))
	var max_x := float(bounds.get("max_x", 0.0))
	var min_z := float(bounds.get("min_z", 0.0))
	var max_z := float(bounds.get("max_z", 0.0))
	var door_sockets: Array = result.get("door_sockets", [])
	for socket_data in door_sockets:
		var socket := socket_data as DoorSocketDataScript
		if socket == null:
			continue
		if (
			is_equal_approx(socket.position.x, min_x)
			or is_equal_approx(socket.position.x, max_x)
			or is_equal_approx(socket.position.z, min_z)
			or is_equal_approx(socket.position.z, max_z)
		):
			return true

	return false

func _result_signature(result: Dictionary) -> PackedStringArray:
	var signature := PackedStringArray()
	var walls: Array = result.get("walls", [])
	for wall_data in walls:
		var wall := wall_data as WallDataScript
		if wall == null:
			continue
		signature.append("%.3f,%.3f -> %.3f,%.3f" % [
			wall.start_position.x,
			wall.start_position.z,
			wall.end_position.x,
			wall.end_position.z,
		])
	var door_sockets: Array = result.get("door_sockets", [])
	for socket_data in door_sockets:
		var socket := socket_data as DoorSocketDataScript
		if socket == null:
			continue
		signature.append("door %.3f,%.3f %.3f" % [
			socket.position.x,
			socket.position.z,
			socket.rotation_y,
		])
	return signature
