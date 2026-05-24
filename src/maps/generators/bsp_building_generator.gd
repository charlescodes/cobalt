class_name BspBuildingGenerator
extends "res://src/maps/generators/map_generator.gd"

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const MapDataResourceScript := preload("res://src/maps/map_data.gd")
const MapPipelineCompilerScript := preload("res://src/maps/map_pipeline_compiler.gd")

@export var bsp_data: BspModuleDataScript = BspModuleDataScript.new()
@export var append_to_input: bool = true

func _init() -> void:
	generator_id = &"bsp_building"

func generate(input_map_data: MapDataResourceScript) -> MapDataResourceScript:
	var generated_bsp := BspRoomProcessorScript.generate(_resolved_bsp_data())
	var generated_map := BspRoomProcessorScript.compile_to_map_data(generated_bsp)
	if not append_to_input:
		return generated_map

	return MapPipelineCompilerScript.merge_map_data(input_map_data, generated_map)

func _resolved_bsp_data() -> BspModuleDataScript:
	if bsp_data == null:
		bsp_data = BspModuleDataScript.new()
	return bsp_data
