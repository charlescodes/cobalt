extends RefCounted

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const WallLayoutViewScript := preload("res://src/walls/wall_layout_view.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return ctx.fail("Main scene did not load.")
	var main := main_scene.instantiate()
	ctx.root().add_child(main)
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
	if navigation_region.get_node_or_null("Floor") as StaticBody3D == null:
		main.free()
		return ctx.fail("Main scene is missing a static floor body.")
	var floor_target := navigation_region.get_node_or_null("Floor/FloorMoveTarget") as InteractionTargetScript
	if floor_target == null:
		main.free()
		return ctx.fail("Main scene is missing the floor move target.")
	if floor_target.target_domain != InteractionActionResolverScript.DOMAIN_MOVE_TARGET:
		main.free()
		return ctx.fail("Floor move target has the wrong domain.")
	if not (floor_target.target_data is MoveTargetDataScript):
		main.free()
		return ctx.fail("Floor move target does not carry MoveTargetData.")
	var main_wall_layout := navigation_region.get_node_or_null("WallLayout") as WallLayoutViewScript
	if main_wall_layout == null:
		main.free()
		return ctx.fail("Main scene wall layout should be inside the navigation region.")
	if main_wall_layout.wall_segments.size() != 2:
		main.free()
		return ctx.fail("Main scene wall layout should contain two sample wall segments.")
	if not main_wall_layout.wall_segments[0].is_valid_segment():
		main.free()
		return ctx.fail("Main scene first wall segment is invalid.")
	main_wall_layout.apply_layout()
	var main_wall_visual_root := main_wall_layout.get_node_or_null("WallVisuals")
	if main_wall_visual_root == null or main_wall_visual_root.get_child_count() != 2:
		main.free()
		return ctx.fail("Main scene wall layout did not build its static wall nodes.")
	if main.get_node_or_null("MovementController") == null:
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
	if main.get_node_or_null("SunLight") == null:
		main.free()
		return ctx.fail("Main scene is missing SunLight.")
	var main_pc := main.get_node_or_null("PlayerCharacter") as BlockoutObjectViewScript
	if main_pc == null or main_pc.object_data == null:
		main.free()
		return ctx.fail("Main scene is missing PlayerCharacter data.")
	if main_pc.get_navigation_agent() == null:
		main.free()
		return ctx.fail("Main scene PlayerCharacter is missing a NavigationAgent3D.")
	var main_npc := main.get_node_or_null("NPC") as BlockoutObjectViewScript
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

	main.free()
	return true
