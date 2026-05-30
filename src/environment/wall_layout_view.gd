class_name WallLayoutView
extends Node3D

const WallSegmentDataScript := preload("res://src/environment/wall_segment_data.gd")
const WallVisualResolverScript := preload("res://src/environment/wall_visual_resolver.gd")

const VISUAL_ROOT_NAME: StringName = &"WallVisuals"

@export var wall_segments: Array[WallSegmentDataScript] = []
@export var navigation_region_path: NodePath = ^".."
@export var apply_on_ready: bool = true
@export var rebake_navigation_on_apply: bool = true

func _ready() -> void:
	if apply_on_ready:
		call_deferred("apply_layout")

func apply_layout() -> void:
	_rebuild_visuals()
	_rebake_navigation()

func _rebuild_visuals() -> void:
	var visual_root := _get_or_create_visual_root()
	for child in visual_root.get_children():
		child.free()

	var wall_index := 0
	for segment in wall_segments:
		if segment == null or not segment.is_valid_segment():
			continue

		var endpoints := WallVisualResolverScript.visual_endpoints(segment)
		if endpoints.size() != 2:
			continue

		_add_wall_visual(visual_root, segment, wall_index)
		wall_index += 1

func _add_wall_visual(parent: Node, segment: WallSegmentDataScript, wall_index: int) -> void:
	var wall := Node3D.new()
	wall.name = "Wall_%02d" % wall_index
	wall.position = WallVisualResolverScript.visual_center(segment)
	wall.rotation.y = WallVisualResolverScript.visual_rotation_y(segment)

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(segment.thickness_m, segment.height_m, WallVisualResolverScript.visual_length(segment))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = box_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = segment.color
	mesh_instance.material_override = material
	wall.add_child(mesh_instance)

	var static_body := StaticBody3D.new()
	static_body.name = "StaticBody3D"
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	wall.add_child(static_body)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = box_mesh.size
	collision_shape.shape = box_shape
	static_body.add_child(collision_shape)

	parent.add_child(wall)

func _get_or_create_visual_root() -> Node3D:
	var visual_root := get_node_or_null(String(VISUAL_ROOT_NAME)) as Node3D
	if visual_root != null:
		return visual_root

	visual_root = Node3D.new()
	visual_root.name = String(VISUAL_ROOT_NAME)
	add_child(visual_root)
	return visual_root

func _rebake_navigation() -> void:
	if not rebake_navigation_on_apply:
		return

	var navigation_region := _resolve_navigation_region()
	if navigation_region == null:
		return

	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()

	var navigation_mesh := navigation_region.navigation_mesh
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_collision_mask = 1
	navigation_region.bake_navigation_mesh(false)

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
