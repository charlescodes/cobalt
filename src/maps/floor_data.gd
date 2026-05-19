class_name FloorData
extends Resource

@export var floor_id: StringName = &""
@export var position: Vector3 = Vector3.ZERO
@export var size_m: Vector3 = Vector3(8.0, 0.1, 8.0)
@export var color: Color = Color(0.19, 0.22, 0.2, 1.0)

func _init(
	p_floor_id: StringName = &"",
	p_position: Vector3 = Vector3.ZERO,
	p_size_m: Vector3 = Vector3(8.0, 0.1, 8.0),
	p_color: Color = Color(0.19, 0.22, 0.2, 1.0)
) -> void:
	floor_id = p_floor_id
	position = p_position
	size_m = p_size_m
	color = p_color
