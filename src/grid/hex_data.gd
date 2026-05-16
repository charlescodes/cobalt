class_name HexData
extends Resource

@export var q: int = 0
@export var r: int = 0
@export var s: int = 0
@export var terrain_id: StringName = &"grass"
@export var is_walkable: bool = true

func _init(
	p_q: int = 0,
	p_r: int = 0,
	p_s: int = 0,
	p_terrain_id: StringName = &"grass",
	p_is_walkable: bool = true
) -> void:
	q = p_q
	r = p_r
	s = p_s
	if not is_valid_cube():
		s = -q - r

	terrain_id = p_terrain_id
	is_walkable = p_is_walkable

func set_axial(p_q: int, p_r: int) -> void:
	q = p_q
	r = p_r
	s = -q - r

func cube_coords() -> Vector3i:
	return Vector3i(q, r, s)

func key() -> Vector3i:
	return cube_coords()

func is_valid_cube() -> bool:
	return q + r + s == 0
