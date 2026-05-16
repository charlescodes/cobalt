class_name WorldObjectData
extends Resource

@export var object_id: StringName = &""
@export var object_kind: StringName = &"blockout_object"
@export var q: int = 0
@export var r: int = 0
@export var s: int = 0
@export var size_m: Vector3 = Vector3.ONE
@export var color: Color = Color.WHITE
@export var is_hoverable: bool = true

func _init(
	p_object_id: StringName = &"",
	p_object_kind: StringName = &"blockout_object",
	p_q: int = 0,
	p_r: int = 0,
	p_s: int = 0,
	p_size_m: Vector3 = Vector3.ONE,
	p_color: Color = Color.WHITE,
	p_is_hoverable: bool = true
) -> void:
	object_id = p_object_id
	object_kind = p_object_kind
	set_cube_coords(p_q, p_r, p_s)
	size_m = p_size_m
	color = p_color
	is_hoverable = p_is_hoverable

func set_cube_coords(p_q: int, p_r: int, p_s: int) -> void:
	q = p_q
	r = p_r
	s = p_s
	if not is_valid_cube():
		s = -q - r

func set_axial(p_q: int, p_r: int) -> void:
	q = p_q
	r = p_r
	s = -q - r

func key() -> Vector3i:
	return Vector3i(q, r, s)

func is_valid_cube() -> bool:
	return q + r + s == 0
