extends RefCounted

const EventBusScript := preload("res://src/core/event_bus.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var event_bus := EventBusScript.new()
	for signal_name in [
		"hover_target_changed",
		"interaction_menu_requested",
		"interaction_action_requested",
		"interaction_pointer_capture_changed",
		"interaction_ui_cancel_requested",
		"interaction_targeting_started",
		"interaction_targeting_cancelled",
		"interaction_targeting_failed",
		"move_requested",
		"movement_started",
		"movement_step_reached",
		"movement_completed",
		"movement_failed",
		"examined_output",
		"editor_mode_changed",
		"editor_tool_changed",
		"editor_selection_changed",
		"editor_map_loaded",
		"editor_map_saved",
	]:
		if not event_bus.has_signal(signal_name):
			event_bus.free()
			return ctx.fail("EventBus is missing %s signal." % signal_name)
	event_bus.free()

	if ProjectSettings.get_setting("autoload/EventBus", "") != "*res://src/core/event_bus.gd":
		return ctx.fail("EventBus autoload is not configured.")
	if not InputMap.has_action("toggle_interaction_log"):
		return ctx.fail("toggle_interaction_log input action is missing.")
	if not InputMap.has_action("toggle_debug_overlay"):
		return ctx.fail("toggle_debug_overlay input action is missing.")
	if not _action_has_keycode("toggle_debug_overlay", KEY_F12):
		return ctx.fail("toggle_debug_overlay is not bound to F12.")
	if not InputMap.has_action("toggle_dev_menu"):
		return ctx.fail("toggle_dev_menu input action is missing.")
	if not _action_has_keycode("toggle_dev_menu", KEY_ESCAPE):
		return ctx.fail("toggle_dev_menu is not bound to Escape.")
	if ResourceLoader.exists("res://src/movement/hex_pathfinder.gd"):
		return ctx.fail("HexPathfinder script should be deleted.")
	if ResourceLoader.exists("res://src/walls/wall_cell_resolver.gd"):
		return ctx.fail("WallCellResolver script should be deleted.")
	if ResourceLoader.exists("res://src/movement/grid_movement_animator.gd"):
		return ctx.fail("GridMovementAnimator script should be deleted.")

	return true

func _action_has_keycode(action_name: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return true

	return false
