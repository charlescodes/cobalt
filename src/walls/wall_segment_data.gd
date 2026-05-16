class_name WallSegmentData
extends Resource

@export var start_position: Vector3 = Vector3.ZERO
@export var end_position: Vector3 = Vector3.ZERO
@export_range(0.25, 8.0, 0.05) var height_m: float = 2.2
@export_range(0.05, 2.0, 0.01) var thickness_m: float = 0.18
@export var color: Color = Color(0.35, 0.34, 0.32, 1.0)

func _init(
	p_start_position: Vector3 = Vector3.ZERO,
	p_end_position: Vector3 = Vector3.ZERO,
	p_height_m: float = 2.2,
	p_thickness_m: float = 0.18,
	p_color: Color = Color(0.35, 0.34, 0.32, 1.0)
) -> void:
	start_position = p_start_position
	end_position = p_end_position
	height_m = p_height_m
	thickness_m = p_thickness_m
	color = p_color

func horizontal_delta() -> Vector3:
	return Vector3(end_position.x - start_position.x, 0.0, end_position.z - start_position.z)

func horizontal_length() -> float:
	return horizontal_delta().length()

func is_valid_segment() -> bool:
	return horizontal_length() > 0.001
