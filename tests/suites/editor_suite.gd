extends RefCounted

const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const DevMenuScript := preload("res://src/editor/dev_menu.gd")
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
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

var _mode_changed_count: int = 0
var _latest_mode: StringName = &""
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
	if interaction_controller.is_gameplay_input_enabled():
		return ctx.fail("InteractionController gameplay input stayed enabled in editor mode.")
	if map_loader.map_data == null or map_loader.map_data.map_id != MapFileStoreScript.BLANK_EDITOR_MAP_ID:
		return ctx.fail("Editor mode did not load the blank editor map.")
	if navigation_region.get_node_or_null("GeneratedMap/StaticGrounds/editor_ground") == null:
		return ctx.fail("Blank editor map did not rebuild generated ground.")
	if _map_loaded_count < 1 or _map_loaded_data != map_loader.map_data:
		return ctx.fail("Blank editor map load did not emit editor_map_loaded.")

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

func _reset_records() -> void:
	_mode_changed_count = 0
	_latest_mode = &""
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
	ctx.disconnect_if_connected(root_event_bus, &"editor_selection_changed", Callable(self, "_record_selection_changed"))
	ctx.disconnect_if_connected(root_event_bus, &"editor_map_loaded", Callable(self, "_record_map_loaded"))
	ctx.disconnect_if_connected(root_event_bus, &"editor_map_saved", Callable(self, "_record_map_saved"))

func _cleanup_saved_map(requested_name: String) -> void:
	var store := MapFileStoreScript.new()
	var path := ProjectSettings.globalize_path(store.map_path_for_name(requested_name))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
