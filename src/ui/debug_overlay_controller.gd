class_name DebugOverlayController
extends Node

@export var debug_log_path: NodePath = ^"../InteractionUI/DebugLogPanel"
@export var navigation_overlay_path: NodePath = ^"../NavigationDebugOverlay"
@export var debug_visible_on_ready: bool = false
@export var handle_toggle_input: bool = false

var _debug_visible: bool = false

func _ready() -> void:
	set_debug_visible(debug_visible_on_ready)

func _unhandled_input(event: InputEvent) -> void:
	if not handle_toggle_input:
		return
	if event.is_action_pressed("toggle_debug_overlay"):
		set_debug_visible(not _debug_visible)
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func set_debug_visible(is_visible: bool) -> void:
	_debug_visible = is_visible
	_set_node_visible(get_node_or_null(debug_log_path), is_visible)
	_set_node_visible(get_node_or_null(navigation_overlay_path), is_visible)

func is_debug_visible() -> bool:
	return _debug_visible

func _set_node_visible(node: Node, is_visible: bool) -> void:
	var canvas_item := node as CanvasItem
	if canvas_item != null:
		canvas_item.visible = is_visible
		return

	var node3d := node as Node3D
	if node3d != null:
		node3d.visible = is_visible
