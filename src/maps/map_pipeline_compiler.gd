class_name MapPipelineCompiler
extends RefCounted

const GroundDataScript := preload("res://src/maps/ground_data.gd")
const ManualOverrideLayerScript := preload("res://src/maps/manual_override_layer.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapGeneratorScript := preload("res://src/maps/generators/map_generator.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

static func compile(
	base_map_data: MapDataScript,
	generators: Array = [],
	manual_override_layer: ManualOverrideLayerScript = null
) -> MapDataScript:
	var current := copy_map_data(base_map_data)
	for generator_resource in generators:
		var generator := generator_resource as MapGeneratorScript
		if generator == null or not generator.enabled:
			continue

		var generated := generator.generate(current)
		if generated != null:
			current = generated

	if manual_override_layer != null:
		manual_override_layer.apply_to_map_data(current)
	return current

static func merge_map_data(base_map_data: MapDataScript, addition: MapDataScript) -> MapDataScript:
	var result := copy_map_data(base_map_data)
	if addition == null:
		return result

	if not addition.map_id.is_empty():
		result.map_id = addition.map_id
	for ground in addition.grounds:
		var ground_copy := copy_ground_data(ground)
		if ground_copy != null:
			result.grounds.append(ground_copy)
	for wall in addition.static_walls:
		var wall_copy := copy_wall_segment_data(wall)
		if wall_copy != null:
			result.static_walls.append(wall_copy)
	for object_data in addition.world_objects:
		var object_copy := copy_world_object_data(object_data)
		if object_copy != null:
			result.world_objects.append(object_copy)
	return result

static func copy_map_data(source: MapDataScript) -> MapDataScript:
	if source == null:
		return MapDataScript.new()

	var grounds: Array[GroundDataScript] = []
	var walls: Array[WallSegmentDataScript] = []
	var objects: Array[WorldObjectDataScript] = []
	for ground in source.grounds:
		var ground_copy := copy_ground_data(ground)
		if ground_copy != null:
			grounds.append(ground_copy)
	for wall in source.static_walls:
		var wall_copy := copy_wall_segment_data(wall)
		if wall_copy != null:
			walls.append(wall_copy)
	for object_data in source.world_objects:
		var object_copy := copy_world_object_data(object_data)
		if object_copy != null:
			objects.append(object_copy)
	return MapDataScript.new(source.map_id, grounds, walls, objects)

static func copy_ground_data(source: GroundDataScript) -> GroundDataScript:
	if source == null:
		return null
	return GroundDataScript.new(source.ground_id, source.position, source.size_m, source.color)

static func copy_wall_segment_data(source: WallSegmentDataScript) -> WallSegmentDataScript:
	if source == null:
		return null
	return WallSegmentDataScript.new(
		source.start_position,
		source.end_position,
		source.height_m,
		source.thickness_m,
		source.color
	)

static func copy_world_object_data(source: WorldObjectDataScript) -> WorldObjectDataScript:
	if source == null:
		return null
	return WorldObjectDataScript.new(
		source.object_id,
		source.object_kind,
		source.position,
		source.size_m,
		source.color,
		source.is_hoverable
	)
