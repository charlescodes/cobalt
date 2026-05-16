class_name HexView
extends MeshInstance3D

const HexDataScript := preload("res://src/grid/hex_data.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")

const HEX_SIDE_TO_SIDE_M: float = 1.0
const HEX_RADIUS_M: float = HEX_SIDE_TO_SIDE_M / sqrt(3.0)
const HEX_MESH_Y_ROTATION_RADIANS: float = PI / 6.0
const DEFAULT_HEIGHT_M: float = 0.08

@export var hex_data: HexDataScript:
	set(value):
		hex_data = value
		apply_data()

@export var tile_height_m: float = DEFAULT_HEIGHT_M:
	set(value):
		tile_height_m = maxf(value, 0.01)
		_configure_mesh()
		_configure_interaction_target()
		apply_data()

func _ready() -> void:
	_configure_mesh()
	_configure_interaction_target()
	apply_data()

static func axial_to_world(p_q: int, p_r: int, p_y: float = 0.0) -> Vector3:
	var x := HEX_RADIUS_M * 1.5 * float(p_q)
	var z := HEX_RADIUS_M * sqrt(3.0) * (float(p_r) + (float(p_q) * 0.5))
	return Vector3(x, p_y, z)

func apply_data() -> void:
	if hex_data == null:
		return

	_configure_mesh()
	_configure_interaction_target()
	position = axial_to_world(hex_data.q, hex_data.r, tile_height_m * 0.5)
	name = "Hex_%d_%d_%d" % [hex_data.q, hex_data.r, hex_data.s]
	_apply_material()

func _configure_mesh() -> void:
	var hex_mesh := mesh as CylinderMesh
	if hex_mesh == null:
		hex_mesh = CylinderMesh.new()
		mesh = hex_mesh

	hex_mesh.top_radius = HEX_RADIUS_M
	hex_mesh.bottom_radius = HEX_RADIUS_M
	hex_mesh.height = tile_height_m
	hex_mesh.radial_segments = 6
	rotation.y = HEX_MESH_Y_ROTATION_RADIANS

func _configure_interaction_target() -> void:
	var target := get_node_or_null("InteractionTarget") as InteractionTargetScript
	if target == null:
		target = InteractionTargetScript.new()
		target.name = "InteractionTarget"
		add_child(target)

	target.target_domain = &"hex"
	target.target_data = hex_data
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

	var shape := collision_shape.shape as CylinderShape3D
	if shape == null:
		shape = CylinderShape3D.new()
		collision_shape.shape = shape

	shape.radius = HEX_RADIUS_M
	shape.height = tile_height_m

	var highlighter := target.get_node_or_null("HoverHighlighter") as HoverHighlighterScript
	if highlighter == null:
		highlighter = HoverHighlighterScript.new()
		highlighter.name = "HoverHighlighter"
		target.add_child(highlighter)

	highlighter.root_path = ^"../.."

func _apply_material() -> void:
	var material := StandardMaterial3D.new()
	if hex_data.is_walkable:
		material.albedo_color = Color(0.24, 0.42, 0.29)
	else:
		material.albedo_color = Color(0.18, 0.17, 0.16)

	material_override = material
