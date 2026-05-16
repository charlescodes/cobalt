class_name WallVisualResolver
extends RefCounted

const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")

static func visual_endpoints(segment: WallSegmentDataScript) -> PackedVector3Array:
	if segment == null:
		return PackedVector3Array()

	return PackedVector3Array([segment.start_position, segment.end_position])

static func visual_center(segment: WallSegmentDataScript) -> Vector3:
	if segment == null:
		return Vector3.ZERO

	var center := (segment.start_position + segment.end_position) * 0.5
	center.y = segment.height_m * 0.5
	return center

static func visual_length(segment: WallSegmentDataScript) -> float:
	if segment == null:
		return 0.0

	return maxf(segment.horizontal_length(), segment.thickness_m)

static func visual_rotation_y(segment: WallSegmentDataScript) -> float:
	if segment == null:
		return 0.0

	var delta := segment.horizontal_delta()
	if delta.length_squared() <= 0.000001:
		return 0.0

	return atan2(delta.x, delta.z)
