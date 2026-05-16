class_name MoveTargetData
extends Resource

@export var position: Vector3 = Vector3.ZERO

func _init(p_position: Vector3 = Vector3.ZERO) -> void:
	position = p_position
