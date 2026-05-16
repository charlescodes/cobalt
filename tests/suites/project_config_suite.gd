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
		"move_requested",
		"movement_started",
		"movement_step_reached",
		"movement_completed",
		"movement_failed",
		"examined_output",
	]:
		if not event_bus.has_signal(signal_name):
			event_bus.free()
			return ctx.fail("EventBus is missing %s signal." % signal_name)
	event_bus.free()

	if ProjectSettings.get_setting("autoload/EventBus", "") != "*res://src/core/event_bus.gd":
		return ctx.fail("EventBus autoload is not configured.")
	if not InputMap.has_action("toggle_interaction_log"):
		return ctx.fail("toggle_interaction_log input action is missing.")
	if ResourceLoader.exists("res://src/movement/hex_pathfinder.gd"):
		return ctx.fail("HexPathfinder script should be deleted.")
	if ResourceLoader.exists("res://src/walls/wall_cell_resolver.gd"):
		return ctx.fail("WallCellResolver script should be deleted.")
	if ResourceLoader.exists("res://src/movement/grid_movement_animator.gd"):
		return ctx.fail("GridMovementAnimator script should be deleted.")

	return true
