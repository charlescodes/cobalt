class_name InteractionActionResolver
extends RefCounted

const ACTION_EXAMINE: StringName = &"examine"
const ACTION_MOVE: StringName = &"move"
const DOMAIN_MOVE_TARGET: StringName = &"move_target"
const DOMAIN_WORLD_OBJECT: StringName = &"world_object"
const PLAYER_CHARACTER_KIND: StringName = &"player_character"

static func get_actions(target: Node) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not _is_enabled_target(target):
		return actions

	if _get_domain(target) == DOMAIN_WORLD_OBJECT:
		if _is_player_character(target):
			actions.append({
				"id": ACTION_MOVE,
				"label": "Move",
			})

		actions.append({
			"id": ACTION_EXAMINE,
			"label": "Examine",
		})

	return actions

static func can_examine(target: Node) -> bool:
	if not _is_enabled_target(target):
		return false

	return _get_domain(target) == DOMAIN_WORLD_OBJECT and _get_data(target) != null

static func build_examine_output(target: Node) -> Dictionary:
	var output: Dictionary = {}
	var domain := _get_domain(target)
	var data := _get_data(target)
	output["domain"] = domain

	if domain != DOMAIN_WORLD_OBJECT or data == null:
		return output

	var object_kind: Variant = data.get("object_kind")
	if object_kind != null:
		output["object_kind"] = object_kind

	var object_id: Variant = data.get("object_id")
	if object_id != null and object_id != &"":
		output["object_id"] = object_id

	return output

static func _is_enabled_target(target: Node) -> bool:
	if target == null:
		return false
	if target.has_method("is_interaction_enabled"):
		return bool(target.call("is_interaction_enabled"))

	var enabled: Variant = target.get("interaction_enabled")
	return enabled == null or bool(enabled)

static func _get_domain(target: Node) -> StringName:
	if target == null:
		return &""
	if target.has_method("get_target_domain"):
		var target_domain: Variant = target.call("get_target_domain")
		return target_domain if target_domain is StringName else StringName(str(target_domain))

	var domain: Variant = target.get("target_domain")
	return domain if domain is StringName else StringName(str(domain))

static func _get_data(target: Node) -> Resource:
	if target == null:
		return null
	if target.has_method("get_target_data"):
		return target.call("get_target_data") as Resource

	return target.get("target_data") as Resource

static func _is_player_character(target: Node) -> bool:
	var data := _get_data(target)
	return data != null and data.get("object_kind") == PLAYER_CHARACTER_KIND
