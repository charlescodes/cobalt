class_name WorldObjectData
extends Resource

@export var object_id: StringName = &""
@export var object_kind: StringName = &"blockout_object"
@export var position: Vector3 = Vector3.ZERO
@export var size_m: Vector3 = Vector3.ONE
@export var color: Color = Color.WHITE
@export var is_hoverable: bool = true

func _init(
	p_object_id: StringName = &"",
	p_object_kind: StringName = &"blockout_object",
	p_position: Vector3 = Vector3.ZERO,
	p_size_m: Vector3 = Vector3.ONE,
	p_color: Color = Color.WHITE,
	p_is_hoverable: bool = true
) -> void:
	object_id = p_object_id
	object_kind = p_object_kind
	position = p_position
	size_m = p_size_m
	color = p_color
	is_hoverable = p_is_hoverable
