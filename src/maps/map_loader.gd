class_name MapLoader
extends Node

const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")

@export var map_data: MapDataScript
@export var build_parent_path: NodePath = ^"../NavigationRegion3D"
@export var navigation_region_path: NodePath = ^"../NavigationRegion3D"
@export var build_on_ready: bool = true
@export var bake_navigation_on_load: bool = true

var generated_map: Node3D

func _ready() -> void:
	if build_on_ready:
		load_map()

func load_map() -> Node3D:
	var build_parent := get_node_or_null(build_parent_path) as Node3D
	if build_parent == null:
		build_parent = get_parent() as Node3D
	if build_parent == null or map_data == null:
		return null

	_clear_generated_map(build_parent)
	generated_map = MapBuilderScript.build(map_data, build_parent)
	if bake_navigation_on_load:
		rebake_navigation()
	return generated_map

func rebake_navigation() -> void:
	var navigation_region := _resolve_navigation_region()
	if navigation_region == null:
		return
	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()

	var navigation_mesh := navigation_region.navigation_mesh
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_collision_mask = 1
	navigation_region.bake_navigation_mesh(false)

func _clear_generated_map(parent: Node3D) -> void:
	var existing := parent.get_node_or_null(String(MapBuilderScript.GENERATED_ROOT_NAME))
	if existing != null:
		existing.free()

func _resolve_navigation_region() -> NavigationRegion3D:
	var configured_region := get_node_or_null(navigation_region_path) as NavigationRegion3D
	if configured_region != null:
		return configured_region

	var node := get_parent()
	while node != null:
		var navigation_region := node as NavigationRegion3D
		if navigation_region != null:
			return navigation_region
		node = node.get_parent()

	return null
