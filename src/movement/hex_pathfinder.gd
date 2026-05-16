class_name HexPathfinder
extends RefCounted

const HexDataScript := preload("res://src/grid/hex_data.gd")

const NEIGHBOR_DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, -1),
	Vector3i(1, -1, 0),
	Vector3i(0, -1, 1),
	Vector3i(-1, 0, 1),
	Vector3i(-1, 1, 0),
	Vector3i(0, 1, -1),
]

static func find_path(hexes: Dictionary, start_key: Vector3i, goal_key: Vector3i) -> Array:
	if not _is_walkable_hex(hexes, start_key) or not _is_walkable_hex(hexes, goal_key):
		return []

	var open_set: Array[Vector3i] = [start_key]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_key: 0}
	var f_score: Dictionary = {start_key: cube_distance(start_key, goal_key)}

	while not open_set.is_empty():
		var current := _lowest_f_score(open_set, f_score)
		if current == goal_key:
			return _reconstruct_path(came_from, current, hexes)

		open_set.erase(current)
		for neighbor in get_neighbor_keys(current):
			if not _is_walkable_hex(hexes, neighbor):
				continue

			var tentative_g_score: int = int(g_score.get(current, 1_000_000)) + 1
			if tentative_g_score >= int(g_score.get(neighbor, 1_000_000)):
				continue

			came_from[neighbor] = current
			g_score[neighbor] = tentative_g_score
			f_score[neighbor] = tentative_g_score + cube_distance(neighbor, goal_key)
			if not open_set.has(neighbor):
				open_set.append(neighbor)

	return []

static func get_neighbor_keys(key: Vector3i) -> Array[Vector3i]:
	var neighbors: Array[Vector3i] = []
	for direction in NEIGHBOR_DIRECTIONS:
		neighbors.append(key + direction)

	return neighbors

static func cube_distance(a: Vector3i, b: Vector3i) -> int:
	return int((absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)) / 2)

static func _lowest_f_score(open_set: Array[Vector3i], f_score: Dictionary) -> Vector3i:
	var best := open_set[0]
	var best_score: int = int(f_score.get(best, 1_000_000))
	for key in open_set:
		var score: int = int(f_score.get(key, 1_000_000))
		if score < best_score:
			best = key
			best_score = score

	return best

static func _reconstruct_path(came_from: Dictionary, current: Vector3i, hexes: Dictionary) -> Array:
	var path_keys: Array[Vector3i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path_keys.insert(0, current)

	var path: Array = []
	for key in path_keys:
		path.append(hexes[key])

	return path

static func _is_walkable_hex(hexes: Dictionary, key: Vector3i) -> bool:
	if not hexes.has(key):
		return false

	var hex_data := hexes[key] as HexDataScript
	return hex_data != null and hex_data.is_walkable
