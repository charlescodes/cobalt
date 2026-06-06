class_name MapBuilder
extends RefCounted

const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const GroundDataScript := preload("res://src/environment/ground_data.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WallVisualResolverScript := preload("res://src/environment/wall_visual_resolver.gd")
const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")
const WorldGeologyGeneratorScript := preload("res://src/generation/world_geology_generator.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const GENERATED_ROOT_NAME: StringName = &"GeneratedMap"
const STATIC_GROUNDS_NAME: StringName = &"StaticGrounds"
const STATIC_WALLS_NAME: StringName = &"StaticWalls"
const DOOR_SOCKETS_NAME: StringName = &"DoorSockets"
const WORLD_OBJECTS_NAME: StringName = &"WorldObjects"
const WORLD_MAP_3D_LAYER_NAME: StringName = &"WorldMap3DLayer"
const EDITOR_SOURCE_META: StringName = &"editor_source_resource"
const EDITOR_KIND_META: StringName = &"editor_source_kind"
const EDITOR_INDEX_META: StringName = &"editor_source_index"
const EDITOR_ROOT_META: StringName = &"editor_select_root"
const EDITOR_KIND_GROUND: StringName = &"ground"
const EDITOR_KIND_WALL: StringName = &"wall"
const EDITOR_KIND_DOOR_SOCKET: StringName = &"door_socket"
const EDITOR_KIND_WORLD_OBJECT: StringName = &"world_object"
const WORLD_GROUND_PICK_META: StringName = &"world_ground_pick_surface"
const DOOR_SOCKET_MARKER_HEIGHT_M: float = 0.025
const DOOR_SOCKET_PICK_HEIGHT_M: float = 0.25
const DOOR_SOCKET_MARKER_SEGMENTS: int = 48

static func build(map_data: MapDataScript, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = String(GENERATED_ROOT_NAME)
	_add_roots(root, map_data)
	if parent != null:
		parent.add_child(root)
	return root

static func _add_roots(root: Node3D, map_data: MapDataScript) -> void:
	var grounds_root := _new_root(STATIC_GROUNDS_NAME)
	var walls_root := _new_root(STATIC_WALLS_NAME)
	var door_sockets_root := _new_root(DOOR_SOCKETS_NAME)
	var objects_root := _new_root(WORLD_OBJECTS_NAME)
	root.add_child(grounds_root)
	root.add_child(walls_root)
	root.add_child(door_sockets_root)
	root.add_child(objects_root)

	if map_data == null:
		return

	var is_world_map := map_data.world_geology != null
	for ground_index in range(map_data.grounds.size()):
		_add_ground(grounds_root, map_data.grounds[ground_index], ground_index, not is_world_map)
	for wall_index in range(map_data.static_walls.size()):
		_add_wall(walls_root, map_data.static_walls[wall_index], wall_index)
	for socket_index in range(map_data.door_sockets.size()):
		_add_door_socket(door_sockets_root, map_data.door_sockets[socket_index], socket_index)
	for object_index in range(map_data.world_objects.size()):
		_add_world_object(objects_root, map_data.world_objects[object_index], object_index)
	if is_world_map:
		_add_world_map_3d_layer(root, map_data.world_geology)

static func _add_ground(
	parent: Node3D,
	ground: GroundDataScript,
	ground_index: int,
	should_add_visual: bool = true
) -> void:
	if ground == null or not _is_positive_size(ground.size_m):
		return

	var body := StaticBody3D.new()
	body.name = _data_name(ground.ground_id, "Ground_%02d" % ground_index)
	body.position = ground.position
	body.collision_layer = 1
	body.collision_mask = 1
	_tag_editor_selectable(body, ground, EDITOR_KIND_GROUND, ground_index, body)
	parent.add_child(body)

	if should_add_visual:
		var box_mesh := BoxMesh.new()
		box_mesh.size = ground.size_m

		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = box_mesh
		mesh.material_override = _material(ground.color)
		body.add_child(mesh)
	else:
		body.set_meta(WORLD_GROUND_PICK_META, true)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = ground.size_m
	collision.shape = box_shape
	body.add_child(collision)

	_add_ground_move_target(body, ground, ground_index)

static func _add_ground_move_target(parent: Node3D, ground: GroundDataScript, ground_index: int) -> void:
	var target := InteractionTargetScript.new()
	target.name = "GroundMoveTarget"
	target.target_domain = &"move_target"
	target.target_data = MoveTargetDataScript.new(_ground_surface_center(ground))
	target.can_highlight = false
	target.interaction_enabled = true
	target.collision_layer = 1
	target.collision_mask = 0
	target.input_ray_pickable = true
	_tag_editor_selectable(target, ground, EDITOR_KIND_GROUND, ground_index, parent)
	parent.add_child(target)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.position = Vector3(0.0, ground.size_m.y * 0.5, 0.0)
	var box_shape := BoxShape3D.new()
	box_shape.size = ground.size_m
	collision.shape = box_shape
	target.add_child(collision)

static func _add_wall(parent: Node3D, wall_data: WallDataScript, wall_index: int) -> void:
	if wall_data == null or not wall_data.is_valid_wall():
		return

	var wall := Node3D.new()
	wall.name = "Wall_%02d" % wall_index
	wall.position = WallVisualResolverScript.visual_center(wall_data)
	_tag_editor_selectable(wall, wall_data, EDITOR_KIND_WALL, wall_index, wall)
	parent.add_child(wall)

	var wall_mesh := WallVisualResolverScript.build_visual_mesh(wall_data)
	if wall_mesh == null:
		return

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = wall_mesh
	mesh.transform = WallVisualResolverScript.visual_local_transform(wall_data)
	mesh.material_override = _material(wall_data.color)
	wall.add_child(mesh)

	var static_body := StaticBody3D.new()
	static_body.name = "StaticBody3D"
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	_tag_editor_selectable(static_body, wall_data, EDITOR_KIND_WALL, wall_index, wall)
	wall.add_child(static_body)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.transform = WallVisualResolverScript.visual_local_transform(wall_data)
	var box_shape := BoxShape3D.new()
	box_shape.size = WallVisualResolverScript.visual_size(wall_data)
	collision.shape = box_shape
	static_body.add_child(collision)

static func _add_door_socket(
	parent: Node3D,
	socket_data: DoorSocketDataScript,
	socket_index: int
) -> void:
	if socket_data == null or not socket_data.is_valid_socket():
		return

	var marker_root := Node3D.new()
	marker_root.name = _data_name(socket_data.socket_id, "DoorSocket_%02d" % socket_index)
	marker_root.position = socket_data.position
	marker_root.rotation.y = socket_data.rotation_y
	_tag_editor_selectable(marker_root, socket_data, EDITOR_KIND_DOOR_SOCKET, socket_index, marker_root)
	parent.add_child(marker_root)

	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = socket_data.width_m * 0.5
	cylinder_mesh.bottom_radius = socket_data.width_m * 0.5
	cylinder_mesh.height = DOOR_SOCKET_MARKER_HEIGHT_M
	cylinder_mesh.radial_segments = DOOR_SOCKET_MARKER_SEGMENTS

	var mesh := MeshInstance3D.new()
	mesh.name = "Marker"
	mesh.position = Vector3(0.0, DOOR_SOCKET_MARKER_HEIGHT_M * 0.5, 0.0)
	mesh.mesh = cylinder_mesh
	mesh.material_override = _door_socket_material(socket_data.color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker_root.add_child(mesh)

	var pick_area := Area3D.new()
	pick_area.name = "EditorPickArea"
	pick_area.collision_layer = 1
	pick_area.collision_mask = 0
	pick_area.input_ray_pickable = true
	_tag_editor_selectable(pick_area, socket_data, EDITOR_KIND_DOOR_SOCKET, socket_index, marker_root)
	marker_root.add_child(pick_area)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.position = Vector3(0.0, DOOR_SOCKET_PICK_HEIGHT_M * 0.5, 0.0)
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = socket_data.width_m * 0.5
	cylinder_shape.height = DOOR_SOCKET_PICK_HEIGHT_M
	collision.shape = cylinder_shape
	pick_area.add_child(collision)

static func _add_world_object(parent: Node3D, object_data: WorldObjectDataScript, object_index: int) -> void:
	if object_data == null:
		return

	var object_view := BlockoutObjectViewScript.new()
	object_view.name = _data_name(object_data.object_id, "WorldObject_%02d" % object_index)
	object_view.object_data = object_data
	_tag_editor_selectable(object_view, object_data, EDITOR_KIND_WORLD_OBJECT, object_index, object_view)
	parent.add_child(object_view)
	var target := object_view.get_node_or_null("InteractionTarget")
	if target != null:
		_tag_editor_selectable(target, object_data, EDITOR_KIND_WORLD_OBJECT, object_index, object_view)

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

static func _new_root(root_name: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = String(root_name)
	return root

static func _data_name(id: StringName, fallback_name: String) -> String:
	var value := String(id)
	return fallback_name if value.is_empty() else value

static func _ground_surface_center(ground: GroundDataScript) -> Vector3:
	return ground.position + Vector3(0.0, ground.size_m.y * 0.5, 0.0)

static func _is_positive_size(size_m: Vector3) -> bool:
	return size_m.x > 0.001 and size_m.y > 0.001 and size_m.z > 0.001

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

static func _door_socket_material(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

static func _tag_editor_selectable(
	node: Node,
	source_data: Resource,
	source_kind: StringName,
	source_index: int,
	select_root: Node
) -> void:
	if node == null:
		return

	node.set_meta(EDITOR_SOURCE_META, source_data)
	node.set_meta(EDITOR_KIND_META, source_kind)
	node.set_meta(EDITOR_INDEX_META, source_index)
	node.set_meta(EDITOR_ROOT_META, select_root)
