extends RefCounted

const CameraRigScript := preload("res://src/camera/camera_rig.gd")
const DevMenuScript := preload("res://src/editor/dev_menu.gd")
const EditorModeControllerScript := preload("res://src/editor/editor_mode_controller.gd")
const EditorPanelScript := preload("res://src/editor/editor_panel.gd")
const EditorSelectionControllerScript := preload("res://src/editor/editor_selection_controller.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const MapFileStoreScript := preload("res://src/editor/map_file_store.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const WorldMapBuilderScript := preload("res://src/maps/world_map_builder.gd")
const WorldMapDataScript := preload("res://src/maps/world_map_data.gd")
const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")
const WorldGeologyGeneratorScript := preload("res://src/generation/world_geology_generator.gd")

const WORLD_SUITE_FILENAME := "world_editor_suite_runtime_world"
const WORLD_SUITE_CROSS_LOCAL_FILENAME := "world_editor_suite_world_in_local"
const WORLD_SUITE_CROSS_WORLD_FILENAME := "world_editor_suite_local_in_world"

func run(ctx) -> bool:
	await ctx.idle_frame()
	if not _generator_is_deterministic_and_coastal(ctx):
		return false

	ctx.ensure_root_event_bus()
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return ctx.fail("Main scene did not load for world editor suite.")

	var original_root_size: Vector2i = ctx.root().size
	ctx.root().size = Vector2i(1280, 720)
	var main := main_scene.instantiate() as Node3D
	ctx.root().add_child(main)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var result := await _run_world_editor_checks(ctx, main)
	if main != null:
		main.free()
	ctx.root().size = original_root_size
	_cleanup_saved_map(WORLD_SUITE_FILENAME)
	_cleanup_saved_map(WORLD_SUITE_CROSS_LOCAL_FILENAME)
	_cleanup_saved_map(WORLD_SUITE_CROSS_WORLD_FILENAME)
	return result

func _generator_is_deterministic_and_coastal(ctx) -> bool:
	var geology := WorldGeologyDataScript.new("world_suite", Vector2(500000.0, 500000.0))
	geology.coast_enabled = true
	geology.coast_edge = WorldGeologyDataScript.COAST_WEST
	var first := WorldGeologyGeneratorScript.generate(geology, 17)
	var second := WorldGeologyGeneratorScript.generate(geology, 17)
	if first.is_empty() or second.is_empty():
		return ctx.fail("World geology generator returned no data.")

	var first_vertices: PackedVector3Array = first.get("vertices", PackedVector3Array())
	var second_vertices: PackedVector3Array = second.get("vertices", PackedVector3Array())
	var first_colors: PackedColorArray = first.get("colors", PackedColorArray())
	var second_colors: PackedColorArray = second.get("colors", PackedColorArray())
	if first_vertices.size() != 289 or first_colors.size() != 289:
		return ctx.fail("World geology generator did not produce the expected grid buffers.")
	if first_vertices[73] != second_vertices[73] or first_colors[73] != second_colors[73]:
		return ctx.fail("World geology generator is not deterministic for the same seed.")

	var elevation: PackedFloat32Array = first.get("elevation", PackedFloat32Array())
	if elevation.is_empty():
		return ctx.fail("World geology generator did not return elevation samples.")
	var west_edge := 0.0
	var east_edge := 0.0
	for z in range(17):
		west_edge += elevation[z * 17]
		east_edge += elevation[(z * 17) + 16]
	if not west_edge < east_edge:
		return ctx.fail("West coast option did not lower the west edge relative to the inland edge.")

	return true

func _run_world_editor_checks(ctx, main: Node3D) -> bool:
	var navigation_region := main.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var map_loader := main.get_node_or_null("MapLoader") as MapLoaderScript
	var interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	var editor_mode_controller := main.get_node_or_null("EditorModeController") as EditorModeControllerScript
	var editor_selection_controller := main.get_node_or_null("EditorSelectionController") as EditorSelectionControllerScript
	var camera := main.get_node_or_null("CameraRig/PitchPivot/Camera3D") as Camera3D
	var camera_rig := main.get_node_or_null("CameraRig") as CameraRigScript
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
		or camera_rig == null
		or dev_menu == null
		or editor_panel == null
	):
		return ctx.fail("World editor suite main scene is missing required nodes.")

	var original_map_data := map_loader.get_local_map_data()
	if original_map_data == null:
		return ctx.fail("World editor suite expected startup to use local MapData.")
	if dev_menu.get_node_or_null("MenuLayout/ModeRow/WorldEditorModeButton") == null:
		return ctx.fail("DevMenu is missing the World mode button.")

	var local_camera_rig_position := camera_rig.position
	editor_mode_controller.enter_world_editor_mode()
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if editor_mode_controller.get_mode() != EditorModeControllerScript.MODE_WORLD_EDITOR:
		return ctx.fail("EditorModeController did not enter world editor mode.")
	var save_button := dev_menu.get_node_or_null("MenuLayout/FileRow/SaveMapButton") as Button
	var load_button := dev_menu.get_node_or_null("MenuLayout/FileRow/LoadMapButton") as Button
	if save_button == null or save_button.text != "Save World":
		return ctx.fail("DevMenu should label save as world while World editor mode is active.")
	if load_button == null or load_button.text != "Load World":
		return ctx.fail("DevMenu should label load as world while World editor mode is active.")
	var world_map_data := map_loader.get_world_map_data()
	if map_loader.map_data == original_map_data or world_map_data == null:
		return ctx.fail("World editor mode did not replace the local map with WorldMapData.")
	if world_map_data.geology == null:
		return ctx.fail("WorldMapData should own the world geology data.")
	if _resource_has_property(world_map_data, "grounds"):
		return ctx.fail("WorldMapData should not expose local ground arrays.")
	if interaction_controller.is_gameplay_input_enabled():
		return ctx.fail("World editor mode should disable gameplay interaction input.")
	var world_size := world_map_data.geology.size_m
	if (
		not is_equal_approx(world_size.x, 500000.0)
		or not is_equal_approx(world_size.y, 500000.0)
	):
		return ctx.fail("World editor mode did not create the expected 500km geology size: %s" % str(world_size))
	var generated_map := navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map == null:
		return ctx.fail("World editor mode did not build GeneratedMap.")
	if (
		generated_map.get_node_or_null("StaticGrounds") != null
		or generated_map.get_node_or_null("StaticWalls") != null
		or generated_map.get_node_or_null("DoorSockets") != null
		or generated_map.get_node_or_null("WorldObjects") != null
	):
		return ctx.fail("WorldMapBuilder should not create local map roots.")
	var world_layer := generated_map.get_node_or_null(String(WorldMapBuilderScript.WORLD_MAP_3D_LAYER_NAME)) as MeshInstance3D
	if world_layer == null or world_layer.mesh == null:
		return ctx.fail("World editor mode did not create a visible 3D world map layer.")
	var world_material := world_layer.material_override as StandardMaterial3D
	if world_material == null or world_material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		return ctx.fail("World map 3D layer should render biome colors without local lighting washing it grey.")
	if not world_material.vertex_color_use_as_albedo or world_material.cull_mode != BaseMaterial3D.CULL_DISABLED:
		return ctx.fail("World map 3D layer should render biome vertex colors as a two-sided surface.")
	var world_mesh := world_layer.mesh as ArrayMesh
	if world_mesh == null or world_mesh.get_surface_count() == 0:
		return ctx.fail("World map 3D layer should expose a renderable ArrayMesh surface.")
	var world_arrays := world_mesh.surface_get_arrays(0)
	var world_vertices: PackedVector3Array = world_arrays[Mesh.ARRAY_VERTEX]
	var world_normals: PackedVector3Array = world_arrays[Mesh.ARRAY_NORMAL]
	if world_vertices.is_empty() or world_normals.size() != world_vertices.size():
		return ctx.fail("World map 3D layer should include normals for every render vertex.")
	if world_layer.has_meta(MapBuilderScript.EDITOR_KIND_META) or world_layer.get_node_or_null("CollisionShape3D") != null:
		return ctx.fail("World map 3D layer should render only, without editor selection metadata or collision.")
	var world_pick_surface := generated_map.get_node_or_null(String(WorldMapBuilderScript.WORLD_PICK_SURFACE_NAME)) as StaticBody3D
	if world_pick_surface == null or world_pick_surface.get_node_or_null("Mesh") != null:
		return ctx.fail("World builder should create a hidden pick/collision surface, not a rendered grey box.")
	var world_pick_collision := world_pick_surface.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var world_pick_shape: BoxShape3D
	if world_pick_collision != null:
		world_pick_shape = world_pick_collision.shape as BoxShape3D
	if (
		world_pick_shape == null
		or not is_equal_approx(world_pick_shape.size.x, world_size.x)
		or not is_equal_approx(world_pick_shape.size.z, world_size.y)
	):
		return ctx.fail("World pick surface collision should be sized from WorldMapData.geology.size_m.")
	if world_layer.custom_aabb.size.x < world_size.x or world_layer.custom_aabb.size.z < world_size.y:
		return ctx.fail("World map 3D layer should use macro render bounds that cover the world ground.")
	if camera.position.z <= 100000.0:
		return ctx.fail("Camera did not switch to a macro-scale world height.")
	if camera.far < 2000000.0:
		return ctx.fail("Camera far clip did not switch to a macro-scale distance.")
	if editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_SELECT_INSPECT:
		return ctx.fail("World editor input should start on Select/Inspect.")

	var rig_start_position := camera_rig.position
	var pan_press := InputEventMouseButton.new()
	pan_press.button_index = MOUSE_BUTTON_RIGHT
	pan_press.pressed = true
	camera_rig._unhandled_input(pan_press)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.relative = Vector2(12.0, -6.0)
	camera_rig._unhandled_input(pan_motion)
	var pan_release := InputEventMouseButton.new()
	pan_release.button_index = MOUSE_BUTTON_RIGHT
	pan_release.pressed = false
	camera_rig._unhandled_input(pan_release)
	if camera_rig.position == rig_start_position:
		return ctx.fail("World camera did not pan with the existing right-mouse binding.")

	var ground_screen_position: Vector2 = ctx.warp_mouse_to_world(camera, Vector3.ZERO)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not editor_selection_controller.select_at_screen(ground_screen_position):
		return ctx.fail("World editor selection raycast did not select the hidden macro ground pick surface.")
	if (
		world_layer.get_node_or_null("EditorSelectionShell") != null
		or world_pick_surface.get_node_or_null("EditorSelectionShell") != null
	):
		return ctx.fail("World ground selection should stay data-only and not create a macro highlight shell.")
	if editor_selection_controller.get_selected_data() != world_map_data:
		return ctx.fail("World pick surface should select the WorldMapData resource, not local GroundData.")
	if editor_selection_controller.place_npc_at_screen(ground_screen_position) != null:
		return ctx.fail("NPC Brush direct call should do nothing in world mode.")
	if editor_selection_controller.place_pc_at_screen(ground_screen_position) != null:
		return ctx.fail("PC Brush direct call should do nothing in world mode.")
	if not editor_selection_controller.add_wall_brush_point_at_screen(ground_screen_position).is_empty():
		return ctx.fail("Wall Brush direct call should do nothing in world mode.")
	if editor_selection_controller.place_door_socket_at_screen(ground_screen_position) != null:
		return ctx.fail("Door Brush direct call should do nothing in world mode.")
	if not editor_selection_controller.place_building_preview_at_screen(ground_screen_position).is_empty():
		return ctx.fail("Bldg. Brush direct call should not create a preview in world mode.")
	if not editor_selection_controller.commit_building_preview().is_empty():
		return ctx.fail("Bldg. Brush commit direct call should do nothing in world mode.")
	if map_loader.get_world_map_data() != world_map_data:
		return ctx.fail("World-mode local brush guards should not replace the world map resource.")

	if not _button_visible(editor_panel, ^"EditorToolDockLayout/ToolButtonRow/SelectInspectToolButton"):
		return ctx.fail("World editor should show Select.")
	if not _button_visible(editor_panel, ^"EditorToolDockLayout/ToolButtonRow/GroundToolButton"):
		return ctx.fail("World editor should show Ground.")
	if not _button_visible(editor_panel, ^"EditorToolDockLayout/ToolButtonRow/GeologyToolButton"):
		return ctx.fail("World editor should show Geology.")
	for hidden_path in [
		^"EditorToolDockLayout/ToolButtonRow/NpcBrushToolButton",
		^"EditorToolDockLayout/ToolButtonRow/PcBrushToolButton",
		^"EditorToolDockLayout/ToolButtonRow/WallBrushToolButton",
		^"EditorToolDockLayout/ToolButtonRow/DoorBrushToolButton",
		^"EditorToolDockLayout/ToolButtonRow/BuildingBrushToolButton",
	]:
		if _button_visible(editor_panel, hidden_path):
			return ctx.fail("World editor exposed a local-map tool that should be hidden.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_NPC_BRUSH)
	if editor_panel.get_active_tool() != EditorPanelScript.TOOL_SELECT_INSPECT:
		return ctx.fail("Hidden local-map tools should not activate in world editor mode.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_GROUND)
	await ctx.tree.process_frame
	var ground_x_slider := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/GroundContent/GroundContentPadding/GroundProperties/GroundSizeXSliderRow/GroundSizeXSlider"
	) as HSlider
	var ground_z_slider := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/GroundContent/GroundContentPadding/GroundProperties/GroundSizeZSliderRow/GroundSizeZSlider"
	) as HSlider
	if ground_x_slider == null or ground_z_slider == null:
		return ctx.fail("World Ground tool sliders were not created.")
	if (
		ground_x_slider.min_value != 250000.0
		or ground_x_slider.max_value != 1000000.0
		or ground_x_slider.step != 10000.0
		or ground_z_slider.min_value != 250000.0
		or ground_z_slider.max_value != 1000000.0
		or ground_z_slider.step != 10000.0
	):
		return ctx.fail("World Ground sliders do not use the expected 250km to 1000km ranges.")
	ground_x_slider.value = 750000.0
	ground_z_slider.value = 800000.0
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	world_map_data = map_loader.get_world_map_data()
	if world_map_data == null or world_map_data.geology == null:
		return ctx.fail("World Ground sliders should keep WorldMapData active.")
	if world_map_data.geology.size_m != Vector2(750000.0, 800000.0):
		return ctx.fail("World Ground resize did not keep geology size in sync.")
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	world_pick_surface = generated_map.get_node_or_null(String(WorldMapBuilderScript.WORLD_PICK_SURFACE_NAME)) as StaticBody3D
	world_pick_collision = null
	if world_pick_surface != null:
		world_pick_collision = world_pick_surface.get_node_or_null("CollisionShape3D") as CollisionShape3D
	world_pick_shape = null
	if world_pick_collision != null:
		world_pick_shape = world_pick_collision.shape as BoxShape3D
	if (
		world_pick_shape == null
		or not is_equal_approx(world_pick_shape.size.x, 750000.0)
		or not is_equal_approx(world_pick_shape.size.z, 800000.0)
	):
		return ctx.fail("World Ground resize did not rebuild the hidden pick surface from geology size.")
	if generated_map.get_node_or_null(String(WorldMapBuilderScript.WORLD_MAP_3D_LAYER_NAME)) == null:
		return ctx.fail("World Ground resize did not rebuild the world map 3D layer.")

	editor_panel.toggle_tool_panel(EditorPanelScript.TOOL_GEOLOGY)
	await ctx.tree.process_frame
	if (
		editor_panel.get_active_tool() != EditorPanelScript.TOOL_GEOLOGY
		or editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_GEOLOGY
	):
		return ctx.fail("Geology tool did not become active in world editor mode.")
	var seed_edit := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/GeologyContent/GeologyContentPadding/GeologyProperties/GeologySeedRow/GeologySeedEdit"
	) as LineEdit
	var coast_check := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/GeologyContent/GeologyContentPadding/GeologyProperties/GeologyCoastRow/GeologyCoastCheck"
	) as CheckBox
	var east_button := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/GeologyContent/GeologyContentPadding/GeologyProperties/GeologyCoastRow/GeologyCoastEastButton"
	) as Button
	var wind_slider := editor_panel.get_node_or_null(
		^"EditorToolDockLayout/ToolContent/GeologyContent/GeologyContentPadding/GeologyProperties/GeologyWindDirectionSliderRow/GeologyWindDirectionSlider"
	) as HSlider
	if seed_edit == null or coast_check == null or east_button == null or wind_slider == null:
		return ctx.fail("Geology panel is missing seed, coast, direction, or wind controls.")
	seed_edit.text = "rain_shadow_suite"
	seed_edit.emit_signal(&"text_submitted", "rain_shadow_suite")
	coast_check.emit_signal(&"toggled", true)
	east_button.emit_signal(&"pressed")
	wind_slider.value = 90.0
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	world_map_data = map_loader.get_world_map_data()
	if world_map_data == null or world_map_data.geology == null:
		return ctx.fail("Geology panel changes should keep WorldMapData active.")
	var geology := world_map_data.geology as WorldGeologyDataScript
	if (
		geology.seed_text != "rain_shadow_suite"
		or not geology.coast_enabled
		or geology.coast_edge != WorldGeologyDataScript.COAST_EAST
		or not is_equal_approx(geology.wind_direction_degrees, 90.0)
	):
		return ctx.fail("Geology panel changes did not update WorldGeologyData.")

	var saved_world_path := editor_mode_controller.save_current_map(WORLD_SUITE_FILENAME)
	if saved_world_path.is_empty() or not ResourceLoader.exists(saved_world_path):
		return ctx.fail("World editor map save did not write a .tres resource.")
	if saved_world_path != MapFileStoreScript.new().world_map_path_for_name(WORLD_SUITE_FILENAME):
		return ctx.fail("World editor map save should write only to the world map directory.")
	var saved_world_resource := ResourceLoader.load(saved_world_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (saved_world_resource is WorldMapDataScript):
		return ctx.fail("World editor map save should write a WorldMapData resource.")
	if not editor_mode_controller.save_local_map(WORLD_SUITE_FILENAME).is_empty():
		return ctx.fail("World editor maps should not be saveable through the local-map save path.")

	editor_mode_controller.enter_editor_mode()
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.get_local_map_data() != original_map_data or map_loader.is_world_map_loaded():
		return ctx.fail("Returning to local Editor mode did not restore the in-memory local map.")
	if camera_rig.position.distance_to(local_camera_rig_position) > 0.001:
		return ctx.fail("Returning to local Editor mode did not restore the local camera rig position.")
	if camera.position.z > 100.0:
		return ctx.fail("Camera did not return to local editor scale.")
	if camera.far > 100000.0:
		return ctx.fail("Camera far clip did not return to local editor scale.")
	if _button_visible(editor_panel, ^"EditorToolDockLayout/ToolButtonRow/GeologyToolButton"):
		return ctx.fail("Local editor mode should hide the Geology tool.")
	if not _button_visible(editor_panel, ^"EditorToolDockLayout/ToolButtonRow/NpcBrushToolButton"):
		return ctx.fail("Local editor mode did not restore local-map tools.")

	var rejected_world_load := editor_mode_controller.load_map(WORLD_SUITE_FILENAME)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if rejected_world_load != null:
		return ctx.fail("Local editor load should not load a world map by filename.")
	if editor_mode_controller.get_mode() != EditorModeControllerScript.MODE_EDITOR:
		return ctx.fail("Rejected world load should keep the controller in local Editor mode.")
	if map_loader.get_local_map_data() != original_map_data or map_loader.is_world_map_loaded():
		return ctx.fail("Rejected world load should not replace the restored local editor map.")

	var store := MapFileStoreScript.new()
	var wrong_world_in_local_path := store.local_map_path_for_name(WORLD_SUITE_CROSS_LOCAL_FILENAME)
	if ResourceSaver.save(world_map_data, wrong_world_in_local_path) != OK:
		return ctx.fail("World editor suite could not write cross-type local fixture.")
	if store.load_local_map(WORLD_SUITE_CROSS_LOCAL_FILENAME) != null:
		return ctx.fail("Local load should reject WorldMapData resources even from the local directory.")
	var wrong_local_in_world_path := store.world_map_path_for_name(WORLD_SUITE_CROSS_WORLD_FILENAME)
	if ResourceSaver.save(original_map_data, wrong_local_in_world_path) != OK:
		return ctx.fail("World editor suite could not write cross-type world fixture.")
	if store.load_world_map(WORLD_SUITE_CROSS_WORLD_FILENAME) != null:
		return ctx.fail("World load should reject MapData resources even from the world directory.")

	var loaded_world_map := editor_mode_controller.load_world_map(WORLD_SUITE_FILENAME)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if (
		loaded_world_map == null
		or editor_mode_controller.get_mode() != EditorModeControllerScript.MODE_WORLD_EDITOR
		or map_loader.get_world_map_data() != loaded_world_map
	):
		return ctx.fail("Loading a saved world map did not route into World editor mode.")
	if loaded_world_map.geology == null or loaded_world_map.geology.size_m.x < 250000.0 or loaded_world_map.geology.size_m.y < 250000.0:
		return ctx.fail("Loading a saved world map through the dev menu shrank it to local editor dimensions.")

	editor_mode_controller.enter_game_mode()
	await ctx.tree.process_frame
	editor_mode_controller.enter_editor_mode()
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.get_local_map_data() != original_map_data or map_loader.is_world_map_loaded():
		return ctx.fail("World -> Game -> Editor did not restore the cached local editor map.")

	return true

func _button_visible(root: Node, button_path: NodePath) -> bool:
	var button := root.get_node_or_null(button_path) as Button
	return button != null and button.visible

func _resource_has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for property in resource.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true

	return false

func _cleanup_saved_map(requested_name: String) -> void:
	var store := MapFileStoreScript.new()
	for res_path in [
		store.local_map_path_for_name(requested_name),
		store.world_map_path_for_name(requested_name),
	]:
		var path := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
