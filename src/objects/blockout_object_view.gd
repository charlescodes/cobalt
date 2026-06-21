class_name BlockoutObjectView
extends CharacterBody3D

const ACTOR_COLLISION_DEBUG_GROUP: StringName = &"actor_collision_debug_sources"

const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")

@export var object_data: WorldObjectDataScript:
	set(value):
		object_data = value
		apply_data()

func _ready() -> void:
	add_to_group(ACTOR_COLLISION_DEBUG_GROUP)
	apply_data()

func apply_data() -> void:
	if object_data == null:
		return

	position = object_data.position
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 3
	input_ray_pickable = false
	_configure_body()
	_configure_movement_collision()
	_configure_interaction_target()
	_configure_navigation_agent()

static func body_center_offset(size_m: Vector3) -> Vector3:
	return Vector3(0.0, size_m.y * 0.5, 0.0)

func get_navigation_agent() -> NavigationAgent3D:
	return _get_or_create_navigation_agent()

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

func _configure_movement_collision() -> void:
	var collision := get_node_or_null("MovementCollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "MovementCollisionShape3D"
		add_child(collision)

	var cylinder_shape := collision.shape as CylinderShape3D
	if cylinder_shape == null:
		cylinder_shape = CylinderShape3D.new()
		collision.shape = cylinder_shape

	cylinder_shape.radius = maxf(object_data.size_m.x, object_data.size_m.z) * 0.5
	cylinder_shape.height = object_data.size_m.y
	collision.position = body_center_offset(object_data.size_m)

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

func _configure_navigation_agent() -> void:
	var agent := _get_or_create_navigation_agent()
	agent.path_desired_distance = 0.1
	agent.target_desired_distance = 0.1
	agent.navigation_layers = 1
	agent.avoidance_enabled = false

func _get_or_create_navigation_agent() -> NavigationAgent3D:
	var agent := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		return agent

	agent = NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	add_child(agent)
	return agent
