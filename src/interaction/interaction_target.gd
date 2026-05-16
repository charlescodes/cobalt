class_name InteractionTarget
extends Area3D

const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")
const GROUP_NAME: StringName = &"interaction_targets"

@export var target_domain: StringName = &""
@export var target_data: Resource
@export var can_highlight: bool = true:
	set(value):
		can_highlight = value
		if not can_highlight:
			set_hovered(false)
@export var interaction_enabled: bool = true:
	set(value):
		interaction_enabled = value
		input_ray_pickable = value
		if not interaction_enabled:
			set_hovered(false)
@export var highlight_root_path: NodePath = ^".."
@export var highlighter_path: NodePath = ^"HoverHighlighter"

var _is_hovered: bool = false

func _init() -> void:
	_configure_pickable()

func _enter_tree() -> void:
	_configure_pickable()

func set_hovered(is_hovered: bool) -> void:
	var should_highlight := is_hovered and interaction_enabled and can_highlight
	if _is_hovered == should_highlight:
		return

	_is_hovered = should_highlight
	var highlighter := _get_highlighter()
	if highlighter != null:
		highlighter.set_highlighted(should_highlight)

func get_hover_root() -> Node3D:
	var root := get_node_or_null(highlight_root_path) as Node3D
	if root != null:
		return root

	return get_parent() as Node3D

func get_target_domain() -> StringName:
	return target_domain

func get_target_data() -> Resource:
	return target_data

func is_interaction_enabled() -> bool:
	return interaction_enabled

func _configure_pickable() -> void:
	add_to_group(GROUP_NAME)
	input_ray_pickable = interaction_enabled
	monitorable = true

func _get_highlighter() -> HoverHighlighterScript:
	return get_node_or_null(highlighter_path) as HoverHighlighterScript
