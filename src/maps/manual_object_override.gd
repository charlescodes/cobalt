class_name ManualObjectOverride
extends Resource

@export var object_id: StringName = &""
@export var override_position: bool = true
@export var position: Vector3 = Vector3.ZERO

func _init(
	p_object_id: StringName = &"",
	p_position: Vector3 = Vector3.ZERO,
	p_override_position: bool = true
) -> void:
	object_id = p_object_id
	position = p_position
	override_position = p_override_position
