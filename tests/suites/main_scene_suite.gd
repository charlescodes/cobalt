extends RefCounted

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const DebugLogPanelScript := preload("res://src/ui/debug_log_panel.gd")
const CameraCompassScript := preload("res://src/ui/camera_compass.gd")
const BspDebugPanelScript := preload("res://src/ui/bsp_debug_panel.gd")
const DebugOverlayControllerScript := preload("res://src/ui/debug_overlay_controller.gd")
const NavigationDebugOverlayScript := preload("res://src/ui/navigation_debug_overlay.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const MovementControllerScript := preload("res://src/movement/movement_controller.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const BspDebugMapControllerScript := preload("res://src/debug/bsp_debug_map_controller.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return ctx.fail("Main scene did not load.")
	var main := main_scene.instantiate()
	ctx.root().add_child(main)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if main.get_node_or_null("HexGridManager") != null:
		main.free()
		return ctx.fail("Main scene still contains HexGridManager.")
	if main.get_node_or_null("NavigationRegion3D") == null:
		main.free()
		return ctx.fail("Main scene is missing NavigationRegion3D.")
	var navigation_region := main.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if navigation_region.navigation_mesh == null:
		main.free()
		return ctx.fail("NavigationRegion3D is missing a NavigationMesh.")
	var map_loader := main.get_node_or_null("MapLoader") as MapLoaderScript
	if map_loader == null or map_loader.map_data == null:
		main.free()
		return ctx.fail("Main scene is missing MapLoader data.")
	var startup_bsp_debug_map_controller := main.get_node_or_null("BspDebugMapController") as BspDebugMapControllerScript
	if startup_bsp_debug_map_controller == null:
		main.free()
		return ctx.fail("Main scene is missing BspDebugMapController.")
	if not startup_bsp_debug_map_controller.is_bsp_enabled():
		main.free()
		return ctx.fail("Main scene should start in BSP debug map mode.")
	if map_loader.map_data.map_id != "bsp_debug":
		main.free()
		return ctx.fail("Main scene did not start with the BSP debug map.")
	if map_loader.map_data.static_walls.size() <= 4 or map_loader.map_data.world_objects.size() != 2:
		main.free()
		return ctx.fail("Startup BSP debug map is missing generated walls or actors.")
	var startup_debug_log_panel := main.get_node_or_null("InteractionUI/DebugLogPanel") as DebugLogPanelScript
	var startup_bsp_debug_panel := main.get_node_or_null("InteractionUI/BspDebugPanel") as BspDebugPanelScript
	var startup_navigation_debug_overlay := main.get_node_or_null("NavigationDebugOverlay") as NavigationDebugOverlayScript
	if startup_debug_log_panel == null or startup_bsp_debug_panel == null or startup_navigation_debug_overlay == null:
		main.free()
		return ctx.fail("Startup BSP debug mode is missing debug overlays.")
	if not startup_debug_log_panel.visible or not startup_bsp_debug_panel.visible or not startup_navigation_debug_overlay.visible:
		main.free()
		return ctx.fail("Startup BSP debug mode should show debug log and navigation overlays.")
	var startup_generated_map := navigation_region.get_node_or_null("GeneratedMap") as Node3D
	var startup_pc := startup_generated_map.get_node_or_null("WorldObjects/pc_001") as BlockoutObjectViewScript if startup_generated_map != null else null
	var startup_npc := startup_generated_map.get_node_or_null("WorldObjects/npc_001") as BlockoutObjectViewScript if startup_generated_map != null else null
	if startup_pc == null or startup_npc == null:
		main.free()
		return ctx.fail("Startup BSP debug map did not instantiate PC and NPC views.")
	var startup_navigation_map := navigation_region.get_navigation_map()
	await ctx.wait_for_scene_navigation_map(startup_navigation_map)
	var startup_bsp_path_result := MoveTargetResolverScript.navigation_path_result(
		startup_navigation_map,
		startup_pc.object_data.position,
		startup_npc.object_data.position
	)
	if not bool(startup_bsp_path_result.get("ok", false)):
		main.free()
		return ctx.fail(
			"Startup BSP debug map did not produce a path from PC to exterior NPC. reason=%s iteration=%s"
			% [
				startup_bsp_path_result.get("reason", &""),
				str(startup_bsp_path_result.get("navigation_map_iteration", 0)),
			]
		)
	startup_bsp_debug_map_controller.set_bsp_enabled(false)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if startup_bsp_debug_map_controller.is_bsp_enabled():
		main.free()
		return ctx.fail("F12 normal-mode toggle did not disable BSP debug map mode.")
	if map_loader.map_data.map_id != "main_blockout":
		main.free()
		return ctx.fail("F12 normal-mode toggle did not restore the authored map.")
	var generated_map := navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map == null:
		main.free()
		return ctx.fail("Main scene did not generate its MapData content.")
	if generated_map.get_node_or_null("StaticGrounds/Ground") as StaticBody3D == null:
		main.free()
		return ctx.fail("Main scene is missing a static ground body.")
	var ground_target := generated_map.get_node_or_null("StaticGrounds/Ground/GroundMoveTarget") as InteractionTargetScript
	if ground_target == null:
		main.free()
		return ctx.fail("Main scene is missing the ground move target.")
	if ground_target.target_domain != InteractionActionResolverScript.DOMAIN_MOVE_TARGET:
		main.free()
		return ctx.fail("Ground move target has the wrong domain.")
	if not (ground_target.target_data is MoveTargetDataScript):
		main.free()
		return ctx.fail("Ground move target does not carry MoveTargetData.")
	var static_walls := generated_map.get_node_or_null("StaticWalls") as Node3D
	if static_walls == null or static_walls.get_child_count() != 2:
		main.free()
		return ctx.fail("Main scene should generate two static walls.")
	if map_loader.map_data.static_walls.size() != 2 or not map_loader.map_data.static_walls[0].is_valid_segment():
		main.free()
		return ctx.fail("Main scene first map wall segment is invalid.")
	var wall_body := generated_map.get_node_or_null("StaticWalls/Wall_00/StaticBody3D") as StaticBody3D
	if wall_body == null:
		main.free()
		return ctx.fail("Main scene static wall is missing collision body.")
	var movement_controller := main.get_node_or_null("MovementController") as MovementControllerScript
	if movement_controller == null:
		main.free()
		return ctx.fail("Main scene is missing MovementController.")
	var interaction_ui := main.get_node_or_null("InteractionUI") as CanvasLayer
	if interaction_ui == null:
		main.free()
		return ctx.fail("Main scene is missing InteractionUI CanvasLayer.")
	var main_interaction_menu := interaction_ui.get_node_or_null("InteractionMenu") as InteractionMenuScript
	if main_interaction_menu == null:
		main.free()
		return ctx.fail("Main scene is missing InteractionMenu.")
	main_interaction_menu._ready()
	if interaction_ui.get_node_or_null("InteractionLogPanel") == null:
		main.free()
		return ctx.fail("Main scene is missing InteractionLogPanel.")
	var debug_log_panel := interaction_ui.get_node_or_null("DebugLogPanel") as DebugLogPanelScript
	if debug_log_panel == null:
		main.free()
		return ctx.fail("Main scene is missing DebugLogPanel.")
	if debug_log_panel.visible:
		main.free()
		return ctx.fail("DebugLogPanel should be hidden until F12 toggles debug.")
	var camera_compass := interaction_ui.get_node_or_null("CameraCompass") as CameraCompassScript
	if camera_compass == null:
		main.free()
		return ctx.fail("Main scene is missing CameraCompass.")
	var bsp_debug_panel := interaction_ui.get_node_or_null("BspDebugPanel") as BspDebugPanelScript
	if bsp_debug_panel == null:
		main.free()
		return ctx.fail("Main scene is missing BspDebugPanel.")
	if bsp_debug_panel.visible:
		main.free()
		return ctx.fail("BspDebugPanel should be hidden in authored normal mode.")
	var navigation_debug_overlay := main.get_node_or_null("NavigationDebugOverlay") as NavigationDebugOverlayScript
	if navigation_debug_overlay == null:
		main.free()
		return ctx.fail("Main scene is missing NavigationDebugOverlay.")
	if navigation_debug_overlay.visible:
		main.free()
		return ctx.fail("NavigationDebugOverlay should be hidden until F12 toggles debug.")
	var debug_overlay_controller := main.get_node_or_null("DebugOverlayController") as DebugOverlayControllerScript
	if debug_overlay_controller == null:
		main.free()
		return ctx.fail("Main scene is missing DebugOverlayController.")
	var bsp_debug_map_controller := main.get_node_or_null("BspDebugMapController") as BspDebugMapControllerScript
	if bsp_debug_map_controller == null:
		main.free()
		return ctx.fail("Main scene is missing BspDebugMapController.")
	debug_overlay_controller.set_debug_visible(true)
	if not debug_log_panel.visible or not navigation_debug_overlay.visible:
		main.free()
		return ctx.fail("DebugOverlayController did not show both debug overlays.")
	debug_overlay_controller.set_debug_visible(false)
	if debug_log_panel.visible or navigation_debug_overlay.visible:
		main.free()
		return ctx.fail("DebugOverlayController did not hide both debug overlays.")
	if main.get_node_or_null("SunLight") == null:
		main.free()
		return ctx.fail("Main scene is missing SunLight.")
	var main_pc := generated_map.get_node_or_null("WorldObjects/pc_001") as BlockoutObjectViewScript
	if main_pc == null or main_pc.object_data == null:
		main.free()
		return ctx.fail("Main scene is missing PlayerCharacter data.")
	if main_pc.get_navigation_agent() == null:
		main.free()
		return ctx.fail("Main scene PlayerCharacter is missing a NavigationAgent3D.")
	var scene_navigation_map := navigation_region.get_navigation_map()
	await ctx.wait_for_scene_navigation_map(scene_navigation_map)
	var default_map_path_result := MoveTargetResolverScript.navigation_path_result(
		scene_navigation_map,
		main_pc.object_data.position,
		Vector3(2.0, 0.0, 0.0)
	)
	if not bool(default_map_path_result.get("ok", false)):
		main.free()
		return ctx.fail(
			"Main scene default map did not produce a native nav path. reason=%s iteration=%s start_snap=%s target_snap=%s"
			% [
				default_map_path_result.get("reason", &""),
				str(default_map_path_result.get("navigation_map_iteration", 0)),
				str(default_map_path_result.get("snapped_start", Vector3.ZERO)),
				str(default_map_path_result.get("snapped_target", Vector3.ZERO)),
			]
		)
	movement_controller.movement_speed_mps = 10.0
	if not movement_controller.request_move(
		main_pc,
		main_pc.object_data,
		MoveTargetDataScript.new(Vector3(2.0, 0.0, 0.0))
	):
		main.free()
		return ctx.fail("Main scene MovementController rejected the first real-map move.")
	for _index in range(40):
		await ctx.tree.physics_frame
		movement_controller._physics_process(0.1)
		if not movement_controller.is_actor_busy(main_pc):
			break
	if movement_controller.is_actor_busy(main_pc):
		main.free()
		return ctx.fail("Main scene MovementController did not complete the first real-map move.")
	if not movement_controller.request_move(
		main_pc,
		main_pc.object_data,
		MoveTargetDataScript.new(Vector3(1.0, 0.0, 1.0))
	):
		main.free()
		return ctx.fail("Main scene MovementController rejected a second real-map move after completion.")
	for _index in range(40):
		await ctx.tree.physics_frame
		movement_controller._physics_process(0.1)
		if not movement_controller.is_actor_busy(main_pc):
			break
	if movement_controller.is_actor_busy(main_pc):
		main.free()
		return ctx.fail("Main scene MovementController did not complete the second real-map move.")
	var main_npc := generated_map.get_node_or_null("WorldObjects/npc_001") as BlockoutObjectViewScript
	if main_npc == null or main_npc.object_data == null:
		main.free()
		return ctx.fail("Main scene is missing NPC data.")
	if main_npc.get_navigation_agent() == null:
		main.free()
		return ctx.fail("Main scene NPC is missing a NavigationAgent3D.")
	if main_npc.position != main_npc.object_data.position:
		main.free()
		return ctx.fail("NPC view is not using WorldObjectData.position.")
	var main_npc_target := main_npc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if main_npc_target == null:
		main.free()
		return ctx.fail("NPC did not create an InteractionTarget.")
	if ctx.has_action(InteractionActionResolverScript.get_actions(main_npc_target), InteractionActionResolverScript.ACTION_MOVE):
		main.free()
		return ctx.fail("NPC interaction target should not expose Move.")
	if MoveTargetResolverScript.can_start_move(main_npc_target):
		main.free()
		return ctx.fail("MoveTargetResolver accepted an NPC as a move source.")

	var main_interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	if main_interaction_controller == null:
		main.free()
		return ctx.fail("Main scene is missing InteractionController.")
	main_interaction_controller._ready()
	if root_event_bus != null and main_interaction_menu._get_event_bus() != null and main_interaction_controller._get_event_bus() != null:
		root_event_bus.emit_signal(&"interaction_menu_requested", main_npc_target, Vector2.ZERO)
		if not main_interaction_menu.visible:
			main.free()
			return ctx.fail("InteractionMenu did not open from a main scene menu request.")
		root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
		if main_interaction_menu.visible:
			main.free()
			return ctx.fail("InteractionMenu did not close from a main scene cancel request.")

	var authored_map_data := map_loader.map_data
	bsp_debug_map_controller.set_bsp_enabled(true)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not bsp_debug_map_controller.is_bsp_enabled():
		main.free()
		return ctx.fail("BspDebugMapController did not enable the generated BSP map.")
	if map_loader.map_data == authored_map_data:
		main.free()
		return ctx.fail("BspDebugMapController did not swap MapLoader.map_data.")
	if map_loader.map_data.map_id != "bsp_debug":
		main.free()
		return ctx.fail("BSP debug map has the wrong map id.")
	if map_loader.map_data.grounds.size() != 1:
		main.free()
		return ctx.fail("BSP debug map should contain one buffered ground.")
	if map_loader.map_data.static_walls.size() <= 4:
		main.free()
		return ctx.fail("BSP debug map did not produce internal wall fragments.")
	if map_loader.map_data.world_objects.size() != 2:
		main.free()
		return ctx.fail("BSP debug map should contain PC and NPC objects.")
	if not debug_log_panel.visible or not navigation_debug_overlay.visible:
		main.free()
		return ctx.fail("BSP debug mode did not show debug log and navigation overlays.")
	var bsp_generated_map := navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if bsp_generated_map == null:
		main.free()
		return ctx.fail("BSP debug map did not rebuild GeneratedMap.")
	if bsp_generated_map.get_node_or_null("WorldObjects/pc_001") as BlockoutObjectViewScript == null:
		main.free()
		return ctx.fail("BSP debug map did not instantiate the PC.")
	if bsp_generated_map.get_node_or_null("WorldObjects/npc_001") as BlockoutObjectViewScript == null:
		main.free()
		return ctx.fail("BSP debug map did not instantiate the NPC.")

	bsp_debug_map_controller.set_bsp_enabled(false)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if bsp_debug_map_controller.is_bsp_enabled():
		main.free()
		return ctx.fail("BspDebugMapController did not disable the generated BSP map.")
	if map_loader.map_data != authored_map_data:
		main.free()
		return ctx.fail("BspDebugMapController did not restore the authored map data.")
	if debug_log_panel.visible or bsp_debug_panel.visible or navigation_debug_overlay.visible:
		main.free()
		return ctx.fail("BspDebugMapController did not restore the previous debug overlay visibility.")
	var restored_map := navigation_region.get_node_or_null("GeneratedMap") as Node3D
	var restored_walls := restored_map.get_node_or_null("StaticWalls") as Node3D if restored_map != null else null
	if restored_walls == null or restored_walls.get_child_count() != 2:
		main.free()
		return ctx.fail("BspDebugMapController did not restore the authored generated map.")

	main.free()
	return true
