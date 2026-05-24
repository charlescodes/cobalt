class_name EditorTool
extends RefCounted

func activate(_editor_controller: Node) -> void:
	pass

func deactivate() -> void:
	pass

func on_mouse_motion(_raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	pass

func on_left_click_down(_raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	pass

func on_left_click_up(_raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	pass

func draw_overlay(_overlay_node: Control) -> void:
	pass
