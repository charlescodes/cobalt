class_name WorldMapData
extends Resource

const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")

@export var map_id: String = ""
@export var geology: WorldGeologyDataScript

func _init(
	p_map_id: String = "",
	p_geology: WorldGeologyDataScript = null
) -> void:
	map_id = p_map_id
	geology = p_geology if p_geology != null else WorldGeologyDataScript.new()
