class_name MovementController
extends Node

const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const ARRIVAL_TOLERANCE_M: float = 0.05
const MIN_MOVE_STEP_M: float = 0.001

@export_range(0.1, 10.0, 0.1) var movement_speed_mps: float = 1.4

var _busy_actors: Dictionary = {}

func _ready() -> void:
	set_physics_process(false)
	var event_bus := _get_event_bus()
	if event_bus == null:
		return
	var move_callable := Callable(self, "_handle_move_requested")
	var completed_callable := Callable(self, "_handle_movement_completed")
	if not event_bus.is_connected(&"move_requested", move_callable):
		event_bus.connect(&"move_requested", move_callable)
	if not event_bus.is_connected(&"movement_completed", completed_callable):
		event_bus.connect(&"movement_completed", completed_callable)

func request_move(actor: Node, actor_data: Resource, destination_data: Resource) -> bool:
	var world_object_data := actor_data as WorldObjectDataScript
	var move_target_data := destination_data as MoveTargetDataScript
	var actor3d := actor as Node3D
	if actor3d == null or world_object_data == null or move_target_data == null:
		_emit_movement_failed(actor, destination_data, &"invalid_request")
		return false
	if (
		not MoveTargetResolverScript.can_start_move_data(world_object_data)
		or not MoveTargetResolverScript.can_select_destination_data(move_target_data)
	):
		_emit_movement_failed(actor, destination_data, &"invalid_request")
		return false

	if _is_actor_busy(actor):
		_emit_movement_failed(actor, destination_data, &"actor_busy")
		return false

	if world_object_data.position.distance_to(move_target_data.position) <= ARRIVAL_TOLERANCE_M:
		_emit_movement_failed(actor, destination_data, &"already_at_destination")
		return false

	var agent := _get_navigation_agent(actor)
	if agent == null:
		_emit_movement_failed(actor, destination_data, &"missing_navigation_agent")
		return false

	var navigation_map := _navigation_map_for_actor(actor)
	var validation := MoveTargetResolverScript.navigation_path_result(
		navigation_map,
		world_object_data.position,
		move_target_data.position
	)
	if not bool(validation.get("ok", false)):
		var reason: StringName = validation.get("reason", &"no_path")
		_emit_movement_failed(actor, destination_data, reason)
		return false
	var path := validation.get("path", PackedVector3Array()) as PackedVector3Array

	agent.target_position = move_target_data.position
	_busy_actors[actor.get_instance_id()] = {
		"actor": actor3d,
		"actor_data": world_object_data,
		"agent": agent,
		"destination_data": move_target_data,
		"target_position": move_target_data.position,
	}
	set_physics_process(true)
	_emit_event(&"movement_started", [actor, path])
	return true

func is_actor_busy(actor: Node) -> bool:
	return _is_actor_busy(actor)

func _physics_process(delta: float) -> void:
	for actor_id in _busy_actors.keys():
		_process_active_movement(int(actor_id), delta)

	if _busy_actors.is_empty():
		set_physics_process(false)

func _handle_move_requested(actor: Node, actor_data: Resource, destination_data: Resource) -> void:
	request_move(actor, actor_data, destination_data)

func _handle_movement_completed(actor: Node, _destination_data: Resource) -> void:
	if actor != null:
		_busy_actors.erase(actor.get_instance_id())

func _is_actor_busy(actor: Node) -> bool:
	return actor != null and _busy_actors.has(actor.get_instance_id())

func _process_active_movement(actor_id: int, delta: float) -> void:
	var record := _busy_actors.get(actor_id, {}) as Dictionary
	var actor := record.get("actor") as Node3D
	var actor_data := record.get("actor_data") as WorldObjectDataScript
	var agent := record.get("agent") as NavigationAgent3D
	var destination_data := record.get("destination_data") as MoveTargetDataScript
	var target_position: Vector3 = record.get("target_position", Vector3.ZERO)
	if (
		actor == null
		or actor_data == null
		or agent == null
		or destination_data == null
		or not is_instance_valid(actor)
		or not is_instance_valid(agent)
	):
		var failed_actor: Node = null
		if actor != null and is_instance_valid(actor):
			failed_actor = actor
		_fail_active_movement(actor_id, failed_actor, destination_data, &"invalid_request")
		return

	var arrival_tolerance := maxf(ARRIVAL_TOLERANCE_M, agent.target_desired_distance)
	if actor.position.distance_to(target_position) <= arrival_tolerance:
		_complete_active_movement(actor_id, actor, actor_data, destination_data, target_position)
		return

	var next_position := agent.get_next_path_position()
	if absf(next_position.y - actor.position.y) <= 0.001:
		next_position.y = actor.position.y

	var move_budget := maxf(movement_speed_mps, 0.01) * delta
	var to_next := next_position - actor.position
	if to_next.length() <= MIN_MOVE_STEP_M:
		to_next = target_position - actor.position
		if absf(to_next.y) <= 0.001:
			to_next.y = 0.0

	if to_next.length() <= MIN_MOVE_STEP_M:
		_complete_active_movement(actor_id, actor, actor_data, destination_data, target_position)
		return

	actor.position += to_next.normalized() * minf(move_budget, to_next.length())
	actor_data.position = actor.position

	if actor.position.distance_to(target_position) <= arrival_tolerance:
		_complete_active_movement(actor_id, actor, actor_data, destination_data, target_position)

func _complete_active_movement(
	actor_id: int,
	actor: Node3D,
	actor_data: WorldObjectDataScript,
	destination_data: MoveTargetDataScript,
	target_position: Vector3
) -> void:
	actor.position = target_position
	actor_data.position = target_position
	_busy_actors.erase(actor_id)
	_emit_event(&"movement_completed", [actor, destination_data])

func _fail_active_movement(
	actor_id: int,
	actor: Node,
	destination_data: Resource,
	reason: StringName
) -> void:
	_busy_actors.erase(actor_id)
	_emit_movement_failed(actor, destination_data, reason)

func _emit_movement_failed(actor: Node, destination_data: Resource, reason: StringName) -> void:
	_emit_event(&"movement_failed", [actor, destination_data, reason])

func _emit_event(signal_name: StringName, args: Array) -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		match signal_name:
			&"movement_started":
				event_bus.emit_signal(signal_name, args[0], args[1])
			&"movement_completed":
				event_bus.emit_signal(signal_name, args[0], args[1])
			&"movement_failed":
				event_bus.emit_signal(signal_name, args[0], args[1], args[2])

func _get_event_bus() -> Node:
	var tree: SceneTree
	if is_inside_tree():
		tree = get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")

func _navigation_map_for_actor(actor: Node) -> RID:
	var agent := _get_navigation_agent(actor)
	if agent != null:
		var agent_map := agent.get_navigation_map()
		if agent_map.is_valid():
			return agent_map

	var actor3d := actor as Node3D
	if actor3d != null and actor3d.is_inside_tree() and actor3d.get_world_3d() != null:
		return actor3d.get_world_3d().navigation_map

	return RID()

func _get_navigation_agent(actor: Node) -> NavigationAgent3D:
	if actor == null:
		return null
	if actor.has_method("get_navigation_agent"):
		return actor.call("get_navigation_agent") as NavigationAgent3D

	return actor.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
