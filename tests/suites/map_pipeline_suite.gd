extends RefCounted

const BspBuildingGeneratorScript := preload("res://src/maps/generators/bsp_building_generator.gd")
const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const GroundDataScript := preload("res://src/maps/ground_data.gd")
const LandscapeScatterGeneratorScript := preload("res://src/maps/generators/landscape_scatter_generator.gd")
const ManualOverrideLayerScript := preload("res://src/maps/manual_override_layer.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapGeneratorScript := preload("res://src/maps/generators/map_generator.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const MapPipelineCompilerScript := preload("res://src/maps/map_pipeline_compiler.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var base_map := _base_map()
	var bsp_generator := _bsp_generator()
	var scatter_generator := _scatter_generator()
	var generators: Array[MapGeneratorScript] = [bsp_generator, scatter_generator]

	var manual_overrides := ManualOverrideLayerScript.new()
	manual_overrides.set_object_position_override(&"tree_000", Vector3(9.0, 0.0, 9.0))
	var compiled := MapPipelineCompilerScript.compile(base_map, generators, manual_overrides)
	if compiled == null:
		return ctx.fail("MapPipelineCompiler did not return compiled MapData.")
	if compiled.grounds.size() < 2:
		return ctx.fail("Map pipeline did not preserve base ground and append generated building floor.")
	if compiled.static_walls.size() <= 4:
		return ctx.fail("BspBuildingGenerator did not append generated building walls.")
	if _object_by_id(compiled, &"tree_000") == null:
		return ctx.fail("LandscapeScatterGenerator did not create deterministic tree ids.")
	if _object_by_id(compiled, &"rock_outcropping_000") == null:
		return ctx.fail("LandscapeScatterGenerator did not create rock outcroppings.")
	if _object_by_id(compiled, &"tree_000").position != Vector3(9.0, 0.0, 9.0):
		return ctx.fail("ManualOverrideLayer did not preserve a curated generated-object move.")

	var compiled_without_override := MapPipelineCompilerScript.compile(base_map, generators, null)
	if _object_by_id(compiled_without_override, &"tree_000").position == Vector3(9.0, 0.0, 9.0):
		return ctx.fail("Manual override mutated generator output instead of applying as a layer.")

	if not _verify_map_loader_pipeline(ctx, base_map, scatter_generator, manual_overrides):
		return false

	return true

func _verify_map_loader_pipeline(
	ctx,
	base_map: MapDataScript,
	scatter_generator: MapGeneratorScript,
	manual_overrides: ManualOverrideLayerScript
) -> bool:
	var root := Node3D.new()
	root.name = "PipelineRoot"
	var build_parent := Node3D.new()
	build_parent.name = "BuildParent"
	root.add_child(build_parent)
	var loader := MapLoaderScript.new()
	loader.name = "MapLoader"
	loader.map_data = base_map
	var generators: Array[MapGeneratorScript] = [scatter_generator]
	loader.generator_modules = generators
	loader.manual_override_layer = manual_overrides
	loader.build_parent_path = ^"../BuildParent"
	loader.build_on_ready = false
	loader.bake_navigation_on_load = false
	root.add_child(loader)
	ctx.root().add_child(root)

	var generated_map := loader.load_map()
	if generated_map == null or build_parent.get_node_or_null("GeneratedMap") != generated_map:
		root.free()
		return ctx.fail("MapLoader did not build the compiled generator pipeline output.")
	var compiled := loader.get_compiled_map_data()
	if compiled == null or _object_by_id(compiled, &"tree_000") == null:
		root.free()
		return ctx.fail("MapLoader did not expose compiled pipeline MapData.")
	if generated_map.get_node_or_null("WorldObjects/tree_000") == null:
		root.free()
		return ctx.fail("MapLoader did not instantiate generated scatter objects.")
	var tree_node := generated_map.get_node_or_null("WorldObjects/tree_000") as Node3D
	tree_node.position = Vector3(8.0, 0.0, 8.0)
	loader.capture_manual_object_overrides_from_generated_map()
	var scatter := scatter_generator as LandscapeScatterGeneratorScript
	if scatter != null:
		scatter.seed = 405
	loader.load_map()
	compiled = loader.get_compiled_map_data()
	if _object_by_id(compiled, &"tree_000").position != Vector3(8.0, 0.0, 8.0):
		root.free()
		return ctx.fail("MapLoader did not preserve captured manual object moves across regeneration.")

	root.free()
	return true

func _base_map() -> MapDataScript:
	var grounds: Array[GroundDataScript] = [
		GroundDataScript.new(
			&"base_ground",
			Vector3(0.0, -0.05, 0.0),
			Vector3(12.0, 0.1, 12.0),
			Color(0.18, 0.2, 0.18, 1.0)
		),
	]
	var objects: Array[WorldObjectDataScript] = [
		WorldObjectDataScript.new(
			&"curated_prop",
			&"blockout_object",
			Vector3(-4.0, 0.0, -4.0),
			Vector3(0.5, 0.5, 0.5),
			Color(0.8, 0.7, 0.4, 1.0)
		),
	]
	return MapDataScript.new("pipeline_base", grounds, [], objects)

func _bsp_generator() -> BspBuildingGeneratorScript:
	var data := BspModuleDataScript.new()
	data.map_id = "pipeline_bsp"
	data.building_size_m = Vector2(12.0, 10.0)
	data.min_room_size_m = 3.0
	data.max_split_depth = 2
	data.seed = 808

	var generator := BspBuildingGeneratorScript.new()
	generator.bsp_data = data
	generator.append_to_input = true
	return generator

func _scatter_generator() -> LandscapeScatterGeneratorScript:
	var generator := LandscapeScatterGeneratorScript.new()
	generator.seed = 404
	generator.scatter_bounds = Rect2(Vector2(-5.0, -5.0), Vector2(10.0, 10.0))
	generator.tree_density_per_100sqm = 4.0
	generator.tree_min_spacing_m = 0.8
	generator.rock_outcropping_count = 2
	generator.rock_min_spacing_m = 1.0
	return generator

func _object_by_id(map_data: MapDataScript, object_id: StringName) -> WorldObjectDataScript:
	if map_data == null:
		return null
	for object_data in map_data.world_objects:
		if object_data != null and object_data.object_id == object_id:
			return object_data
	return null
