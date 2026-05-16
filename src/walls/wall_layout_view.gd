class_name WallLayoutView
extends Node3D

const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WallVisualResolverScript := preload("res://src/walls/wall_visual_resolver.gd")

const VISUAL_ROOT_NAME: StringName = &"WallVisuals"

@export var wall_segments: Array[WallSegmentDataScript] = []
@export var apply_on_ready: bool = true

func _ready() -> void:
	if apply_on_ready:
		call_deferred("apply_layout")

func apply_layout() -> void:
	_rebuild_visuals()

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

func _get_or_create_visual_root() -> Node3D:
	var visual_root := get_node_or_null(String(VISUAL_ROOT_NAME)) as Node3D
	if visual_root != null:
		return visual_root

	visual_root = Node3D.new()
	visual_root.name = String(VISUAL_ROOT_NAME)
	add_child(visual_root)
	return visual_root
