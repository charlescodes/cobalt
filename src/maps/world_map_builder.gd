class_name WorldMapBuilder
extends RefCounted

const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")
const WorldGeologyGeneratorScript := preload("res://src/generation/world_geology_generator.gd")
const WorldMapDataScript := preload("res://src/maps/world_map_data.gd")

const WORLD_PICK_SURFACE_NAME: StringName = &"WorldPickSurface"
const WORLD_MAP_3D_LAYER_NAME: StringName = &"WorldMap3DLayer"
const WORLD_PICK_SURFACE_META: StringName = &"world_pick_surface"
const WORLD_PICK_SURFACE_HEIGHT_M: float = 0.1

static func build(world_map_data: WorldMapDataScript, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = String(MapBuilderScript.GENERATED_ROOT_NAME)
	_add_world_roots(root, world_map_data)
	if parent != null:
		parent.add_child(root)
	return root

static func _add_world_roots(root: Node3D, world_map_data: WorldMapDataScript) -> void:
	if world_map_data == null or world_map_data.geology == null:
		return

	_add_world_pick_surface(root, world_map_data)
	_add_world_map_3d_layer(root, world_map_data.geology)

static func _add_world_pick_surface(parent: Node3D, world_map_data: WorldMapDataScript) -> StaticBody3D:
	var geology_data := world_map_data.geology
	if geology_data == null or not _is_positive_size(geology_data.size_m):
		return null

	var body := StaticBody3D.new()
	body.name = String(WORLD_PICK_SURFACE_NAME)
	body.position = Vector3(0.0, -(WORLD_PICK_SURFACE_HEIGHT_M * 0.5), 0.0)
	body.collision_layer = 1
	body.collision_mask = 1
	body.input_ray_pickable = true
	body.set_meta(WORLD_PICK_SURFACE_META, true)
	_tag_editor_selectable(
		body,
		world_map_data,
		MapBuilderScript.EDITOR_KIND_GROUND,
		0,
		body
	)
	parent.add_child(body)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(
		geology_data.size_m.x,
		WORLD_PICK_SURFACE_HEIGHT_M,
		geology_data.size_m.y
	)
	collision.shape = box_shape
	body.add_child(collision)
	return body

static func _add_world_map_3d_layer(parent: Node3D, geology_data: WorldGeologyDataScript) -> MeshInstance3D:
	var generated := WorldGeologyGeneratorScript.generate(geology_data)
	if generated.is_empty():
		return null

	var vertices: PackedVector3Array = generated.get("vertices", PackedVector3Array())
	var colors: PackedColorArray = generated.get("colors", PackedColorArray())
	var indices: PackedInt32Array = generated.get("indices", PackedInt32Array())
	var size_m: Vector2 = generated.get("size_m", geology_data.size_m)
	if vertices.is_empty() or colors.size() != vertices.size() or indices.is_empty():
		return null
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for normal_index in range(normals.size()):
		normals[normal_index] = Vector3.UP

	var mesh_arrays := []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_COLOR] = colors
	mesh_arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = String(WORLD_MAP_3D_LAYER_NAME)
	mesh_instance.mesh = array_mesh
	mesh_instance.material_override = material
	mesh_instance.position.y = 0.2
	mesh_instance.custom_aabb = AABB(
		Vector3(-size_m.x * 0.5, -1000.0, -size_m.y * 0.5),
		Vector3(size_m.x, WorldGeologyGeneratorScript.MAX_ELEVATION_M + 2000.0, size_m.y)
	)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)
	return mesh_instance

static func _is_positive_size(size_m: Vector2) -> bool:
	return size_m.x > 0.001 and size_m.y > 0.001

static func _tag_editor_selectable(
	node: Node,
	source_data: Resource,
	source_kind: StringName,
	source_index: int,
	select_root: Node
) -> void:
	if node == null:
		return

	node.set_meta(MapBuilderScript.EDITOR_SOURCE_META, source_data)
	node.set_meta(MapBuilderScript.EDITOR_KIND_META, source_kind)
	node.set_meta(MapBuilderScript.EDITOR_INDEX_META, source_index)
	node.set_meta(MapBuilderScript.EDITOR_ROOT_META, select_root)
