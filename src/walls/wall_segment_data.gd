class_name WallSegmentData
extends Resource

const SPAN_CORNER_TO_CORNER: StringName = &"corner_to_corner"
const SPAN_SIDE_TO_SIDE: StringName = &"side_to_side"

@export var start_q: int = 0
@export var start_r: int = 0
@export var end_q: int = 0
@export var end_r: int = 0
@export var span_mode: StringName = SPAN_CORNER_TO_CORNER
@export_range(0.25, 8.0, 0.05) var height_m: float = 2.2
@export_range(0.05, 2.0, 0.01) var thickness_m: float = 0.18
@export var color: Color = Color(0.35, 0.34, 0.32, 1.0)

func _init(
	p_start_q: int = 0,
	p_start_r: int = 0,
	p_end_q: int = 0,
	p_end_r: int = 0,
	p_span_mode: StringName = SPAN_CORNER_TO_CORNER,
	p_height_m: float = 2.2,
	p_thickness_m: float = 0.18,
	p_color: Color = Color(0.35, 0.34, 0.32, 1.0)
) -> void:
	start_q = p_start_q
	start_r = p_start_r
	end_q = p_end_q
	end_r = p_end_r
	span_mode = p_span_mode
	height_m = p_height_m
	thickness_m = p_thickness_m
	color = p_color

func start_key() -> Vector3i:
	return Vector3i(start_q, start_r, -start_q - start_r)

func end_key() -> Vector3i:
	return Vector3i(end_q, end_r, -end_q - end_r)

func is_valid_span_mode() -> bool:
	return span_mode == SPAN_CORNER_TO_CORNER or span_mode == SPAN_SIDE_TO_SIDE
