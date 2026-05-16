class_name WallVisualResolver
extends RefCounted

const HexViewScript := preload("res://src/grid/hex_view.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")

static func visual_endpoints(segment: WallSegmentDataScript) -> PackedVector3Array:
	if segment == null:
		return PackedVector3Array()

	var start_center := HexViewScript.axial_to_world(segment.start_q, segment.start_r, 0.0)
	var end_center := HexViewScript.axial_to_world(segment.end_q, segment.end_r, 0.0)
	var direction := Vector3(end_center.x - start_center.x, 0.0, end_center.z - start_center.z)
	if direction.length_squared() <= 0.0001:
		direction = Vector3.RIGHT

	var start_offset := _anchor_offset(direction, segment.span_mode)
	var end_offset := _anchor_offset(-direction, segment.span_mode)
	return PackedVector3Array([start_center + start_offset, end_center + end_offset])

static func _anchor_offset(direction: Vector3, span_mode: StringName) -> Vector3:
	var candidates := _side_midpoint_offsets()
	if span_mode == WallSegmentDataScript.SPAN_CORNER_TO_CORNER:
		candidates = _corner_offsets()

	var normalized_direction := direction.normalized()
	var best := candidates[0]
	var best_dot := best.normalized().dot(normalized_direction)
	for candidate in candidates:
		var dot := candidate.normalized().dot(normalized_direction)
		if dot > best_dot:
			best = candidate
			best_dot = dot

	return best

static func _corner_offsets() -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	for index in range(6):
		var angle := HexViewScript.HEX_MESH_Y_ROTATION_RADIANS + (float(index) * TAU / 6.0)
		offsets.append(Vector3(cos(angle), 0.0, sin(angle)) * HexViewScript.HEX_RADIUS_M)

	return offsets

static func _side_midpoint_offsets() -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	for index in range(6):
		var angle := HexViewScript.HEX_MESH_Y_ROTATION_RADIANS + ((float(index) + 0.5) * TAU / 6.0)
		offsets.append(Vector3(cos(angle), 0.0, sin(angle)) * (HexViewScript.HEX_SIDE_TO_SIDE_M * 0.5))

	return offsets
