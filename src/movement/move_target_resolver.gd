class_name MoveTargetResolver
extends RefCounted

const HexDataScript := preload("res://src/grid/hex_data.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const PLAYER_CHARACTER_KIND: StringName = &"player_character"

static func can_start_move(source: Node) -> bool:
	var data := get_target_data(source) as WorldObjectDataScript
	return (
		_is_enabled_target(source)
		and get_target_domain(source) == InteractionActionResolverScript.DOMAIN_WORLD_OBJECT
		and data != null
		and data.object_kind == PLAYER_CHARACTER_KIND
	)

static func can_select_destination(destination: Node) -> bool:
	var data := get_target_data(destination) as HexDataScript
	return (
		_is_enabled_target(destination)
		and get_target_domain(destination) == InteractionActionResolverScript.DOMAIN_HEX
		and data != null
		and data.is_walkable
	)

static func can_move(source: Node, destination: Node) -> bool:
	return can_start_move(source) and can_select_destination(destination)

static func get_actor_node(source: Node) -> Node:
	if source == null:
		return null
	if source.has_method("get_hover_root"):
		return source.call("get_hover_root") as Node

	return source.get_parent()

static func get_target_data(target: Node) -> Resource:
	if target == null:
		return null
	if target.has_method("get_target_data"):
		return target.call("get_target_data") as Resource

	return target.get("target_data") as Resource

static func get_target_domain(target: Node) -> StringName:
	if target == null:
		return &""
	if target.has_method("get_target_domain"):
		var target_domain: Variant = target.call("get_target_domain")
		return target_domain if target_domain is StringName else StringName(str(target_domain))

	var domain: Variant = target.get("target_domain")
	return domain if domain is StringName else StringName(str(domain))

static func _is_enabled_target(target: Node) -> bool:
	if target == null:
		return false
	if target.has_method("is_interaction_enabled"):
		return bool(target.call("is_interaction_enabled"))

	var enabled: Variant = target.get("interaction_enabled")
	return enabled == null or bool(enabled)
