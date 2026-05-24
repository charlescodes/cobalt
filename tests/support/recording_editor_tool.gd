extends "res://src/editor/tools/editor_tool.gd"

var motion_count: int = 0
var left_down_count: int = 0
var left_up_count: int = 0
var last_hit: Vector3 = Vector3.ZERO
var last_modifiers: Dictionary = {}

func on_mouse_motion(raycast_hit: Vector3, modifiers: Dictionary) -> void:
	motion_count += 1
	last_hit = raycast_hit
	last_modifiers = modifiers

func on_left_click_down(raycast_hit: Vector3, modifiers: Dictionary) -> void:
	left_down_count += 1
	last_hit = raycast_hit
	last_modifiers = modifiers

func on_left_click_up(raycast_hit: Vector3, modifiers: Dictionary) -> void:
	left_up_count += 1
	last_hit = raycast_hit
	last_modifiers = modifiers
