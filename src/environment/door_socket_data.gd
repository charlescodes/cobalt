class_name DoorSocketData
extends Resource

@export var socket_id: StringName = &""
@export var position: Vector3 = Vector3.ZERO
@export_range(0.25, 4.0, 0.05) var width_m: float = 1.0
@export var rotation_y: float = 0.0
@export var color: Color = Color(0.82, 0.9, 0.84, 1.0)

func _init(
	p_socket_id: StringName = &"",
	p_position: Vector3 = Vector3.ZERO,
	p_width_m: float = 1.0,
	p_rotation_y: float = 0.0,
	p_color: Color = Color(0.82, 0.9, 0.84, 1.0)
) -> void:
	socket_id = p_socket_id
	position = p_position
	width_m = p_width_m
	rotation_y = p_rotation_y
	color = p_color

func is_valid_socket() -> bool:
	return width_m > 0.001
