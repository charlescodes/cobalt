class_name LandscapeScatterGenerator
extends "res://src/maps/generators/map_generator.gd"

const MapDataResourceScript := preload("res://src/maps/map_data.gd")
const MapPipelineCompilerScript := preload("res://src/maps/map_pipeline_compiler.gd")
const GroundDataScript := preload("res://src/maps/ground_data.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

@export var seed: int = 1337
@export var scatter_bounds: Rect2 = Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0))
@export_range(0.0, 80.0, 0.5) var tree_density_per_100sqm: float = 8.0
@export_range(0.2, 8.0, 0.1) var tree_min_spacing_m: float = 1.8
@export_range(0, 64, 1) var rock_outcropping_count: int = 6
@export_range(0.2, 8.0, 0.1) var rock_min_spacing_m: float = 2.2
@export_range(8, 256, 1) var max_attempts_per_object: int = 48
@export var tree_size_m: Vector3 = Vector3(0.7, 2.4, 0.7)
@export var rock_size_m: Vector3 = Vector3(1.2, 0.7, 0.9)

func _init() -> void:
	generator_id = &"landscape_scatter"

func generate(input_map_data: MapDataResourceScript) -> MapDataResourceScript:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(maxi(seed, 0))

	var occupied_positions := _occupied_positions(input_map_data)
	var used_ids := _used_object_ids(input_map_data)
	var generated_objects: Array[WorldObjectDataScript] = []
	var tree_count := _tree_count()
	_append_scattered_objects(
		generated_objects,
		occupied_positions,
		used_ids,
		rng,
		&"tree",
		tree_count,
		tree_min_spacing_m,
		tree_size_m,
		Color(0.16, 0.36, 0.18, 1.0)
	)
	_append_scattered_objects(
		generated_objects,
		occupied_positions,
		used_ids,
		rng,
		&"rock_outcropping",
		rock_outcropping_count,
		rock_min_spacing_m,
		rock_size_m,
		Color(0.38, 0.38, 0.36, 1.0)
	)

	var generated_grounds: Array[GroundDataScript] = []
	var generated_walls: Array[WallSegmentDataScript] = []
	var generated_map := MapDataResourceScript.new("", generated_grounds, generated_walls, generated_objects)
	return MapPipelineCompilerScript.merge_map_data(input_map_data, generated_map)

func _tree_count() -> int:
	var area_sqm := maxf(scatter_bounds.size.x, 0.0) * maxf(scatter_bounds.size.y, 0.0)
	return int(round((area_sqm / 100.0) * maxf(tree_density_per_100sqm, 0.0)))

func _append_scattered_objects(
	out_objects: Array[WorldObjectDataScript],
	occupied_positions: Array[Vector3],
	used_ids: Dictionary,
	rng: RandomNumberGenerator,
	object_kind: StringName,
	count: int,
	min_spacing_m: float,
	size_m: Vector3,
	color: Color
) -> void:
	var created := 0
	var attempts := 0
	var max_attempts := maxi(count * max_attempts_per_object, max_attempts_per_object)
	while created < count and attempts < max_attempts:
		attempts += 1
		var candidate := _random_position(rng)
		if not _is_far_enough(candidate, occupied_positions, min_spacing_m):
			continue

		var object_id := _next_available_object_id(object_kind, created, used_ids)
		var object_data := WorldObjectDataScript.new(
			object_id,
			object_kind,
			candidate,
			size_m,
			color,
			true
		)
		out_objects.append(object_data)
		occupied_positions.append(candidate)
		used_ids[object_id] = true
		created += 1

func _random_position(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(
		rng.randf_range(scatter_bounds.position.x, scatter_bounds.end.x),
		0.0,
		rng.randf_range(scatter_bounds.position.y, scatter_bounds.end.y)
	)

func _is_far_enough(candidate: Vector3, occupied_positions: Array[Vector3], min_spacing_m: float) -> bool:
	var min_distance_squared := min_spacing_m * min_spacing_m
	for position in occupied_positions:
		var delta := Vector2(candidate.x - position.x, candidate.z - position.z)
		if delta.length_squared() < min_distance_squared:
			return false
	return true

func _occupied_positions(input_map_data: MapDataResourceScript) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if input_map_data == null:
		return positions

	for object_data in input_map_data.world_objects:
		if object_data != null:
			positions.append(object_data.position)
	return positions

func _used_object_ids(input_map_data: MapDataResourceScript) -> Dictionary:
	var ids := {}
	if input_map_data == null:
		return ids

	for object_data in input_map_data.world_objects:
		if object_data != null and object_data.object_id != &"":
			ids[object_data.object_id] = true
	return ids

func _next_available_object_id(
	object_kind: StringName,
	index: int,
	used_ids: Dictionary
) -> StringName:
	var object_id := StringName("%s_%03d" % [String(object_kind), index])
	var next_index := index
	while used_ids.has(object_id):
		next_index += 1
		object_id = StringName("%s_%03d" % [String(object_kind), next_index])
	return object_id
