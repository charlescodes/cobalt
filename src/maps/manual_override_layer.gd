class_name ManualOverrideLayer
extends Resource

const ManualObjectOverrideScript := preload("res://src/maps/manual_object_override.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

@export var object_overrides: Array[ManualObjectOverrideScript] = []

func has_overrides() -> bool:
	return not object_overrides.is_empty()

func set_object_position_override(object_id: StringName, position: Vector3) -> void:
	if object_id == &"":
		return

	var existing := _object_override_by_id(object_id)
	if existing != null:
		existing.position = position
		existing.override_position = true
		return

	object_overrides.append(ManualObjectOverrideScript.new(object_id, position, true))

func apply_to_map_data(map_data: MapDataScript) -> void:
	if map_data == null:
		return

	for object_data in map_data.world_objects:
		var override := _object_override_by_id(object_data.object_id if object_data != null else &"")
		if override == null:
			continue
		_apply_object_override(object_data, override)

func _object_override_by_id(object_id: StringName) -> ManualObjectOverrideScript:
	if object_id == &"":
		return null

	for override in object_overrides:
		if override != null and override.object_id == object_id:
			return override

	return null

func _apply_object_override(
	object_data: WorldObjectDataScript,
	override: ManualObjectOverrideScript
) -> void:
	if object_data == null or override == null:
		return
	if override.override_position:
		object_data.position = override.position
