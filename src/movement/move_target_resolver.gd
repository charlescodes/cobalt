class_name MoveTargetResolver
extends RefCounted

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const PLAYER_CHARACTER_KIND: StringName = &"player_character"
const NAV_SNAP_TOLERANCE_M: float = 0.35
const NAV_VERTICAL_SNAP_TOLERANCE_M: float = 0.5
const PATH_ENDPOINT_TOLERANCE_M: float = 0.05

static func can_start_move(source: Node) -> bool:
	return (
		_is_enabled_target(source)
		and get_target_domain(source) == InteractionActionResolverScript.DOMAIN_WORLD_OBJECT
		and can_start_move_data(get_target_data(source))
	)

static func can_select_destination(destination: Node) -> bool:
	return (
		_is_enabled_target(destination)
		and get_target_domain(destination) == InteractionActionResolverScript.DOMAIN_MOVE_TARGET
		and can_select_destination_data(get_target_data(destination))
	)

static func can_start_move_data(actor_data: Resource) -> bool:
	var data := actor_data as WorldObjectDataScript
	return data != null and data.object_kind == PLAYER_CHARACTER_KIND

static func can_select_destination_data(destination_data: Resource) -> bool:
	return destination_data is MoveTargetDataScript

static func can_move(source: Node, destination: Node, navigation_map: RID = RID()) -> bool:
	if not can_start_move(source) or not can_select_destination(destination):
		return false

	return not navigation_path_for_targets(source, destination, navigation_map).is_empty()

static func navigation_path_for_targets(
	source: Node,
	destination: Node,
	navigation_map: RID = RID()
) -> PackedVector3Array:
	var actor_data := get_target_data(source) as WorldObjectDataScript
	var destination_data := get_target_data(destination) as MoveTargetDataScript
	if actor_data == null or destination_data == null:
		return PackedVector3Array()

	var resolved_map := navigation_map
	if not resolved_map.is_valid():
		resolved_map = get_navigation_map(source, destination)

	return navigation_path(resolved_map, actor_data.position, destination_data.position)

static func navigation_path(
	navigation_map: RID,
	start_position: Vector3,
	target_position: Vector3,
	snap_tolerance_m: float = NAV_SNAP_TOLERANCE_M
) -> PackedVector3Array:
	if not navigation_map.is_valid():
		return PackedVector3Array()
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return PackedVector3Array()

	var snapped_start := NavigationServer3D.map_get_closest_point(navigation_map, start_position)
	var snapped_target := NavigationServer3D.map_get_closest_point(navigation_map, target_position)
	if not _is_within_snap_tolerance(snapped_start, start_position, snap_tolerance_m):
		return PackedVector3Array()
	if not _is_within_snap_tolerance(snapped_target, target_position, snap_tolerance_m):
		return PackedVector3Array()

	snapped_start = _stabilize_navigation_point(snapped_start)
	snapped_target = _stabilize_navigation_point(snapped_target)
	var path := NavigationServer3D.map_get_path(navigation_map, snapped_start, snapped_target, false)
	if path.is_empty():
		return PackedVector3Array()
	if path[path.size() - 1].distance_to(snapped_target) > PATH_ENDPOINT_TOLERANCE_M:
		return PackedVector3Array()

	return path

static func get_navigation_map(source: Node, destination: Node = null) -> RID:
	var actor_map := _navigation_map_for_actor_node(get_actor_node(source))
	if actor_map.is_valid():
		return actor_map

	var source_map := _navigation_map_for_node(source)
	if source_map.is_valid():
		return source_map

	return _navigation_map_for_node(destination)

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

static func _navigation_map_for_node(node: Node) -> RID:
	var node3d := node as Node3D
	if node3d != null and node3d.is_inside_tree() and node3d.get_world_3d() != null:
		return node3d.get_world_3d().navigation_map

	if node != null and node.is_inside_tree():
		var viewport := node.get_viewport()
		if viewport != null and viewport.get_world_3d() != null:
			return viewport.get_world_3d().navigation_map

	return RID()

static func _navigation_map_for_actor_node(actor: Node) -> RID:
	if actor == null:
		return RID()

	var agent: NavigationAgent3D
	if actor.has_method("get_navigation_agent"):
		agent = actor.call("get_navigation_agent") as NavigationAgent3D
	else:
		agent = actor.get_node_or_null("NavigationAgent3D") as NavigationAgent3D

	if agent == null:
		return RID()

	var navigation_map := agent.get_navigation_map()
	return navigation_map if navigation_map.is_valid() else RID()

static func _is_within_snap_tolerance(
	snapped_position: Vector3,
	requested_position: Vector3,
	horizontal_tolerance_m: float
) -> bool:
	var horizontal_delta := Vector2(
		snapped_position.x - requested_position.x,
		snapped_position.z - requested_position.z
	)
	return (
		horizontal_delta.length() <= horizontal_tolerance_m
		and absf(snapped_position.y - requested_position.y) <= NAV_VERTICAL_SNAP_TOLERANCE_M
	)

static func _stabilize_navigation_point(position: Vector3) -> Vector3:
	return Vector3(
		snappedf(position.x, 0.001),
		snappedf(position.y, 0.001),
		snappedf(position.z, 0.001)
	)
