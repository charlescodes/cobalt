class_name BlockoutObjectView
extends Node3D

const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const HexViewScript := preload("res://src/grid/hex_view.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")
const GridMovementAnimatorScript := preload("res://src/movement/grid_movement_animator.gd")

@export var object_data: WorldObjectDataScript:
	set(value):
		object_data = value
		apply_data()

func _ready() -> void:
	apply_data()

func apply_data() -> void:
	if object_data == null:
		return

	position = grid_to_world(object_data)
	_configure_body()
	_configure_interaction_target()
	_configure_movement_animator()

static func grid_to_world(data: WorldObjectDataScript) -> Vector3:
	if data == null:
		return Vector3.ZERO

	return HexViewScript.axial_to_world(data.q, data.r, 0.0)

static func body_center_offset(size_m: Vector3) -> Vector3:
	return Vector3(0.0, size_m.y * 0.5, 0.0)

func move_along_hex_path(path: Array, speed_mps: float) -> bool:
	var animator := _get_or_create_movement_animator()
	return animator.move_along_hex_path(path, speed_mps)

func _configure_body() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null:
		body = MeshInstance3D.new()
		body.name = "Body"
		add_child(body)

	var box_mesh := body.mesh as BoxMesh
	if box_mesh == null:
		box_mesh = BoxMesh.new()
		body.mesh = box_mesh

	box_mesh.size = object_data.size_m
	body.position = body_center_offset(object_data.size_m)

	var material := StandardMaterial3D.new()
	material.albedo_color = object_data.color
	body.material_override = material

func _configure_interaction_target() -> void:
	var target := get_node_or_null("InteractionTarget") as InteractionTargetScript
	if not object_data.is_hoverable:
		if target != null:
			target.queue_free()
		return

	if target == null:
		target = InteractionTargetScript.new()
		target.name = "InteractionTarget"
		add_child(target)

	target.target_domain = &"world_object"
	target.target_data = object_data
	target.highlight_root_path = ^".."
	target.highlighter_path = ^"HoverHighlighter"
	target.can_highlight = true
	target.interaction_enabled = true
	target.collision_layer = 1
	target.collision_mask = 0
	target.input_ray_pickable = true

	var collision_shape := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		target.add_child(collision_shape)

	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape == null:
		box_shape = BoxShape3D.new()
		collision_shape.shape = box_shape

	box_shape.size = object_data.size_m
	collision_shape.position = body_center_offset(object_data.size_m)

	var highlighter := target.get_node_or_null("HoverHighlighter") as HoverHighlighterScript
	if highlighter == null:
		highlighter = HoverHighlighterScript.new()
		highlighter.name = "HoverHighlighter"
		target.add_child(highlighter)

	highlighter.root_path = ^"../.."

func _configure_movement_animator() -> void:
	_get_or_create_movement_animator()

func _get_or_create_movement_animator() -> GridMovementAnimatorScript:
	var animator := get_node_or_null("GridMovementAnimator") as GridMovementAnimatorScript
	if animator != null:
		return animator

	animator = GridMovementAnimatorScript.new()
	animator.name = "GridMovementAnimator"
	add_child(animator)
	return animator
