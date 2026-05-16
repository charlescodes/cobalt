extends RefCounted

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MovementControllerScript := preload("res://src/movement/movement_controller.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	var pc_data := WorldObjectDataScript.new(&"pc_target", &"player_character", Vector3.ZERO)
	var pc_view := BlockoutObjectViewScript.new()
	pc_view.object_data = pc_data
	ctx.root().add_child(pc_view)
	var pc_target := pc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript

	var move_target_parent := Node3D.new()
	ctx.root().add_child(move_target_parent)
	var move_target := InteractionTargetScript.new()
	move_target.target_domain = InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	move_target.target_data = MoveTargetDataScript.new(Vector3(1.0, 0.0, 1.0))
	move_target_parent.add_child(move_target)

	ctx.reset_move_requested()
	var move_requested_callable: Callable = ctx.move_requested_callable()
	ctx.connect_if_needed(root_event_bus, &"move_requested", move_requested_callable)

	var targeting_controller := InteractionControllerScript.new()
	ctx.root().add_child(targeting_controller)
	targeting_controller._ready()
	if not targeting_controller.start_targeting(pc_target, InteractionActionResolverScript.ACTION_MOVE):
		_free_targeting_fixture(ctx, root_event_bus, move_requested_callable, targeting_controller, move_target_parent, pc_view)
		return ctx.fail("InteractionController did not enter move targeting for a PC source.")
	if targeting_controller.try_confirm_targeting_target(move_target):
		_free_targeting_fixture(ctx, root_event_bus, move_requested_callable, targeting_controller, move_target_parent, pc_view)
		return ctx.fail("InteractionController confirmed a target without an attached native nav map.")
	if ctx.move_requested_count != 0:
		_free_targeting_fixture(ctx, root_event_bus, move_requested_callable, targeting_controller, move_target_parent, pc_view)
		return ctx.fail("InteractionController emitted move_requested for an invalid destination.")
	targeting_controller.cancel_targeting()
	ctx.disconnect_if_connected(root_event_bus, &"move_requested", move_requested_callable)
	targeting_controller.free()
	move_target_parent.free()

	var nav: Dictionary = ctx.create_square_nav_map()
	var navigation_map: RID = nav["map"]
	var navigation_region: RID = nav["region"]
	pc_view.get_navigation_agent().set_navigation_map(navigation_map)
	await ctx.wait_for_navigation_map(navigation_map)
	var setup_path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		pc_data.position,
		Vector3(2.0, 0.0, 0.0)
	)
	if setup_path.is_empty():
		var start_snap := NavigationServer3D.map_get_closest_point(navigation_map, pc_data.position)
		var target_snap := NavigationServer3D.map_get_closest_point(navigation_map, Vector3(2.0, 0.0, 0.0))
		ctx.free_nav_map(navigation_map, navigation_region)
		pc_view.free()
		return ctx.fail(
			"Test native navigation map did not produce a path. Iteration=%d start_snap=%s target_snap=%s."
			% [
				NavigationServer3D.map_get_iteration_id(navigation_map),
				start_snap,
				target_snap,
			]
		)

	var movement_controller := MovementControllerScript.new()
	movement_controller.movement_speed_mps = 10.0
	ctx.root().add_child(movement_controller)
	movement_controller._ready()
	var movement_controller_has_event_bus := movement_controller._get_event_bus() != null
	var movement_started_callable: Callable = ctx.movement_started_callable()
	var movement_completed_callable: Callable = ctx.movement_completed_callable()
	var movement_failed_callable: Callable = ctx.movement_failed_callable()
	if movement_controller_has_event_bus:
		ctx.connect_if_needed(root_event_bus, &"movement_started", movement_started_callable)
		ctx.connect_if_needed(root_event_bus, &"movement_completed", movement_completed_callable)
		ctx.connect_if_needed(root_event_bus, &"movement_failed", movement_failed_callable)

	ctx.reset_movement_events()
	var valid_destination := MoveTargetDataScript.new(Vector3(2.0, 0.0, 0.0))
	if not movement_controller.request_move(pc_view, pc_data, valid_destination):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController rejected a valid nav-backed movement: %s." % ctx.movement_failed_reason)
	if not movement_controller.is_actor_busy(pc_view):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController did not mark the actor busy after movement start.")
	if movement_controller_has_event_bus:
		if ctx.movement_started_count != 1 or ctx.movement_started_path.is_empty():
			_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
			return ctx.fail("MovementController did not emit movement_started with a native path.")

	ctx.movement_failed_count = 0
	ctx.movement_failed_reason = &""
	if movement_controller.request_move(pc_view, pc_data, MoveTargetDataScript.new(Vector3(1.0, 0.0, 0.0))):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController accepted a second move while the actor was busy.")
	if movement_controller_has_event_bus:
		if ctx.movement_failed_count != 1 or ctx.movement_failed_reason != &"actor_busy":
			_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
			return ctx.fail("MovementController did not emit actor_busy for a repeated request.")

	for _index in range(40):
		await ctx.tree.physics_frame
		movement_controller._physics_process(0.1)
		if not movement_controller.is_actor_busy(pc_view):
			break

	if movement_controller.is_actor_busy(pc_view):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController did not complete movement within the expected ticks.")
	if pc_view.position.distance_to(valid_destination.position) > 0.001:
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController did not snap the actor to the target position.")
	if pc_data.position.distance_to(valid_destination.position) > 0.001:
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController did not update WorldObjectData.position on completion.")
	if movement_controller_has_event_bus:
		if ctx.movement_completed_count != 1:
			_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
			return ctx.fail("MovementController did not emit movement_completed.")

	ctx.movement_failed_count = 0
	ctx.movement_failed_reason = &""
	if movement_controller.request_move(pc_view, pc_data, MoveTargetDataScript.new(valid_destination.position)):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController accepted already-at-destination movement.")
	if movement_controller.is_actor_busy(pc_view):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController marked an actor busy for a rejected movement.")
	if movement_controller_has_event_bus:
		if ctx.movement_failed_count != 1 or ctx.movement_failed_reason != &"already_at_destination":
			_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
			return ctx.fail("MovementController did not emit already_at_destination.")

	ctx.movement_failed_count = 0
	ctx.movement_failed_reason = &""
	if movement_controller.request_move(
		pc_view,
		WorldObjectDataScript.new(&"npc_move", &"non_player_character", pc_data.position),
		MoveTargetDataScript.new(Vector3(1.0, 0.0, 1.0))
	):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController accepted non-player movement data.")
	if movement_controller_has_event_bus:
		if ctx.movement_failed_count != 1 or ctx.movement_failed_reason != &"invalid_request":
			_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
			return ctx.fail("MovementController did not reject non-player movement data.")

	ctx.movement_failed_count = 0
	ctx.movement_failed_reason = &""
	var bare_actor := Node3D.new()
	bare_actor.position = pc_data.position
	ctx.root().add_child(bare_actor)
	if movement_controller.request_move(
		bare_actor,
		WorldObjectDataScript.new(&"pc_no_agent", &"player_character", pc_data.position),
		MoveTargetDataScript.new(Vector3(1.0, 0.0, 1.0))
	):
		bare_actor.free()
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController accepted an actor without a NavigationAgent3D.")
	if movement_controller_has_event_bus:
		if ctx.movement_failed_count != 1 or ctx.movement_failed_reason != &"missing_navigation_agent":
			bare_actor.free()
			_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
			return ctx.fail("MovementController did not emit missing_navigation_agent.")
	bare_actor.free()

	ctx.movement_failed_count = 0
	ctx.movement_failed_reason = &""
	if movement_controller.request_move(pc_view, pc_data, MoveTargetDataScript.new(Vector3(8.0, 0.0, 8.0))):
		_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
		return ctx.fail("MovementController accepted movement without a nav path.")
	if movement_controller_has_event_bus:
		if ctx.movement_failed_count != 1 or ctx.movement_failed_reason != &"no_path":
			_free_movement_fixture(ctx, root_event_bus, movement_controller, pc_view, navigation_map, navigation_region)
			return ctx.fail("MovementController did not emit no_path for missing nav.")
		ctx.disconnect_if_connected(root_event_bus, &"movement_started", movement_started_callable)
		ctx.disconnect_if_connected(root_event_bus, &"movement_completed", movement_completed_callable)
		ctx.disconnect_if_connected(root_event_bus, &"movement_failed", movement_failed_callable)

	movement_controller.free()
	ctx.free_nav_map(navigation_map, navigation_region)
	pc_view.free()
	return true

func _free_targeting_fixture(
	ctx,
	root_event_bus: Node,
	move_requested_callable: Callable,
	targeting_controller: Node,
	move_target_parent: Node,
	pc_view: Node
) -> void:
	ctx.disconnect_if_connected(root_event_bus, &"move_requested", move_requested_callable)
	if targeting_controller != null:
		targeting_controller.free()
	if move_target_parent != null:
		move_target_parent.free()
	if pc_view != null:
		pc_view.free()

func _free_movement_fixture(
	ctx,
	root_event_bus: Node,
	movement_controller: Node,
	pc_view: Node,
	navigation_map: RID,
	navigation_region: RID
) -> void:
	ctx.disconnect_if_connected(root_event_bus, &"movement_started", ctx.movement_started_callable())
	ctx.disconnect_if_connected(root_event_bus, &"movement_completed", ctx.movement_completed_callable())
	ctx.disconnect_if_connected(root_event_bus, &"movement_failed", ctx.movement_failed_callable())
	if movement_controller != null:
		movement_controller.free()
	ctx.free_nav_map(navigation_map, navigation_region)
	if pc_view != null:
		pc_view.free()
