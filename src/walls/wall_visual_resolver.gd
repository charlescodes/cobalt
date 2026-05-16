class_name WallVisualResolver
extends RefCounted

const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")

static func visual_endpoints(segment: WallSegmentDataScript) -> PackedVector3Array:
	if segment == null:
		return PackedVector3Array()

	return PackedVector3Array([
		Vector3(float(segment.start_q), 0.0, float(segment.start_r)),
		Vector3(float(segment.end_q), 0.0, float(segment.end_r)),
	])
