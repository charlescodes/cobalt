extends RefCounted

const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MovementControllerScript := preload("res://src/movement/movement_controller.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	if root_event_bus == null:
		return ctx.fail("Main scene movement check requires EventBus.")

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return ctx.fail("Main scene did not load for movement check.")

	var original_root_size: Vector2i = ctx.root().size
	ctx.root().size = Vector2i(1280, 720)
	var signals_connected := false
	var main := main_scene.instantiate() as Node3D
	ctx.root().add_child(main)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var camera := main.get_node_or_null("CameraRig/PitchPivot/Camera3D") as Camera3D
	var interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	var movement_controller := main.get_node_or_null("MovementController") as MovementControllerScript
	var navigation_region := main.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var generated_map: Node3D
	var main_pc: BlockoutObjectViewScript
	if navigation_region != null:
		generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map != null:
		main_pc = generated_map.get_node_or_null("WorldObjects/pc_001") as BlockoutObjectViewScript

	var ground_target: InteractionTargetScript
	if generated_map != null:
		ground_target = generated_map.get_node_or_null("StaticGround/Ground/GroundMoveTarget") as InteractionTargetScript

	if (
		camera == null
		or interaction_controller == null
		or movement_controller == null
		or navigation_region == null
		or generated_map == null
		or main_pc == null
		or ground_target == null
	):
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Main scene movement check is missing required nodes.")

	interaction_controller._ready()
	movement_controller._ready()

	var movement_completed_callable: Callable = ctx.movement_completed_callable()
	var movement_failed_callable: Callable = ctx.movement_failed_callable()
	ctx.connect_if_needed(root_event_bus, &"movement_completed", movement_completed_callable)
	ctx.connect_if_needed(root_event_bus, &"movement_failed", movement_failed_callable)
	signals_connected = true
	ctx.reset_movement_events()

	var navigation_map := main_pc.get_navigation_agent().get_navigation_map()
	if not navigation_map.is_valid() and main_pc.get_world_3d() != null:
		navigation_map = main_pc.get_world_3d().navigation_map
	await ctx.wait_for_navigation_map(navigation_map)
	for _index in range(4):
		await ctx.tree.process_frame
		await ctx.tree.physics_frame

	var target_world_position := Vector3(1.5, 0.0, 0.0)
	var setup_snapped_target := NavigationServer3D.map_get_closest_point(navigation_map, target_world_position)
	var setup_path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		main_pc.object_data.position,
		target_world_position
	)
	if setup_path.is_empty():
		var navmesh := navigation_region.navigation_mesh
		var vertex_count := -1
		var polygon_count := -1
		if navmesh != null:
			vertex_count = navmesh.vertices.size()
			polygon_count = navmesh.get_polygon_count()
		var snapped_start := NavigationServer3D.map_get_closest_point(navigation_map, main_pc.object_data.position)
		var snapped_target := NavigationServer3D.map_get_closest_point(navigation_map, target_world_position)
		var min_y := INF
		var max_y := -INF
		if navmesh != null:
			for vertex in navmesh.vertices:
				min_y = minf(min_y, vertex.y)
				max_y = maxf(max_y, vertex.y)
		return _fail_movement(
			ctx,
			root_event_bus,
			main,
			original_root_size,
			signals_connected,
			"Default map did not bake a native navigation path to the test movement point. iteration=%d vertices=%d polygons=%d nav_y=%.3f..%.3f map_valid=%s start_snap=%s start_dist=%.3f target_snap=%s target_dist=%.3f."
			% [
				NavigationServer3D.map_get_iteration_id(navigation_map),
				vertex_count,
				polygon_count,
				min_y,
				max_y,
				str(navigation_map.is_valid()),
				snapped_start,
				snapped_start.distance_to(main_pc.object_data.position),
				snapped_target,
				snapped_target.distance_to(target_world_position),
			]
		)

	var pc_target := main_pc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if pc_target == null:
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Player character is missing its interaction target.")
	if not interaction_controller.start_targeting(pc_target, InteractionActionResolverScript.ACTION_MOVE):
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Main scene PC did not start move targeting.")

	var target_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, target_world_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var expected_ground_hit: Dictionary = ctx.raycast_first_area_hit(camera, target_screen_position)
	if expected_ground_hit.is_empty() or expected_ground_hit.get("collider") != ground_target:
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Main scene movement raycast did not hit the ground target.")

	ctx.drive_interaction_hover_at_screen(
		interaction_controller,
		target_screen_position,
		InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	)
	var destination_data := ground_target.target_data as MoveTargetDataScript
	if destination_data == null:
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Ground target does not carry MoveTargetData.")
	var expected_destination := destination_data.position

	if not interaction_controller.try_confirm_targeting_target(ground_target):
		var snapped_destination := NavigationServer3D.map_get_closest_point(navigation_map, expected_destination)
		return _fail_movement(
			ctx,
			root_event_bus,
			main,
			original_root_size,
			signals_connected,
			"Main scene did not confirm the reachable ground move target. destination=%s snapped=%s snap_dist=%.3f."
			% [
				expected_destination,
				snapped_destination,
				snapped_destination.distance_to(expected_destination),
			]
		)
	if not movement_controller.is_actor_busy(main_pc):
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "MovementController did not start moving the main scene PC.")

	for _index in range(120):
		await ctx.tree.physics_frame
		movement_controller._process_active_movement(main_pc.get_instance_id(), 0.1)
		if not movement_controller.is_actor_busy(main_pc):
			break

	if movement_controller.is_actor_busy(main_pc):
		var active_record: Dictionary = movement_controller._busy_actors.get(main_pc.get_instance_id(), {}) as Dictionary
		var agent := active_record.get("agent") as NavigationAgent3D
		var next_position := agent.get_next_path_position() if agent != null else Vector3.ZERO
		return _fail_movement(
			ctx,
			root_event_bus,
			main,
			original_root_size,
			signals_connected,
			"Main scene PC did not complete movement through the baked navmesh. position=%s destination=%s record_target=%s next=%s finished=%s distance=%.3f failed=%d:%s."
			% [
				main_pc.position,
				expected_destination,
				active_record.get("target_position", Vector3.ZERO),
				next_position,
				str(agent.is_navigation_finished() if agent != null else false),
				main_pc.position.distance_to(expected_destination),
				ctx.movement_failed_count,
				ctx.movement_failed_reason,
			]
		)
	if ctx.movement_failed_count != 0:
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Main scene PC movement emitted movement_failed: %s." % ctx.movement_failed_reason)
	if ctx.movement_completed_count != 1:
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Main scene PC movement did not emit movement_completed.")
	if main_pc.position.distance_to(expected_destination) > 0.001:
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Main scene PC did not snap to the clicked destination.")
	if main_pc.object_data.position.distance_to(expected_destination) > 0.001:
		return _fail_movement(ctx, root_event_bus, main, original_root_size, signals_connected, "Main scene PC WorldObjectData did not snap to the clicked destination.")

	_cleanup_movement(ctx, root_event_bus, main, original_root_size, signals_connected)
	return true

func _fail_movement(
	ctx,
	root_event_bus: Node,
	main: Node,
	original_root_size: Vector2i,
	signals_connected: bool,
	message: String
) -> bool:
	_cleanup_movement(ctx, root_event_bus, main, original_root_size, signals_connected)
	return ctx.fail(message)

func _cleanup_movement(
	ctx,
	root_event_bus: Node,
	main: Node,
	original_root_size: Vector2i,
	signals_connected: bool
) -> void:
	if signals_connected:
		ctx.disconnect_if_connected(root_event_bus, &"movement_completed", ctx.movement_completed_callable())
		ctx.disconnect_if_connected(root_event_bus, &"movement_failed", ctx.movement_failed_callable())
	if main != null:
		main.free()
	ctx.root().size = original_root_size
