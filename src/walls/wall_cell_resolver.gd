class_name WallCellResolver
extends RefCounted

const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")

static func blocked_keys_for_segment(segment: WallSegmentDataScript) -> Array[Vector3i]:
	var blocked_keys: Array[Vector3i] = []
	if segment == null:
		return blocked_keys

	var start_key := segment.start_key()
	var end_key := segment.end_key()
	var steps := cube_distance(start_key, end_key)
	if steps == 0:
		blocked_keys.append(start_key)
		return blocked_keys

	for index in range(steps + 1):
		var t := float(index) / float(steps)
		var key := _cube_round(_cube_lerp(start_key, end_key, t))
		if not blocked_keys.has(key):
			blocked_keys.append(key)

	return blocked_keys

static func cube_distance(a: Vector3i, b: Vector3i) -> int:
	return int((absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)) / 2)

static func _cube_lerp(a: Vector3i, b: Vector3i, t: float) -> Vector3:
	return Vector3(
		lerpf(float(a.x), float(b.x), t),
		lerpf(float(a.y), float(b.y), t),
		lerpf(float(a.z), float(b.z), t)
	)

static func _cube_round(cube: Vector3) -> Vector3i:
	var q := roundi(cube.x)
	var r := roundi(cube.y)
	var s := roundi(cube.z)

	var q_diff := absf(float(q) - cube.x)
	var r_diff := absf(float(r) - cube.y)
	var s_diff := absf(float(s) - cube.z)

	if q_diff > r_diff and q_diff > s_diff:
		q = -r - s
	elif r_diff > s_diff:
		r = -q - s
	else:
		s = -q - r

	return Vector3i(q, r, s)
