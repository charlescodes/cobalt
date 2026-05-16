extends RefCounted

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const InteractionLogPanelScript := preload("res://src/ui/interaction_log_panel.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	if root_event_bus == null:
		return ctx.fail("Main scene interaction raycast check requires EventBus.")

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return ctx.fail("Main scene did not load for interaction raycast check.")

	var original_root_size: Vector2i = ctx.root().size
	ctx.root().size = Vector2i(1280, 720)
	var navigation_map := RID()
	var navigation_region_rid := RID()
	var signals_connected := false
	var main := main_scene.instantiate() as Node3D
	ctx.root().add_child(main)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var camera := main.get_node_or_null("CameraRig/PitchPivot/Camera3D") as Camera3D
	var interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	var interaction_ui := main.get_node_or_null("InteractionUI") as CanvasLayer
	var interaction_menu: InteractionMenuScript
	var interaction_log_panel: InteractionLogPanelScript
	if interaction_ui != null:
		interaction_menu = interaction_ui.get_node_or_null("InteractionMenu") as InteractionMenuScript
		interaction_log_panel = interaction_ui.get_node_or_null("InteractionLogPanel") as InteractionLogPanelScript
	var main_pc := main.get_node_or_null("PlayerCharacter") as BlockoutObjectViewScript
	var main_npc := main.get_node_or_null("NPC") as BlockoutObjectViewScript
	var navigation_region := main.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if (
		camera == null
		or interaction_controller == null
		or interaction_menu == null
		or interaction_log_panel == null
		or main_pc == null
		or main_npc == null
		or navigation_region == null
	):
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Main scene interaction raycast check is missing required nodes.")

	interaction_controller._ready()
	interaction_menu._ready()
	interaction_log_panel._ready()

	var pc_target := main_pc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	var npc_target := main_npc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	var floor_target := navigation_region.get_node_or_null("Floor/FloorMoveTarget") as InteractionTargetScript
	if pc_target == null or npc_target == null or floor_target == null:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Main scene interaction raycast check is missing interaction targets.")
	if not pc_target.input_ray_pickable or not npc_target.input_ray_pickable or not floor_target.input_ray_pickable:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Main scene interaction targets are not ray-pickable.")
	if pc_target.target_data != main_pc.object_data or npc_target.target_data != main_npc.object_data:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "World-object interaction targets do not carry their object data.")

	var nav: Dictionary = ctx.create_square_nav_map()
	navigation_map = nav["map"]
	navigation_region_rid = nav["region"]
	main_pc.get_navigation_agent().set_navigation_map(navigation_map)
	await ctx.wait_for_navigation_map(navigation_map)

	var hover_callable: Callable = ctx.hover_changed_callable()
	var move_requested_callable: Callable = ctx.move_requested_callable()
	var examined_callable: Callable = ctx.examined_output_callable()
	ctx.connect_if_needed(root_event_bus, &"hover_target_changed", hover_callable)
	ctx.connect_if_needed(root_event_bus, &"move_requested", move_requested_callable)
	ctx.connect_if_needed(root_event_bus, &"examined_output", examined_callable)
	signals_connected = true

	ctx.reset_hover_changed()
	var pc_hover_position := main_pc.global_position + BlockoutObjectViewScript.body_center_offset(main_pc.object_data.size_m)
	var pc_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, pc_hover_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	ctx.drive_interaction_hover_at_screen(interaction_controller, pc_screen_position)
	if ctx.hover_changed_target != pc_target:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "CameraRig raycast did not hover the player character InteractionTarget.")
	if main_pc.get_node_or_null("Body/HoverShell") == null:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Player hover did not apply a highlight shell.")

	var hover_count_before_capture: int = ctx.hover_changed_count
	interaction_controller._handle_interaction_pointer_capture_changed(true)
	var npc_hover_position := main_npc.global_position + BlockoutObjectViewScript.body_center_offset(main_npc.object_data.size_m)
	ctx.warp_mouse_to_world(camera, npc_hover_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	interaction_controller._physics_process(0.016)
	if ctx.hover_changed_count != hover_count_before_capture or ctx.hover_changed_target != pc_target:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "InteractionController changed hover while pointer capture was active.")
	interaction_controller._handle_interaction_pointer_capture_changed(false)

	ctx.warp_mouse_to_world(camera, npc_hover_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	ctx.drive_interaction_hover_at_screen(interaction_controller, camera.unproject_position(npc_hover_position))
	if ctx.hover_changed_target != npc_target:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "CameraRig raycast did not hover the NPC InteractionTarget.")
	if main_pc.get_node_or_null("Body/HoverShell") != null:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Player hover highlight was not cleared after hovering the NPC.")
	if main_npc.get_node_or_null("Body/HoverShell") == null:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "NPC hover did not apply a highlight shell.")

	ctx.warp_mouse_to_world(camera, pc_hover_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	ctx.drive_interaction_hover_at_screen(interaction_controller, pc_screen_position)
	interaction_controller._request_menu_for_current_target(pc_screen_position)
	await ctx.tree.process_frame
	await ctx.tree.process_frame
	if not interaction_menu.visible:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "InteractionMenu did not open from the hovered player target.")
	if not interaction_controller.is_interaction_pointer_captured():
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "InteractionMenu did not capture the interaction pointer.")
	if not ctx.control_inside_viewport(interaction_menu):
		var menu_rect := Rect2(interaction_menu.position, interaction_menu.size)
		var viewport_size := interaction_menu.get_viewport_rect().size
		return _fail_raycast(
			ctx,
			root_event_bus,
			main,
			original_root_size,
			navigation_map,
			navigation_region_rid,
			signals_connected,
			"InteractionMenu was not clamped inside the viewport. rect=%s viewport=%s." % [menu_rect, viewport_size]
		)
	root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
	if interaction_menu.visible or interaction_controller.is_interaction_pointer_captured():
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "InteractionMenu did not close from a cancel request.")

	interaction_controller._request_menu_for_current_target(pc_screen_position)
	await ctx.tree.process_frame
	await ctx.tree.process_frame
	root_event_bus.emit_signal(&"hover_target_changed", npc_target)
	if interaction_menu.visible:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "InteractionMenu did not close when hover changed targets.")

	ctx.reset_examined_output()
	root_event_bus.emit_signal(&"interaction_action_requested", npc_target, InteractionActionResolverScript.ACTION_EXAMINE)
	if ctx.examined_count != 1:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Examine action did not emit examined_output.")
	if ctx.examined_target_domain != InteractionActionResolverScript.DOMAIN_WORLD_OBJECT:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Examine output carried the wrong target domain.")
	if ctx.examined_target_data != main_npc.object_data:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Examine output carried the wrong target data.")
	if ctx.examined_output.get("object_id") != main_npc.object_data.object_id:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Examine output did not include the NPC object id.")
	var log_label := interaction_log_panel.get_node_or_null("Content") as Label
	if log_label == null or not log_label.text.contains("npc_001"):
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "InteractionLogPanel did not render the examined NPC data.")

	if interaction_controller.start_targeting(npc_target, InteractionActionResolverScript.ACTION_MOVE):
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "NPC target started move targeting.")
	if not interaction_controller.start_targeting(pc_target, InteractionActionResolverScript.ACTION_MOVE):
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "PC target did not start move targeting.")

	ctx.warp_mouse_to_world(camera, pc_hover_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	ctx.drive_interaction_hover_at_screen(
		interaction_controller,
		pc_screen_position,
		InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	)
	if ctx.hover_changed_target == pc_target:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Move targeting raycast did not filter out world-object targets.")

	var floor_click_position := Vector3(2.0, 0.0, 0.0)
	var floor_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, floor_click_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var expected_floor_hit: Dictionary = ctx.raycast_first_area_hit(camera, floor_screen_position)
	if expected_floor_hit.is_empty() or expected_floor_hit.get("collider") != floor_target:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "CameraRig raycast did not hit the floor move target.")
	ctx.drive_interaction_hover_at_screen(
		interaction_controller,
		floor_screen_position,
		InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	)
	if ctx.hover_changed_target != floor_target:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Move targeting did not hover the floor move target.")
	var expected_floor_position: Vector3 = expected_floor_hit.get("position", Vector3.ZERO)
	var floor_data := floor_target.target_data as MoveTargetDataScript
	if floor_data == null or floor_data.position.distance_to(expected_floor_position) > 0.001:
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Floor MoveTargetData did not preserve the exact raycast hit position.")

	ctx.reset_move_requested()
	if not interaction_controller.try_confirm_targeting_target(floor_target):
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Move targeting did not confirm a reachable floor target.")
	if (
		ctx.move_requested_count != 1
		or ctx.move_requested_actor != main_pc
		or ctx.move_requested_actor_data != main_pc.object_data
		or ctx.move_requested_destination != floor_data
	):
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Move targeting emitted the wrong move_requested payload.")
	if interaction_controller.is_targeting_interaction():
		return _fail_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected, "Move targeting stayed active after confirmation.")

	_cleanup_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected)
	return true

func _fail_raycast(
	ctx,
	root_event_bus: Node,
	main: Node,
	original_root_size: Vector2i,
	navigation_map: RID,
	navigation_region_rid: RID,
	signals_connected: bool,
	message: String
) -> bool:
	_cleanup_raycast(ctx, root_event_bus, main, original_root_size, navigation_map, navigation_region_rid, signals_connected)
	return ctx.fail(message)

func _cleanup_raycast(
	ctx,
	root_event_bus: Node,
	main: Node,
	original_root_size: Vector2i,
	navigation_map: RID,
	navigation_region_rid: RID,
	signals_connected: bool
) -> void:
	if signals_connected:
		ctx.disconnect_if_connected(root_event_bus, &"hover_target_changed", ctx.hover_changed_callable())
		ctx.disconnect_if_connected(root_event_bus, &"move_requested", ctx.move_requested_callable())
		ctx.disconnect_if_connected(root_event_bus, &"examined_output", ctx.examined_output_callable())
	if navigation_map.is_valid() or navigation_region_rid.is_valid():
		ctx.free_nav_map(navigation_map, navigation_region_rid)
	if main != null:
		main.free()
	ctx.root().size = original_root_size
