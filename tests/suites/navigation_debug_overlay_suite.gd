extends RefCounted

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
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

	var bsp_data := BspModuleDataScript.new()
	bsp_data.building_size_m = Vector2(18.0, 14.0)
	bsp_data.min_room_size_m = 4.0
	bsp_data.max_split_depth = 3
	bsp_data.seed = 1337
	var generated_bsp := BspRoomProcessorScript.generate(bsp_data)
	overlay.set_bsp_debug_data(generated_bsp)
	var bsp_rooms_root := overlay.get_node_or_null("BspInterestDebug/Rooms") as Node3D
	var bsp_walls_root := overlay.get_node_or_null("BspInterestDebug/Walls") as Node3D
	var bsp_sockets_root := overlay.get_node_or_null("BspInterestDebug/Sockets") as Node3D
	var bsp_route_root := overlay.get_node_or_null("BspInterestDebug/ExitRoute") as Node3D
	if bsp_rooms_root == null or bsp_rooms_root.get_child_count() != generated_bsp.rooms.size():
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw BSP room interest bounds.")
	if bsp_walls_root == null or bsp_walls_root.get_child_count() <= 4:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw BSP wall interest highlights.")
	if bsp_sockets_root == null or bsp_sockets_root.get_child_count() < generated_bsp.doors.size() + 2:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw BSP door/object sockets.")
	if bsp_route_root == null or bsp_route_root.get_child_count() < 2:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw a BSP exterior route.")
	overlay.set_bsp_exit_route_visible(false)
	if overlay.get_node_or_null("BspInterestDebug/ExitRoute") != null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not hide the BSP exterior route.")
	overlay.set_bsp_exit_route_visible(true)
	overlay.set_bsp_interest_visible(false)
	if overlay.get_node_or_null("BspInterestDebug/Rooms") != null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not hide BSP interest highlights.")
	overlay.set_bsp_interest_visible(true)

	overlay.set_editor_snap_grid_cursor(Vector3(1.04, 0.0, 1.04), Vector3(1.0, 0.0, 1.0), 0.1)
	var snap_cloud := overlay.get_node_or_null("EditorSnapDebug/PointCloud") as MultiMeshInstance3D
	var snap_cursor := overlay.get_node_or_null("EditorSnapDebug/SnapCursor") as MeshInstance3D
	if snap_cloud == null or snap_cloud.multimesh == null or snap_cloud.multimesh.instance_count < 25:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw an editor snapping point cloud.")
	if snap_cursor == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw the editor snapping cursor marker.")
	overlay.clear_editor_snap_grid()
	var snap_root := overlay.get_node_or_null("EditorSnapDebug") as Node3D
	if snap_root == null or snap_root.get_child_count() != 0:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not clear the editor snapping point cloud.")
	overlay.set_bsp_editor_hover_segment({
		&"start": Vector3(0.0, 0.0, 0.0),
		&"end": Vector3(1.5, 0.0, 0.0),
	})
	if overlay.get_node_or_null("BspEditorHoverDebug/HoverSegment") as MeshInstance3D == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not draw the BSP editor hover segment.")
	overlay.clear_bsp_editor_hover_segment()
	var hover_root := overlay.get_node_or_null("BspEditorHoverDebug") as Node3D
	if hover_root == null or hover_root.get_child_count() != 0:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not clear the BSP editor hover segment.")

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

	root_event_bus.emit_signal(
		&"move_requested",
		overlay,
		null,
		MoveTargetDataScript.new(Vector3(2.0, 0.0, 1.25))
	)
	if overlay.get_node_or_null("PathDebug/PathLine") as MeshInstance3D == null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay cleared an active path after a destination update.")

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
	if overlay.get_node_or_null("PathDebug/PathLine") as MeshInstance3D != null:
		overlay.free()
		return ctx.fail("NavigationDebugOverlay did not clear the stale path after a targeting failure.")

	overlay.free()
	return true
