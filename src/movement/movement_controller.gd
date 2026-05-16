class_name MovementController
extends Node

const HexGridManagerScript := preload("res://src/grid/hex_grid_manager.gd")
const HexPathfinderScript := preload("res://src/movement/hex_pathfinder.gd")
const HexDataScript := preload("res://src/grid/hex_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

@export var grid_manager_path: NodePath = ^"../HexGridManager"
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
	var hex_data := destination_data as HexDataScript
	if actor == null or world_object_data == null or hex_data == null:
		_emit_movement_failed(actor, destination_data, &"invalid_request")
		return false

	if _is_actor_busy(actor):
		_emit_movement_failed(actor, destination_data, &"actor_busy")
		return false

	if not actor.has_method("move_along_hex_path"):
		_emit_movement_failed(actor, destination_data, &"missing_mover")
		return false

	var grid_manager := _resolve_grid_manager()
	if grid_manager == null:
		_emit_movement_failed(actor, destination_data, &"missing_grid")
		return false

	var path := HexPathfinderScript.find_path(grid_manager.get_hexes(), world_object_data.key(), hex_data.key())
	if path.is_empty():
		_emit_movement_failed(actor, destination_data, &"no_path")
		return false
	if path.size() < 2:
		_emit_movement_failed(actor, destination_data, &"already_at_destination")
		return false

	_busy_actors[actor.get_instance_id()] = true
	_emit_event(&"movement_started", [actor, path])
	var accepted := bool(actor.call("move_along_hex_path", path, movement_speed_mps))
	if not accepted:
		_busy_actors.erase(actor.get_instance_id())
		_emit_movement_failed(actor, destination_data, &"actor_busy")
		return false

	return true

func is_actor_busy(actor: Node) -> bool:
	return _is_actor_busy(actor)

func _handle_move_requested(actor: Node, actor_data: Resource, destination_data: Resource) -> void:
	request_move(actor, actor_data, destination_data)

func _handle_movement_completed(actor: Node, _destination_data: Resource) -> void:
	if actor != null:
		_busy_actors.erase(actor.get_instance_id())

func _resolve_grid_manager() -> HexGridManagerScript:
	return get_node_or_null(grid_manager_path) as HexGridManagerScript

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
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
