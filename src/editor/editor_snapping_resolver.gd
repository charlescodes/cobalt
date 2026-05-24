class_name EditorSnappingResolver
extends RefCounted

const DEFAULT_STEP_M: float = 0.1
const DEFAULT_CONTEXT_SNAP_DISTANCE_M: float = 0.35
const EPSILON: float = 0.0001

static func snap_vector3(raw_pos: Vector3, step: float = DEFAULT_STEP_M) -> Vector3:
	if step <= EPSILON:
		return raw_pos

	return Vector3(
		snappedf(raw_pos.x, step),
		snappedf(raw_pos.y, step),
		snappedf(raw_pos.z, step)
	)

static func snap_with_context(
	raw_pos: Vector3,
	context: Dictionary = {},
	step: float = DEFAULT_STEP_M
) -> Vector3:
	var snapped_position := snap_vector3(raw_pos, step)
	snapped_position = _snap_to_nearest_wall_segment(snapped_position, context)
	return _apply_context_elevation(snapped_position, context)

static func _snap_to_nearest_wall_segment(position: Vector3, context: Dictionary) -> Vector3:
	var segments: Array = context.get(&"wall_segments", [])
	if segments.is_empty():
		return position

	var max_distance_m := float(context.get(&"wall_snap_distance_m", DEFAULT_CONTEXT_SNAP_DISTANCE_M))
	var best_position := position
	var best_distance := INF
	for segment in segments:
		var segment_points := _segment_points(segment)
		if segment_points.is_empty():
			continue

		var candidate := _closest_point_on_segment_xz(
			position,
			segment_points[0] as Vector3,
			segment_points[1] as Vector3
		)
		var distance := _distance_xz(position, candidate)
		if distance < best_distance:
			best_position = candidate
			best_distance = distance

	if best_distance > max_distance_m:
		return position

	return best_position

static func _apply_context_elevation(position: Vector3, context: Dictionary) -> Vector3:
	if context.has(&"slope_normal"):
		var normal_value: Variant = context.get(&"slope_normal")
		var origin_value: Variant = context.get(&"slope_origin", Vector3.ZERO)
		if normal_value is Vector3 and origin_value is Vector3:
			return _position_on_origin_plane(position, origin_value as Vector3, normal_value as Vector3)

	if context.has(&"slope_plane"):
		var plane_value: Variant = context.get(&"slope_plane")
		if plane_value is Plane:
			return _position_on_plane(position, plane_value as Plane)

	if context.has(&"elevation_y"):
		position.y = float(context.get(&"elevation_y"))

	return position

static func _segment_points(segment: Variant) -> Array[Vector3]:
	if segment is Dictionary:
		var start_value: Variant = (segment as Dictionary).get(&"start")
		var end_value: Variant = (segment as Dictionary).get(&"end")
		if start_value is Vector3 and end_value is Vector3:
			return [start_value as Vector3, end_value as Vector3]

		start_value = (segment as Dictionary).get(&"start_position")
		end_value = (segment as Dictionary).get(&"end_position")
		if start_value is Vector3 and end_value is Vector3:
			return [start_value as Vector3, end_value as Vector3]

	if segment is Array:
		var points := segment as Array
		if points.size() >= 2 and points[0] is Vector3 and points[1] is Vector3:
			return [points[0] as Vector3, points[1] as Vector3]

	if segment is Resource:
		var resource := segment as Resource
		var start_position: Variant = resource.get("start_position")
		var end_position: Variant = resource.get("end_position")
		if start_position is Vector3 and end_position is Vector3:
			return [start_position as Vector3, end_position as Vector3]

	return []

static func _closest_point_on_segment_xz(position: Vector3, start: Vector3, end: Vector3) -> Vector3:
	var point_2d := Vector2(position.x, position.z)
	var start_2d := Vector2(start.x, start.z)
	var end_2d := Vector2(end.x, end.z)
	var segment := end_2d - start_2d
	var length_squared := segment.length_squared()
	if length_squared <= EPSILON:
		return start

	var t := clampf((point_2d - start_2d).dot(segment) / length_squared, 0.0, 1.0)
	return start.lerp(end, t)

static func _distance_xz(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

static func _position_on_origin_plane(position: Vector3, origin: Vector3, normal: Vector3) -> Vector3:
	var unit_normal := normal.normalized()
	if absf(unit_normal.y) <= EPSILON:
		return position

	position.y = origin.y - (
		(unit_normal.x * (position.x - origin.x))
		+ (unit_normal.z * (position.z - origin.z))
	) / unit_normal.y
	return position

static func _position_on_plane(position: Vector3, plane: Plane) -> Vector3:
	if absf(plane.normal.y) <= EPSILON:
		return position

	position.y = (plane.d - (plane.normal.x * position.x) - (plane.normal.z * position.z)) / plane.normal.y
	return position
