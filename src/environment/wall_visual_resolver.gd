class_name WallVisualResolver
extends RefCounted

const WallDataScript := preload("res://src/environment/wall_data.gd")

static func visual_endpoints(wall: WallDataScript) -> PackedVector3Array:
	if wall == null:
		return PackedVector3Array()

	return PackedVector3Array([wall.start_position, wall.end_position])

static func visual_center(wall: WallDataScript) -> Vector3:
	if wall == null:
		return Vector3.ZERO

	var center := (wall.start_position + wall.end_position) * 0.5
	center.y += wall.height_m * 0.5
	return center

static func visual_length(wall: WallDataScript) -> float:
	if wall == null:
		return 0.0

	return maxf(wall.horizontal_length(), wall.thickness_m)

static func visual_size(wall: WallDataScript) -> Vector3:
	if wall == null:
		return Vector3.ZERO

	return Vector3(wall.thickness_m, wall.height_m, visual_length(wall))

static func visual_rotation_y(wall: WallDataScript) -> float:
	if wall == null:
		return 0.0

	var delta := wall.horizontal_delta()
	if delta.length_squared() <= 0.000001:
		return 0.0

	return atan2(delta.x, delta.z)

static func visual_local_transform(wall: WallDataScript) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, visual_rotation_y(wall)), Vector3.ZERO)

static func build_visual_mesh(wall: WallDataScript) -> BoxMesh:
	if wall == null or not wall.is_valid_wall():
		return null

	var box_mesh := BoxMesh.new()
	box_mesh.size = visual_size(wall)
	return box_mesh
