extends RefCounted

const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const DevMenuScript := preload("res://src/editor/dev_menu.gd")
const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const EditorModeControllerScript := preload("res://src/editor/editor_mode_controller.gd")
const EditorPanelScript := preload("res://src/editor/editor_panel.gd")
const EditorSelectionControllerScript := preload("res://src/editor/editor_selection_controller.gd")
const GroundDataScript := preload("res://src/environment/ground_data.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapFileStoreScript := preload("res://src/editor/map_file_store.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

var _mode_changed_count: int = 0
var _latest_mode: StringName = &""
var _tool_changed_count: int = 0
var _latest_tool: StringName = &""
var _wall_mode_changed_count: int = 0
var _latest_wall_mode: StringName = &""
var _selection_count: int = 0
var _selected_node: Node
var _selected_data: Resource
var _selected_kind: StringName = &""
var _map_loaded_count: int = 0
var _map_loaded_data: Resource
var _map_loaded_path: String = ""
var _map_saved_count: int = 0
var _map_saved_data: Resource
var _map_saved_path: String = ""

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	if root_event_bus == null:
		return ctx.fail("Editor suite requires EventBus.")

	_reset_records()
	ctx.connect_if_needed(root_event_bus, &"editor_mode_changed", Callable(self, "_record_mode_changed"))
	ctx.connect_if_needed(root_event_bus, &"editor_tool_changed", Callable(self, "_record_tool_changed"))
	ctx.connect_if_needed(root_event_bus, &"editor_wall_brush_mode_changed", Callable(self, "_record_wall_mode_changed"))
	ctx.connect_if_needed(root_event_bus, &"editor_selection_changed", Callable(self, "_record_selection_changed"))
	ctx.connect_if_needed(root_event_bus, &"editor_map_loaded", Callable(self, "_record_map_loaded"))
	ctx.connect_if_needed(root_event_bus, &"editor_map_saved", Callable(self, "_record_map_saved"))

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_disconnect_records(ctx, root_event_bus)
		return ctx.fail("Main scene did not load for editor suite.")

	var original_root_size: Vector2i = ctx.root().size
	ctx.root().size = Vector2i(1280, 720)
	var main := main_scene.instantiate() as Node3D
	ctx.root().add_child(main)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var result := await _run_editor_checks(ctx, root_event_bus, main)
	if main != null:
		main.free()
	ctx.root().size = original_root_size
	_disconnect_records(ctx, root_event_bus)
	_cleanup_saved_map("editor_suite_runtime_map")
	return result

func _run_editor_checks(ctx, _root_event_bus: Node, main: Node3D) -> bool:
	var navigation_region := main.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var map_loader := main.get_node_or_null("MapLoader") as MapLoaderScript
	var interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	var editor_mode_controller := main.get_node_or_null("EditorModeController") as EditorModeControllerScript
	var editor_selection_controller := main.get_node_or_null("EditorSelectionController") as EditorSelectionControllerScript
	var camera := main.get_node_or_null("CameraRig/PitchPivot/Camera3D") as Camera3D
	var interaction_ui := main.get_node_or_null("InteractionUI") as CanvasLayer
	var dev_menu: DevMenuScript
	var editor_panel: EditorPanelScript
	if interaction_ui != null:
		dev_menu = interaction_ui.get_node_or_null("DevMenu") as DevMenuScript
		editor_panel = interaction_ui.get_node_or_null("EditorPanel") as EditorPanelScript
	if (
		navigation_region == null
		or map_loader == null
		or interaction_controller == null
		or editor_mode_controller == null
		or editor_selection_controller == null
		or camera == null
		or dev_menu == null
		or editor_panel == null
	):
		return ctx.fail("Editor suite main scene is missing required nodes.")

	if dev_menu.visible or editor_panel.visible:
		return ctx.fail("Editor UI should start hidden.")

	var action_event := InputEventAction.new()
	action_event.action = &"toggle_dev_menu"
	action_event.pressed = true
	editor_mode_controller._unhandled_input(action_event)
	if not dev_menu.visible:
		return ctx.fail("toggle_dev_menu did not show the centered dev menu.")
	editor_mode_controller._unhandled_input(action_event)
	if dev_menu.visible:
		return ctx.fail("toggle_dev_menu did not hide the centered dev menu.")

	editor_mode_controller.enter_editor_mode()
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if editor_mode_controller.get_mode() != EditorModeControllerScript.MODE_EDITOR:
		return ctx.fail("EditorModeController did not enter editor mode.")
	if _latest_mode != EditorModeControllerScript.MODE_EDITOR:
		return ctx.fail("Editor mode switch did not emit editor_mode_changed.")
	if not editor_panel.visible:
		return ctx.fail("EditorPanel did not appear in editor mode.")
	if editor_panel.is_tool_panel_expanded():
		return ctx.fail("EditorPanel should start collapsed to tool buttons only.")
	if editor_panel.get_active_tool() != EditorPanelScript.TOOL_SELECT_INSPECT:
		return ctx.fail("EditorPanel should default to the select/inspect tool.")
	if editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_SELECT_INSPECT:
		return ctx.fail("EditorSelectionController should default to the select/inspect tool.")
	if interaction_controller.is_gameplay_input_enabled():
		return ctx.fail("InteractionController gameplay input stayed enabled in editor mode.")
	if map_loader.map_data == null or map_loader.map_data.map_id != MapFileStoreScript.BLANK_EDITOR_MAP_ID:
		return ctx.fail("Editor mode did not load the blank editor map.")
	if navigation_region.get_node_or_null("GeneratedMap/StaticGrounds/editor_ground") == null:
		return ctx.fail("Blank editor map did not rebuild generated ground.")
	if _map_loaded_count < 1 or _map_loaded_data != map_loader.map_data:
		return ctx.fail("Blank editor map load did not emit editor_map_loaded.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_SELECT_INSPECT)
	await ctx.tree.process_frame
	if not editor_panel.is_tool_panel_expanded() or editor_panel.get_expanded_tool() != EditorPanelScript.TOOL_SELECT_INSPECT:
		return ctx.fail("Select/Inspect tool button did not expand the inspector panel.")
	if not _tool_label_has_usable_width(
		editor_panel,
		^"EditorToolDockLayout/ToolContent/SelectInspectContent/SelectInspectContentPadding/InspectorContent"
	):
		return ctx.fail("Inspector label did not receive usable wrapping width.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_SELECT_INSPECT)
	if editor_panel.is_tool_panel_expanded():
		return ctx.fail("Clicking the active Select/Inspect tool did not collapse the panel.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_NPC_BRUSH)
	await ctx.tree.process_frame
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_NPC_BRUSH
		or editor_panel.get_expanded_tool() != EditorPanelScript.TOOL_NPC_BRUSH
		or _latest_tool != EditorPanelScript.TOOL_NPC_BRUSH
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_NPC_BRUSH
	):
		return ctx.fail("NPC Brush tool did not become the active expanded editor tool.")
	if not _tool_label_has_usable_width(
		editor_panel,
		^"EditorToolDockLayout/ToolContent/NpcBrushContent/NpcBrushContentPadding/NpcBrushProperties"
	):
		return ctx.fail("NPC Brush label did not receive the same usable wrapping width.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_PC_BRUSH)
	await ctx.tree.process_frame
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_PC_BRUSH
		or editor_panel.get_expanded_tool() != EditorPanelScript.TOOL_PC_BRUSH
		or _latest_tool != EditorPanelScript.TOOL_PC_BRUSH
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_PC_BRUSH
	):
		return ctx.fail("PC Brush tool did not become the active expanded editor tool.")
	if not _tool_label_has_usable_width(
		editor_panel,
		^"EditorToolDockLayout/ToolContent/PcBrushContent/PcBrushContentPadding/PcBrushProperties"
	):
		return ctx.fail("PC Brush label did not receive a usable wrapping width.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_SELECT_INSPECT)
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_SELECT_INSPECT
		or editor_panel.get_expanded_tool() != EditorPanelScript.TOOL_SELECT_INSPECT
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_SELECT_INSPECT
	):
		return ctx.fail("Select/Inspect tool did not reactivate after the character brush tools.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_WALL_BRUSH)
	await ctx.tree.process_frame
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_WALL_BRUSH
		or editor_panel.get_expanded_tool() != EditorPanelScript.TOOL_WALL_BRUSH
		or editor_panel.get_wall_brush_mode() != EditorPanelScript.WALL_BRUSH_MODE_LINE
		or _latest_tool != EditorPanelScript.TOOL_WALL_BRUSH
		or _latest_wall_mode != EditorPanelScript.WALL_BRUSH_MODE_LINE
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_WALL_BRUSH
		or editor_selection_controller.get_wall_brush_mode() != EditorSelectionControllerScript.WALL_BRUSH_MODE_LINE
	):
		return ctx.fail("Wall Brush did not activate in default line mode.")
	if not _tool_label_has_usable_width(
		editor_panel,
		^"EditorToolDockLayout/ToolContent/WallBrushContent/WallBrushContentPadding/WallBrushProperties/WallBrushDetails"
	):
		return ctx.fail("Wall Brush label did not receive a usable wrapping width.")
	editor_panel.set_wall_brush_mode(EditorPanelScript.WALL_BRUSH_MODE_RECTANGLE)
	await ctx.tree.process_frame
	if (
		editor_panel.get_wall_brush_mode() != EditorPanelScript.WALL_BRUSH_MODE_RECTANGLE
		or _latest_wall_mode != EditorPanelScript.WALL_BRUSH_MODE_RECTANGLE
		or editor_selection_controller.get_wall_brush_mode() != EditorSelectionControllerScript.WALL_BRUSH_MODE_RECTANGLE
	):
		return ctx.fail("Wall Brush rectangle mode did not propagate to editor input.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_SELECT_INSPECT)
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_SELECT_INSPECT
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_SELECT_INSPECT
	):
		return ctx.fail("Select/Inspect tool did not reactivate after the wall brush tool.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_DOOR_BRUSH)
	await ctx.tree.process_frame
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_DOOR_BRUSH
		or editor_panel.get_expanded_tool() != EditorPanelScript.TOOL_DOOR_BRUSH
		or _latest_tool != EditorPanelScript.TOOL_DOOR_BRUSH
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_DOOR_BRUSH
	):
		return ctx.fail("Door Brush tool did not become the active expanded editor tool.")
	if not _tool_label_has_usable_width(
		editor_panel,
		^"EditorToolDockLayout/ToolContent/DoorBrushContent/DoorBrushContentPadding/DoorBrushProperties"
	):
		return ctx.fail("Door Brush label did not receive a usable wrapping width.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_BUILDING_BRUSH)
	await ctx.tree.process_frame
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_BUILDING_BRUSH
		or editor_panel.get_expanded_tool() != EditorPanelScript.TOOL_BUILDING_BRUSH
		or _latest_tool != EditorPanelScript.TOOL_BUILDING_BRUSH
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_BUILDING_BRUSH
	):
		return ctx.fail("Building Brush tool did not become the active expanded editor tool.")
	if not _tool_label_has_usable_width(
		editor_panel,
		^"EditorToolDockLayout/ToolContent/BuildingBrushContent/BuildingBrushContentPadding/BuildingBrushProperties/BuildingBrushDetails"
	):
		return ctx.fail("Building Brush label did not receive a usable wrapping width.")
	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_SELECT_INSPECT)
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_SELECT_INSPECT
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_SELECT_INSPECT
	):
		return ctx.fail("Select/Inspect tool did not reactivate after the door/building brush tools.")

	var start_panel_position := editor_panel.get_panel_position()
	var drag_press := InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_RIGHT
	drag_press.pressed = true
	drag_press.position = Vector2(8.0, 8.0)
	editor_panel._gui_input(drag_press)
	if not editor_panel.is_dragging():
		return ctx.fail("Editor tool dock did not start dragging on right mouse press.")
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = Vector2(-32.0, 28.0)
	editor_panel._input(drag_motion)
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_RIGHT
	drag_release.pressed = false
	drag_release.position = Vector2(-32.0, 28.0)
	editor_panel._input(drag_release)
	if editor_panel.is_dragging():
		return ctx.fail("Editor tool dock did not stop dragging on right mouse release.")
	if editor_panel.get_panel_position() == start_panel_position:
		return ctx.fail("Editor tool dock right-mouse drag did not move the panel.")
	if not ctx.control_inside_viewport(editor_panel):
		return ctx.fail("Editor tool dock drag moved the panel outside the viewport.")

	editor_mode_controller.enter_game_mode()
	await ctx.tree.process_frame
	if editor_mode_controller.get_mode() != EditorModeControllerScript.MODE_GAME:
		return ctx.fail("EditorModeController did not return to game mode.")
	if not interaction_controller.is_gameplay_input_enabled():
		return ctx.fail("InteractionController gameplay input did not re-enable in game mode.")
	if editor_panel.visible:
		return ctx.fail("EditorPanel stayed visible in game mode.")

	editor_mode_controller.enter_editor_mode()
	await ctx.tree.process_frame
	if not editor_panel.visible or editor_panel.is_tool_panel_expanded():
		return ctx.fail("EditorPanel did not return to buttons-only state when re-entering editor mode.")
	var editor_map := _create_editor_test_map()
	map_loader.replace_map_data(editor_map, true)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var generated_map := navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map == null:
		return ctx.fail("Editor test map did not generate content.")
	if not _generated_nodes_have_editor_metadata(generated_map):
		return ctx.fail("Generated map nodes are missing editor selection metadata.")

	var pc_view := generated_map.get_node_or_null("WorldObjects/editor_object") as BlockoutObjectViewScript
	var object_target: InteractionTargetScript
	if pc_view != null:
		object_target = pc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if object_target == null:
		return ctx.fail("Editor test world object is missing its InteractionTarget.")
	if interaction_controller.start_targeting(object_target, InteractionActionResolverScript.ACTION_MOVE):
		return ctx.fail("InteractionController accepted gameplay targeting in editor mode.")

	var object_position := pc_view.global_position + BlockoutObjectViewScript.body_center_offset(pc_view.object_data.size_m)
	var object_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, object_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not editor_selection_controller.select_at_screen(object_screen_position):
		return ctx.fail("Editor selection raycast did not select a generated world object.")
	if _selected_kind != MapBuilderScript.EDITOR_KIND_WORLD_OBJECT or _selected_data != pc_view.object_data:
		return ctx.fail("Editor selection emitted the wrong world-object payload.")
	if pc_view.get_node_or_null("Body/EditorSelectionShell") == null:
		return ctx.fail("World-object selection did not create an editor highlight shell.")
	var object_inspector := editor_panel.get_inspector_text()
	if not object_inspector.contains("world_object") or not object_inspector.contains("editor_object"):
		return ctx.fail("Inspector did not render selected world-object fields.")
	if not _tool_label_has_usable_width(
		editor_panel,
		^"EditorToolDockLayout/ToolContent/SelectInspectContent/SelectInspectContentPadding/InspectorContent"
	):
		return ctx.fail("Inspector label collapsed to a character-wrapping width after selection.")

	var wall_node := generated_map.get_node_or_null("StaticWalls/Wall_00") as Node3D
	if wall_node == null:
		return ctx.fail("Editor test wall was not generated.")
	var wall_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, wall_node.global_position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not editor_selection_controller.select_at_screen(wall_screen_position):
		return ctx.fail("Editor selection raycast did not select a generated wall.")
	if _selected_kind != MapBuilderScript.EDITOR_KIND_WALL:
		return ctx.fail("Editor selection emitted the wrong wall kind.")
	if pc_view.get_node_or_null("Body/EditorSelectionShell") != null:
		return ctx.fail("Editor selection highlight did not clear from the prior world object.")
	if wall_node.get_node_or_null("Mesh/EditorSelectionShell") == null:
		return ctx.fail("Wall selection did not create an editor highlight shell.")
	var wall_inspector := editor_panel.get_inspector_text()
	if not wall_inspector.contains("wall") or not wall_inspector.contains("line"):
		return ctx.fail("Inspector did not render selected wall fields.")

	var ground_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(-3.0, 0.0, -3.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not editor_selection_controller.select_at_screen(ground_screen_position):
		return ctx.fail("Editor selection raycast did not select generated ground.")
	if _selected_kind != MapBuilderScript.EDITOR_KIND_GROUND:
		return ctx.fail("Editor selection emitted the wrong ground kind.")
	var ground_node := generated_map.get_node_or_null("StaticGrounds/editor_ground_test") as StaticBody3D
	if ground_node == null or ground_node.get_node_or_null("Mesh/EditorSelectionShell") == null:
		return ctx.fail("Ground selection did not create an editor highlight shell.")
	var ground_inspector := editor_panel.get_inspector_text()
	if not ground_inspector.contains("ground") or not ground_inspector.contains("editor_ground_test") or not ground_inspector.contains("size"):
		return ctx.fail("Inspector did not render selected ground fields.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_NPC_BRUSH)
	await ctx.tree.process_frame
	var object_count_before_brush := map_loader.map_data.world_objects.size()
	var brush_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(2.0, 0.0, -2.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var brush_click := InputEventMouseButton.new()
	brush_click.button_index = MOUSE_BUTTON_LEFT
	brush_click.pressed = true
	brush_click.position = brush_screen_position
	editor_selection_controller._unhandled_input(brush_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.world_objects.size() != object_count_before_brush + 1:
		return ctx.fail("NPC Brush did not append a world object to the editor map.")
	var placed_npc := map_loader.map_data.world_objects[map_loader.map_data.world_objects.size() - 1]
	if placed_npc.object_kind != &"non_player_character":
		return ctx.fail("NPC Brush placed a world object with the wrong kind.")
	if not String(placed_npc.object_id).begins_with("npc_"):
		return ctx.fail("NPC Brush did not assign an npc_* object id.")
	if placed_npc.position.distance_to(Vector3(2.0, 0.0, -2.0)) > 0.2:
		return ctx.fail("NPC Brush did not place the NPC near the clicked ground point.")
	if _selected_node != null or _selected_data != null or _selected_kind != &"":
		return ctx.fail("NPC Brush should clear selection after placing an NPC.")
	if editor_selection_controller.get_selected_data() != null:
		return ctx.fail("EditorSelectionController kept a selected resource after NPC Brush placement.")
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	var placed_npc_node := generated_map.get_node_or_null("WorldObjects/%s" % String(placed_npc.object_id)) as BlockoutObjectViewScript
	if placed_npc_node == null:
		return ctx.fail("NPC Brush did not rebuild generated content with the placed NPC.")
	if placed_npc_node.get_node_or_null("Body/EditorSelectionShell") != null:
		return ctx.fail("NPC Brush should not highlight the newly placed NPC.")
	var npc_inspector := editor_panel.get_inspector_text()
	if npc_inspector != "No selection":
		return ctx.fail("Inspector should show no selection after NPC Brush placement.")

	var object_count_after_valid_brush := map_loader.map_data.world_objects.size()
	var empty_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(20.0, 0.0, 20.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if editor_selection_controller.place_npc_at_screen(empty_screen_position) != null:
		return ctx.fail("NPC Brush placed an object when clicking empty space.")
	if map_loader.map_data.world_objects.size() != object_count_after_valid_brush:
		return ctx.fail("NPC Brush changed map data after an empty-space click.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_PC_BRUSH)
	await ctx.tree.process_frame
	var object_count_before_pc_brush := map_loader.map_data.world_objects.size()
	var pc_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(-2.0, 0.0, -2.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var pc_click := InputEventMouseButton.new()
	pc_click.button_index = MOUSE_BUTTON_LEFT
	pc_click.pressed = true
	pc_click.position = pc_screen_position
	editor_selection_controller._unhandled_input(pc_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.world_objects.size() != object_count_before_pc_brush + 1:
		return ctx.fail("PC Brush did not append a world object to the editor map.")
	var placed_pc := map_loader.map_data.world_objects[map_loader.map_data.world_objects.size() - 1]
	if placed_pc.object_kind != &"player_character":
		return ctx.fail("PC Brush placed a world object with the wrong kind.")
	if placed_pc.object_id != &"pc_001":
		return ctx.fail("PC Brush did not assign the first pc_* object id.")
	if not MoveTargetResolverScript.can_start_move_data(placed_pc):
		return ctx.fail("PC Brush placed a world object that movement rules cannot control.")
	if placed_pc.position.distance_to(Vector3(-2.0, 0.0, -2.0)) > 0.2:
		return ctx.fail("PC Brush did not place the PC near the clicked ground point.")
	var second_pc_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(-4.0, 0.0, -2.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var second_pc_click := InputEventMouseButton.new()
	second_pc_click.button_index = MOUSE_BUTTON_LEFT
	second_pc_click.pressed = true
	second_pc_click.position = second_pc_screen_position
	editor_selection_controller._unhandled_input(second_pc_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.world_objects.size() != object_count_before_pc_brush + 2:
		return ctx.fail("PC Brush did not allow multiple player-character placements.")
	var second_pc := map_loader.map_data.world_objects[map_loader.map_data.world_objects.size() - 1]
	if second_pc.object_kind != &"player_character" or second_pc.object_id != &"pc_002":
		return ctx.fail("PC Brush did not assign a second controllable PC correctly.")
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if (
		generated_map.get_node_or_null("WorldObjects/pc_001") == null
		or generated_map.get_node_or_null("WorldObjects/pc_002") == null
	):
		return ctx.fail("PC Brush did not rebuild generated content with multiple PCs.")
	if editor_panel.get_inspector_text() != "No selection":
		return ctx.fail("Inspector should show no selection after PC Brush placement.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_WALL_BRUSH)
	await ctx.tree.process_frame
	var wall_count_before_line := map_loader.map_data.static_walls.size()
	var line_start_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(-4.0, 0.0, -4.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var line_start_click := InputEventMouseButton.new()
	line_start_click.button_index = MOUSE_BUTTON_LEFT
	line_start_click.pressed = true
	line_start_click.position = line_start_screen_position
	editor_selection_controller._unhandled_input(line_start_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.static_walls.size() != wall_count_before_line:
		return ctx.fail("Wall Brush line mode should wait for a second click before adding a wall.")
	if not editor_selection_controller.has_pending_wall_brush_point():
		return ctx.fail("Wall Brush line mode did not keep the first clicked point pending.")
	var line_end_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(-2.0, 0.0, -4.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var line_end_click := InputEventMouseButton.new()
	line_end_click.button_index = MOUSE_BUTTON_LEFT
	line_end_click.pressed = true
	line_end_click.position = line_end_screen_position
	editor_selection_controller._unhandled_input(line_end_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.static_walls.size() != wall_count_before_line + 1:
		return ctx.fail("Wall Brush line mode did not append one wall after the second click.")
	if editor_selection_controller.has_pending_wall_brush_point():
		return ctx.fail("Wall Brush line mode kept a pending point after creating the wall.")
	var line_wall := map_loader.map_data.static_walls[map_loader.map_data.static_walls.size() - 1]
	if (
		line_wall.start_position.distance_to(Vector3(-4.0, 0.0, -4.0)) > 0.2
		or line_wall.end_position.distance_to(Vector3(-2.0, 0.0, -4.0)) > 0.2
		or not is_equal_approx(line_wall.height_m, 2.2)
		or not is_equal_approx(line_wall.thickness_m, 0.18)
	):
		return ctx.fail("Wall Brush line mode wrote the wrong wall data.")
	if line_wall.start_position.y != 0.0 or line_wall.end_position.y != 0.0:
		return ctx.fail("Wall Brush line mode did not flatten wall endpoints to y = 0.")
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map.get_node_or_null("StaticWalls/Wall_%02d" % wall_count_before_line) == null:
		return ctx.fail("Wall Brush line mode did not rebuild generated content with the new wall.")
	if editor_panel.get_inspector_text() != "No selection":
		return ctx.fail("Inspector should show no selection after Wall Brush line placement.")

	editor_panel.set_wall_brush_mode(EditorPanelScript.WALL_BRUSH_MODE_RECTANGLE)
	await ctx.tree.process_frame
	var wall_count_before_rectangle := map_loader.map_data.static_walls.size()
	var rectangle_start_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(1.0, 0.0, -4.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var rectangle_start_click := InputEventMouseButton.new()
	rectangle_start_click.button_index = MOUSE_BUTTON_LEFT
	rectangle_start_click.pressed = true
	rectangle_start_click.position = rectangle_start_screen_position
	editor_selection_controller._unhandled_input(rectangle_start_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.static_walls.size() != wall_count_before_rectangle:
		return ctx.fail("Wall Brush rectangle mode should wait for a second click before adding walls.")
	if not editor_selection_controller.has_pending_wall_brush_point():
		return ctx.fail("Wall Brush rectangle mode did not keep the first clicked point pending.")
	var rectangle_end_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(4.0, 0.0, -1.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var rectangle_end_click := InputEventMouseButton.new()
	rectangle_end_click.button_index = MOUSE_BUTTON_LEFT
	rectangle_end_click.pressed = true
	rectangle_end_click.position = rectangle_end_screen_position
	editor_selection_controller._unhandled_input(rectangle_end_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.static_walls.size() != wall_count_before_rectangle + 4:
		return ctx.fail("Wall Brush rectangle mode did not append four walls after the second click.")
	if editor_selection_controller.has_pending_wall_brush_point():
		return ctx.fail("Wall Brush rectangle mode kept a pending point after creating the room.")
	if not _wall_matches(
		map_loader.map_data.static_walls[wall_count_before_rectangle],
		Vector3(1.0, 0.0, -4.0),
		Vector3(4.0, 0.0, -4.0)
	):
		return ctx.fail("Wall Brush rectangle mode wrote the first room edge incorrectly.")
	if not _wall_matches(
		map_loader.map_data.static_walls[wall_count_before_rectangle + 1],
		Vector3(4.0, 0.0, -4.0),
		Vector3(4.0, 0.0, -1.0)
	):
		return ctx.fail("Wall Brush rectangle mode wrote the second room edge incorrectly.")
	if not _wall_matches(
		map_loader.map_data.static_walls[wall_count_before_rectangle + 2],
		Vector3(4.0, 0.0, -1.0),
		Vector3(1.0, 0.0, -1.0)
	):
		return ctx.fail("Wall Brush rectangle mode wrote the third room edge incorrectly.")
	if not _wall_matches(
		map_loader.map_data.static_walls[wall_count_before_rectangle + 3],
		Vector3(1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, -4.0)
	):
		return ctx.fail("Wall Brush rectangle mode wrote the fourth room edge incorrectly.")
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map.get_node_or_null("StaticWalls/Wall_%02d" % (wall_count_before_rectangle + 3)) == null:
		return ctx.fail("Wall Brush rectangle mode did not rebuild generated content with all room walls.")
	if editor_panel.get_inspector_text() != "No selection":
		return ctx.fail("Inspector should show no selection after Wall Brush rectangle placement.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_DOOR_BRUSH)
	await ctx.tree.process_frame
	var wall_count_before_door := map_loader.map_data.static_walls.size()
	var socket_count_before_door := map_loader.map_data.door_sockets.size()
	var door_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(0.0, 0.0, 2.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var door_click := InputEventMouseButton.new()
	door_click.button_index = MOUSE_BUTTON_LEFT
	door_click.pressed = true
	door_click.position = door_screen_position
	editor_selection_controller._unhandled_input(door_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data.door_sockets.size() != socket_count_before_door + 1:
		return ctx.fail("Door Brush did not append a door socket to the editor map.")
	if map_loader.map_data.static_walls.size() != wall_count_before_door + 1:
		return ctx.fail("Door Brush did not split one wall into two wall segments.")
	var placed_socket := map_loader.map_data.door_sockets[map_loader.map_data.door_sockets.size() - 1]
	if placed_socket.socket_id != &"door_socket_001":
		return ctx.fail("Door Brush did not assign the expected door_socket_* id.")
	if placed_socket.position.distance_to(Vector3(0.0, 0.0, 2.0)) > 0.2:
		return ctx.fail("Door Brush did not snap the socket to the clicked wall point.")
	if not is_equal_approx(placed_socket.width_m, 1.0):
		return ctx.fail("Door Brush did not use a 1m socket width.")
	if placed_socket.color != Color(0.82, 0.9, 0.84, 1.0):
		return ctx.fail("Door Brush did not use the expected light grey-green marker color.")
	if not _wall_matches(
		map_loader.map_data.static_walls[0],
		Vector3(-1.0, 0.0, 2.0),
		Vector3(-0.5, 0.0, 2.0),
		2.0,
		0.2
	):
		return ctx.fail("Door Brush did not keep the left wall segment up to the 1m gap.")
	if not _wall_matches(
		map_loader.map_data.static_walls[1],
		Vector3(0.5, 0.0, 2.0),
		Vector3(1.0, 0.0, 2.0),
		2.0,
		0.2
	):
		return ctx.fail("Door Brush did not keep the right wall segment after the 1m gap.")
	if editor_panel.get_inspector_text() != "No selection":
		return ctx.fail("Inspector should show no selection after Door Brush placement.")
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	var placed_socket_node := generated_map.get_node_or_null("DoorSockets/door_socket_001") as Node3D
	if placed_socket_node == null:
		return ctx.fail("Door Brush did not rebuild generated content with the placed door socket.")
	var placed_socket_marker := placed_socket_node.get_node_or_null("Marker") as MeshInstance3D
	if placed_socket_marker == null or not (placed_socket_marker.mesh is CylinderMesh):
		return ctx.fail("Door Brush marker did not generate a visible circle mesh.")
	var placed_socket_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, placed_socket.position)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not editor_selection_controller.select_at_screen(placed_socket_screen_position):
		return ctx.fail("Editor selection raycast did not select a generated door socket.")
	if _selected_kind != MapBuilderScript.EDITOR_KIND_DOOR_SOCKET or _selected_data != placed_socket:
		return ctx.fail("Editor selection emitted the wrong door-socket payload.")
	var socket_inspector := editor_panel.get_inspector_text()
	if not socket_inspector.contains("door_socket") or not socket_inspector.contains("door_socket_001"):
		return ctx.fail("Inspector did not render selected door socket fields.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_BUILDING_BRUSH)
	await ctx.tree.process_frame
	var wall_count_before_building := map_loader.map_data.static_walls.size()
	var socket_count_before_building := map_loader.map_data.door_sockets.size()
	var building_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3(3.0, 0.0, 3.0))
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	var building_click := InputEventMouseButton.new()
	building_click.button_index = MOUSE_BUTTON_LEFT
	building_click.pressed = true
	building_click.position = building_screen_position
	editor_selection_controller._unhandled_input(building_click)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not editor_selection_controller.has_building_preview():
		return ctx.fail("Building Brush did not create a transient preview after a ground click.")
	if editor_selection_controller.get_node_or_null("BuildingBrushPreview") == null:
		return ctx.fail("Building Brush preview did not create visible preview geometry.")
	if map_loader.map_data.static_walls.size() != wall_count_before_building:
		return ctx.fail("Building Brush preview should not append walls before Submit.")
	if map_loader.map_data.door_sockets.size() != socket_count_before_building:
		return ctx.fail("Building Brush preview should not append door sockets before Submit.")
	var width_slider := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/BuildingBrushContent/BuildingBrushContentPadding/BuildingBrushProperties/BuildingWidthSliderRow/BuildingWidthSlider"
	) as HSlider
	if width_slider == null:
		return ctx.fail("Building Brush width slider was not created.")
	width_slider.value = 12.0
	await ctx.tree.process_frame
	var adjusted_preview := editor_selection_controller.get_building_preview_result()
	var adjusted_bounds: Dictionary = adjusted_preview.get("bounds", {})
	var adjusted_width := float(adjusted_bounds.get("max_x", 0.0)) - float(adjusted_bounds.get("min_x", 0.0))
	if not is_equal_approx(adjusted_width, 12.0):
		return ctx.fail("Building Brush slider changes did not regenerate the preview.")
	var preview_walls: Array = adjusted_preview.get("walls", [])
	var preview_sockets: Array = adjusted_preview.get("door_sockets", [])
	if preview_walls.is_empty() or preview_sockets.is_empty():
		return ctx.fail("Building Brush preview did not contain generated walls and door sockets.")
	var submit_button := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/BuildingBrushContent/BuildingBrushContentPadding/BuildingBrushProperties/BuildingBrushActionRow/BuildingSubmitButton"
	) as Button
	if submit_button == null:
		return ctx.fail("Building Brush submit button was not created.")
	submit_button.emit_signal(&"pressed")
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if editor_selection_controller.has_building_preview():
		return ctx.fail("Building Brush kept the preview after Submit.")
	if map_loader.map_data.static_walls.size() != wall_count_before_building + preview_walls.size():
		return ctx.fail("Building Brush Submit did not append the preview walls to the map.")
	if map_loader.map_data.door_sockets.size() != socket_count_before_building + preview_sockets.size():
		return ctx.fail("Building Brush Submit did not append the preview door sockets to the map.")
	var building_socket := map_loader.map_data.door_sockets[map_loader.map_data.door_sockets.size() - 1] as DoorSocketDataScript
	if building_socket == null or not String(building_socket.socket_id).begins_with("building_door_"):
		return ctx.fail("Building Brush Submit did not assign building_door_* socket ids.")
	var building_socket_id := String(building_socket.socket_id)
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map.get_node_or_null("DoorSockets/%s" % building_socket_id) == null:
		return ctx.fail("Building Brush Submit did not rebuild generated door socket nodes.")
	if editor_panel.get_inspector_text() != "No selection":
		return ctx.fail("Inspector should show no selection after Building Brush Submit.")

	var saved_door_socket_count := map_loader.map_data.door_sockets.size()
	var saved_path := editor_mode_controller.save_current_map("editor_suite_runtime_map")
	if saved_path.is_empty() or not ResourceLoader.exists(saved_path):
		return ctx.fail("Editor map save did not write a .tres resource.")
	if _map_saved_count != 1 or _map_saved_data != map_loader.map_data or _map_saved_path != saved_path:
		return ctx.fail("Editor map save did not emit editor_map_saved.")

	map_loader.replace_map_data(MapFileStoreScript.new().create_blank_editor_map(), true)
	await ctx.tree.process_frame
	if map_loader.map_data.map_id == "editor_suite_map":
		return ctx.fail("Editor save/load test did not replace the current map before loading.")
	var loaded_map := editor_mode_controller.load_map("editor_suite_runtime_map")
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if loaded_map == null or map_loader.map_data != loaded_map:
		return ctx.fail("Editor map load did not replace MapLoader.map_data.")
	if map_loader.map_data.map_id != "editor_suite_map":
		return ctx.fail("Editor map load returned the wrong MapData.")
	if navigation_region.get_node_or_null("GeneratedMap/WorldObjects/editor_object") == null:
		return ctx.fail("Editor map load did not rebuild generated world objects.")
	if (
		map_loader.map_data.door_sockets.size() != saved_door_socket_count
		or navigation_region.get_node_or_null("GeneratedMap/DoorSockets/door_socket_001") == null
		or navigation_region.get_node_or_null("GeneratedMap/DoorSockets/%s" % building_socket_id) == null
	):
		return ctx.fail("Editor map load did not preserve and rebuild door sockets.")
	if _map_loaded_data != loaded_map or _map_loaded_path != saved_path:
		return ctx.fail("Editor map load did not emit editor_map_loaded.")

	return true

func _create_editor_test_map() -> MapDataScript:
	var ground := GroundDataScript.new(
		&"editor_ground_test",
		Vector3(0.0, -0.05, 0.0),
		Vector3(12.0, 0.1, 12.0),
		Color(0.2, 0.24, 0.2, 1.0)
	)
	var wall := WallDataScript.new(
		Vector3(-1.0, 0.0, 2.0),
		Vector3(1.0, 0.0, 2.0),
		2.0,
		0.2,
		Color(0.3, 0.32, 0.34, 1.0)
	)
	var world_object := WorldObjectDataScript.new(
		&"editor_object",
		&"player_character",
		Vector3(0.5, 0.0, 0.5),
		Vector3(0.5, 1.8, 0.5),
		Color(0.1, 0.45, 0.95, 1.0)
	)
	var grounds: Array[GroundDataScript] = []
	var walls: Array[WallDataScript] = []
	var objects: Array[WorldObjectDataScript] = []
	grounds.append(ground)
	walls.append(wall)
	objects.append(world_object)
	return MapDataScript.new("editor_suite_map", grounds, walls, objects)

func _generated_nodes_have_editor_metadata(generated_map: Node3D) -> bool:
	var ground := generated_map.get_node_or_null("StaticGrounds/editor_ground_test")
	var wall_body := generated_map.get_node_or_null("StaticWalls/Wall_00/StaticBody3D")
	var world_object := generated_map.get_node_or_null("WorldObjects/editor_object")
	return (
		ground != null
		and ground.has_meta(MapBuilderScript.EDITOR_KIND_META)
		and wall_body != null
		and wall_body.has_meta(MapBuilderScript.EDITOR_SOURCE_META)
		and world_object != null
		and world_object.has_meta(MapBuilderScript.EDITOR_SOURCE_META)
	)

func _tool_label_has_usable_width(editor_panel: EditorPanelScript, label_path: NodePath) -> bool:
	var label := editor_panel.get_node_or_null(label_path) as Label
	return label != null and label.size.x >= 180.0

func _wall_matches(
	wall: WallDataScript,
	expected_start: Vector3,
	expected_end: Vector3,
	expected_height_m: float = 2.2,
	expected_thickness_m: float = 0.18
) -> bool:
	return (
		wall != null
		and wall.start_position.distance_to(expected_start) <= 0.2
		and wall.end_position.distance_to(expected_end) <= 0.2
		and wall.start_position.y == 0.0
		and wall.end_position.y == 0.0
		and is_equal_approx(wall.height_m, expected_height_m)
		and is_equal_approx(wall.thickness_m, expected_thickness_m)
	)

func _reset_records() -> void:
	_mode_changed_count = 0
	_latest_mode = &""
	_tool_changed_count = 0
	_latest_tool = &""
	_wall_mode_changed_count = 0
	_latest_wall_mode = &""
	_selection_count = 0
	_selected_node = null
	_selected_data = null
	_selected_kind = &""
	_map_loaded_count = 0
	_map_loaded_data = null
	_map_loaded_path = ""
	_map_saved_count = 0
	_map_saved_data = null
	_map_saved_path = ""

func _record_mode_changed(mode: StringName) -> void:
	_mode_changed_count += 1
	_latest_mode = mode

func _record_tool_changed(tool_id: StringName) -> void:
	_tool_changed_count += 1
	_latest_tool = tool_id

func _record_wall_mode_changed(mode: StringName) -> void:
	_wall_mode_changed_count += 1
	_latest_wall_mode = mode

func _record_selection_changed(selected_node: Node, selected_data: Resource, selected_kind: StringName) -> void:
	_selection_count += 1
	_selected_node = selected_node
	_selected_data = selected_data
	_selected_kind = selected_kind

func _record_map_loaded(map_data: Resource, path: String) -> void:
	_map_loaded_count += 1
	_map_loaded_data = map_data
	_map_loaded_path = path

func _record_map_saved(map_data: Resource, path: String) -> void:
	_map_saved_count += 1
	_map_saved_data = map_data
	_map_saved_path = path

func _disconnect_records(ctx, root_event_bus: Node) -> void:
	ctx.disconnect_if_connected(root_event_bus, &"editor_mode_changed", Callable(self, "_record_mode_changed"))
	ctx.disconnect_if_connected(root_event_bus, &"editor_tool_changed", Callable(self, "_record_tool_changed"))
	ctx.disconnect_if_connected(root_event_bus, &"editor_wall_brush_mode_changed", Callable(self, "_record_wall_mode_changed"))
	ctx.disconnect_if_connected(root_event_bus, &"editor_selection_changed", Callable(self, "_record_selection_changed"))
	ctx.disconnect_if_connected(root_event_bus, &"editor_map_loaded", Callable(self, "_record_map_loaded"))
	ctx.disconnect_if_connected(root_event_bus, &"editor_map_saved", Callable(self, "_record_map_saved"))

func _cleanup_saved_map(requested_name: String) -> void:
	var store := MapFileStoreScript.new()
	var path := ProjectSettings.globalize_path(store.map_path_for_name(requested_name))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
