extends RefCounted

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const NavigationDebugOverlayScript := preload("res://src/ui/navigation_debug_overlay.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	var overlay := NavigationDebugOverlayScript.new()
	ctx.root().add_child(overlay)
	await ctx.idle_frame()

	if overlay.visible:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay should start hidden.")

	var destination_data := MoveTargetDataScript.new(Vector3(1.5, 0.0, 1.0))
	root_event_bus.emit_signal(&"move_requested", overlay, null, destination_data)
	var destination_marker := overlay.get_node_or_null("MarkerDebug/DestinationMarker") as MeshInstance3D
	if destination_marker == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw a destination marker.")

	var path := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.75, 0.0, 0.25),
		Vector3(1.5, 0.0, 1.0),
	])
	root_event_bus.emit_signal(&"movement_started", overlay, path)
	var path_line := overlay.get_node_or_null("PathDebug/PathLine") as MeshInstance3D
	if path_line == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw a path line.")
	if overlay.get_node_or_null("PathDebug/Waypoint_00") as MeshInstance3D == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw waypoint markers.")
	if overlay.get_node_or_null("PathDebug/Waypoint_02") as MeshInstance3D == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw the final waypoint marker.")

	var failed_target := InteractionTargetScript.new()
	failed_target.target_domain = InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	failed_target.target_data = MoveTargetDataScript.new(Vector3(3.0, 0.0, 3.0))
	root_event_bus.emit_signal(
		&"interaction_targeting_failed",
		overlay,
		failed_target,
		InteractionActionResolverScript.ACTION_MOVE,
		&"target_off_nav",
		{}
	)
	var failure_marker := overlay.get_node_or_null("MarkerDebug/FailureMarker") as MeshInstance3D
	failed_target.free()
	if failure_marker == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw a targeting failure marker.")

	overlay.free()
	return true
