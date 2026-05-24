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

func uses_snapping_grid() -> bool:
	return false

func get_snapping_step() -> float:
	return 0.1

func get_snapping_context(_raw_pos: Vector3, _modifiers: Dictionary) -> Dictionary:
	return {}
