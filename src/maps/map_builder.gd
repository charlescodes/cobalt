class_name MapBuilder
extends RefCounted

const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const GroundDataScript := preload("res://src/environment/ground_data.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const WallSegmentDataScript := preload("res://src/environment/wall_segment_data.gd")
const WallVisualResolverScript := preload("res://src/environment/wall_visual_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const GENERATED_ROOT_NAME: StringName = &"GeneratedMap"
const STATIC_GROUNDS_NAME: StringName = &"StaticGrounds"
const STATIC_WALLS_NAME: StringName = &"StaticWalls"
const WORLD_OBJECTS_NAME: StringName = &"WorldObjects"
const EDITOR_SOURCE_META: StringName = &"editor_source_resource"
const EDITOR_KIND_META: StringName = &"editor_source_kind"
const EDITOR_INDEX_META: StringName = &"editor_source_index"
const EDITOR_ROOT_META: StringName = &"editor_select_root"
const EDITOR_KIND_GROUND: StringName = &"ground"
const EDITOR_KIND_WALL: StringName = &"wall"
const EDITOR_KIND_WORLD_OBJECT: StringName = &"world_object"

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
	var objects_root := _new_root(WORLD_OBJECTS_NAME)
	root.add_child(grounds_root)
	root.add_child(walls_root)
	root.add_child(objects_root)

	if map_data == null:
		return

	for ground_index in range(map_data.grounds.size()):
		_add_ground(grounds_root, map_data.grounds[ground_index], ground_index)
	for wall_index in range(map_data.static_walls.size()):
		_add_wall(walls_root, map_data.static_walls[wall_index], wall_index)
	for object_index in range(map_data.world_objects.size()):
		_add_world_object(objects_root, map_data.world_objects[object_index], object_index)

static func _add_ground(parent: Node3D, ground: GroundDataScript, ground_index: int) -> void:
	if ground == null or not _is_positive_size(ground.size_m):
		return

	var body := StaticBody3D.new()
	body.name = _data_name(ground.ground_id, "Ground_%02d" % ground_index)
	body.position = ground.position
	body.collision_layer = 1
	body.collision_mask = 1
	_tag_editor_selectable(body, ground, EDITOR_KIND_GROUND, ground_index, body)
	parent.add_child(body)

	var box_mesh := BoxMesh.new()
	box_mesh.size = ground.size_m

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = box_mesh
	mesh.material_override = _material(ground.color)
	body.add_child(mesh)

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

static func _add_wall(parent: Node3D, segment: WallSegmentDataScript, wall_index: int) -> void:
	if segment == null or not segment.is_valid_segment():
		return

	var wall := Node3D.new()
	wall.name = "Wall_%02d" % wall_index
	wall.position = WallVisualResolverScript.visual_center(segment)
	wall.rotation.y = WallVisualResolverScript.visual_rotation_y(segment)
	_tag_editor_selectable(wall, segment, EDITOR_KIND_WALL, wall_index, wall)
	parent.add_child(wall)

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(
		segment.thickness_m,
		segment.height_m,
		WallVisualResolverScript.visual_length(segment)
	)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = box_mesh
	mesh.material_override = _material(segment.color)
	wall.add_child(mesh)

	var static_body := StaticBody3D.new()
	static_body.name = "StaticBody3D"
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	_tag_editor_selectable(static_body, segment, EDITOR_KIND_WALL, wall_index, wall)
	wall.add_child(static_body)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = box_mesh.size
	collision.shape = box_shape
	static_body.add_child(collision)

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
