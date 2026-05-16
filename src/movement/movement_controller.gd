class_name MovementController
extends Node

const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const ARRIVAL_TOLERANCE_M: float = 0.05

@export_range(0.1, 10.0, 0.1) var movement_speed_mps: float = 1.4

var _busy_actors: Dictionary = {}

func _ready() -> void:
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
	if actor == null or world_object_data == null or move_target_data == null:
		_emit_movement_failed(actor, destination_data, &"invalid_request")
		return false

	if _is_actor_busy(actor):
		_emit_movement_failed(actor, destination_data, &"actor_busy")
		return false

	if world_object_data.position.distance_to(move_target_data.position) <= ARRIVAL_TOLERANCE_M:
		_emit_movement_failed(actor, destination_data, &"already_at_destination")
		return false

	var navigation_map := _navigation_map_for_actor(actor)
	var path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		world_object_data.position,
		move_target_data.position
	)
	if path.is_empty():
		_emit_movement_failed(actor, destination_data, &"no_path")
		return false

	_emit_movement_failed(actor, destination_data, &"movement_driver_unavailable")
	return false

func is_actor_busy(actor: Node) -> bool:
	return _is_actor_busy(actor)

func _handle_move_requested(actor: Node, actor_data: Resource, destination_data: Resource) -> void:
	request_move(actor, actor_data, destination_data)

func _handle_movement_completed(actor: Node, _destination_data: Resource) -> void:
	if actor != null:
		_busy_actors.erase(actor.get_instance_id())

func _is_actor_busy(actor: Node) -> bool:
	return actor != null and _busy_actors.has(actor.get_instance_id())

func _emit_movement_failed(actor: Node, destination_data: Resource, reason: StringName) -> void:
	_emit_event(&"movement_failed", [actor, destination_data, reason])

func _emit_event(signal_name: StringName, args: Array) -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		match signal_name:
			&"movement_started":
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
	var actor3d := actor as Node3D
	if actor3d != null and actor3d.is_inside_tree() and actor3d.get_world_3d() != null:
		return actor3d.get_world_3d().navigation_map

	return RID()
