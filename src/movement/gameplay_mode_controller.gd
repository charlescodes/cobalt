class_name GameplayModeController
extends Node

const RUNTIME_MODE_GAME: StringName = &"game"
const CONTROL_MODE_NONE: StringName = &"none"
const CONTROL_MODE_REAL_TIME: StringName = &"real_time"
const CONTROL_MODE_TURN_BASED: StringName = &"turn_based"

@export var start_control_mode: StringName = CONTROL_MODE_REAL_TIME

var _control_mode: StringName = CONTROL_MODE_REAL_TIME
var _is_game_runtime_mode: bool = false

func _ready() -> void:
	_control_mode = (
		start_control_mode
		if _is_known_control_mode(start_control_mode)
		else CONTROL_MODE_REAL_TIME
	)
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	var runtime_mode_callable := Callable(self, "_on_runtime_mode_changed")
	if (
		event_bus.has_signal(&"editor_mode_changed")
		and not event_bus.is_connected(&"editor_mode_changed", runtime_mode_callable)
	):
		event_bus.connect(&"editor_mode_changed", runtime_mode_callable)
	var control_mode_callable := Callable(self, "set_control_mode")
	if (
		event_bus.has_signal(&"gameplay_control_mode_requested")
		and not event_bus.is_connected(&"gameplay_control_mode_requested", control_mode_callable)
	):
		event_bus.connect(&"gameplay_control_mode_requested", control_mode_callable)

func set_control_mode(mode: StringName) -> void:
	if not _is_known_control_mode(mode) or _control_mode == mode:
		return

	_control_mode = mode
	_emit_active_control_mode()

func get_control_mode() -> StringName:
	return _control_mode

func get_active_control_mode() -> StringName:
	return _control_mode if _is_game_runtime_mode else CONTROL_MODE_NONE

func _on_runtime_mode_changed(mode: StringName) -> void:
	_is_game_runtime_mode = mode == RUNTIME_MODE_GAME
	_emit_active_control_mode()

func _emit_active_control_mode() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null and event_bus.has_signal(&"gameplay_control_mode_changed"):
		event_bus.emit_signal(&"gameplay_control_mode_changed", get_active_control_mode())

func _is_known_control_mode(mode: StringName) -> bool:
	return mode == CONTROL_MODE_REAL_TIME or mode == CONTROL_MODE_TURN_BASED

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
