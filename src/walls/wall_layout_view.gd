class_name WallLayoutView
extends Node3D

const HexDataScript := preload("res://src/grid/hex_data.gd")
const HexGridManagerScript := preload("res://src/grid/hex_grid_manager.gd")
const HexViewScript := preload("res://src/grid/hex_view.gd")
const WallCellResolverScript := preload("res://src/walls/wall_cell_resolver.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WallVisualResolverScript := preload("res://src/walls/wall_visual_resolver.gd")

const VISUAL_ROOT_NAME: StringName = &"WallVisuals"

@export var grid_manager_path: NodePath = ^"../HexGridManager"
@export var wall_segments: Array[WallSegmentDataScript] = []
@export var apply_on_ready: bool = true
@export var wall_terrain_id: StringName = &"wall"

func _ready() -> void:
	if apply_on_ready:
		call_deferred("apply_layout")

func apply_layout() -> Array[Vector3i]:
	var grid_manager := _resolve_grid_manager()
	if grid_manager == null:
		return []

	var blocked_keys := get_blocked_keys()
	for key in blocked_keys:
		var hex_data := grid_manager.get_hexes().get(key) as HexDataScript
		if hex_data == null:
			continue

		hex_data.is_walkable = false
		hex_data.terrain_id = wall_terrain_id
		_refresh_hex_view(grid_manager, key)

	_rebuild_visuals()
	return blocked_keys

func get_blocked_keys() -> Array[Vector3i]:
	var blocked_keys: Array[Vector3i] = []
	for segment in wall_segments:
		for key in WallCellResolverScript.blocked_keys_for_segment(segment):
			if not blocked_keys.has(key):
				blocked_keys.append(key)

	return blocked_keys

func _rebuild_visuals() -> void:
	var visual_root := _get_or_create_visual_root()
	for child in visual_root.get_children():
		child.free()

	for segment in wall_segments:
		if segment == null:
			continue

		var endpoints := WallVisualResolverScript.visual_endpoints(segment)
		if endpoints.size() != 2:
			continue

		_add_wall_visual(visual_root, segment, endpoints[0], endpoints[1])

func _add_wall_visual(parent: Node, segment: WallSegmentDataScript, start: Vector3, end: Vector3) -> void:
	var delta := end - start
	var length := maxf(Vector2(delta.x, delta.z).length(), segment.thickness_m)

	var wall := MeshInstance3D.new()
	wall.name = "Wall_%d_%d_to_%d_%d" % [segment.start_q, segment.start_r, segment.end_q, segment.end_r]
	wall.position = (start + end) * 0.5
	wall.position.y = segment.height_m * 0.5
	wall.rotation.y = atan2(delta.x, delta.z)

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(segment.thickness_m, segment.height_m, length)
	wall.mesh = box_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = segment.color
	wall.material_override = material
	parent.add_child(wall)

func _refresh_hex_view(grid_manager: HexGridManagerScript, key: Vector3i) -> void:
	for child in grid_manager.get_children():
		var hex_view := child as HexViewScript
		if hex_view != null and hex_view.hex_data != null and hex_view.hex_data.key() == key:
			hex_view.apply_data()
			return

func _get_or_create_visual_root() -> Node3D:
	var visual_root := get_node_or_null(String(VISUAL_ROOT_NAME)) as Node3D
	if visual_root != null:
		return visual_root

	visual_root = Node3D.new()
	visual_root.name = String(VISUAL_ROOT_NAME)
	add_child(visual_root)
	return visual_root

func _resolve_grid_manager() -> HexGridManagerScript:
	return get_node_or_null(grid_manager_path) as HexGridManagerScript
