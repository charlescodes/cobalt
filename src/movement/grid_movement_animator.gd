class_name GridMovementAnimator
extends Node

const HexDataScript := preload("res://src/grid/hex_data.gd")
const HexViewScript := preload("res://src/grid/hex_view.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

var _path: Array = []
var _path_index: int = 0
var _speed_mps: float = 1.4
var _is_moving: bool = false

func _ready() -> void:
	set_process(false)

func move_along_hex_path(path: Array, speed_mps: float) -> bool:
	if _is_moving or path.size() < 2:
		return false

	_path = path.duplicate()
	_path_index = 1
	_speed_mps = maxf(speed_mps, 0.01)
	_is_moving = true
	set_process(true)
	return true

func is_moving() -> bool:
	return _is_moving

func _process(delta: float) -> void:
	var actor := get_parent() as Node3D
	if actor == null:
		_finish_movement(null)
		return

	var travel_budget := _speed_mps * delta
	while _is_moving and travel_budget >= 0.0:
		var target_hex := _path[_path_index] as HexDataScript
		if target_hex == null:
			_finish_movement(null)
			return

		var target_position := HexViewScript.axial_to_world(target_hex.q, target_hex.r, actor.position.y)
		var to_target := target_position - actor.position
		var distance := to_target.length()
		if distance <= 0.001:
			_reach_step(actor, target_hex)
			continue

		if distance <= travel_budget:
			actor.position = target_position
			travel_budget -= distance
			_reach_step(actor, target_hex)
		else:
			actor.position += to_target.normalized() * travel_budget
			return

func _reach_step(actor: Node3D, hex_data: HexDataScript) -> void:
	_apply_hex_to_actor_data(hex_data)
	_emit_event(&"movement_step_reached", actor, hex_data)
	_path_index += 1
	if _path_index >= _path.size():
		_finish_movement(hex_data)

func _finish_movement(destination_data: HexDataScript) -> void:
	var actor := get_parent() as Node
	_is_moving = false
	_path.clear()
	_path_index = 0
	set_process(false)

	if destination_data != null:
		_emit_event(&"movement_completed", actor, destination_data)

func _apply_hex_to_actor_data(hex_data: HexDataScript) -> void:
	var actor_data := _get_actor_data()
	if actor_data == null:
		return

	actor_data.set_cube_coords(hex_data.q, hex_data.r, hex_data.s)

func _get_actor_data() -> WorldObjectDataScript:
	var actor := get_parent()
	if actor == null:
		return null

	return actor.get("object_data") as WorldObjectDataScript

func _emit_event(signal_name: StringName, actor: Node, payload: Resource) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	var event_bus := tree.root.get_node_or_null("EventBus")
	if event_bus != null:
		event_bus.emit_signal(signal_name, actor, payload)
