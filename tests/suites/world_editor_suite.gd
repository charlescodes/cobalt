extends RefCounted

const CameraRigScript := preload("res://src/camera/camera_rig.gd")
const DevMenuScript := preload("res://src/editor/dev_menu.gd")
const EditorModeControllerScript := preload("res://src/editor/editor_mode_controller.gd")
const EditorPanelScript := preload("res://src/editor/editor_panel.gd")
const EditorSelectionControllerScript := preload("res://src/editor/editor_selection_controller.gd")
const GroundDataScript := preload("res://src/environment/ground_data.gd")
const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")
const WorldGeologyGeneratorScript := preload("res://src/generation/world_geology_generator.gd")

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
		or editor_mode_controller == null
		or editor_selection_controller == null
		or camera == null
		or camera_rig == null
		or dev_menu == null
		or editor_panel == null
	):
		return ctx.fail("World editor suite main scene is missing required nodes.")

	var original_map_data := map_loader.map_data
	if dev_menu.get_node_or_null("MenuLayout/ModeRow/WorldEditorModeButton") == null:
		return ctx.fail("DevMenu is missing the World mode button.")

	editor_mode_controller.enter_world_editor_mode()
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if editor_mode_controller.get_mode() != EditorModeControllerScript.MODE_WORLD_EDITOR:
		return ctx.fail("EditorModeController did not enter world editor mode.")
	if map_loader.map_data == original_map_data or map_loader.map_data.world_geology == null:
		return ctx.fail("World editor mode did not replace the local map with a world geology map.")
	var world_ground := map_loader.map_data.grounds[0] as GroundDataScript
	if (
		world_ground == null
		or not is_equal_approx(world_ground.size_m.x, 500000.0)
		or not is_equal_approx(world_ground.size_m.y, 0.1)
		or not is_equal_approx(world_ground.size_m.z, 500000.0)
	):
		return ctx.fail("World editor mode did not create the expected 500km macro ground: %s" % str(world_ground.size_m if world_ground != null else Vector3.ZERO))
	var generated_map := navigation_region.get_node_or_null("GeneratedMap") as Node3D
	var world_layer := generated_map.get_node_or_null(String(MapBuilderScript.WORLD_MAP_3D_LAYER_NAME)) as MeshInstance3D
	if world_layer == null or world_layer.mesh == null:
		return ctx.fail("World editor mode did not create a visible 3D world map layer.")
	if world_layer.has_meta(MapBuilderScript.EDITOR_KIND_META) or world_layer.get_node_or_null("CollisionShape3D") != null:
		return ctx.fail("World map 3D layer should render only, without editor selection metadata or collision.")
	if camera.position.z <= 100000.0:
		return ctx.fail("Camera did not switch to a macro-scale world height.")
	if editor_selection_controller.get_active_tool() != EditorSelectionControllerScript.TOOL_SELECT_INSPECT:
		return ctx.fail("World editor input should start on Select/Inspect.")

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
	world_ground = map_loader.map_data.grounds[0] as GroundDataScript
	if world_ground.size_m.x != 750000.0 or world_ground.size_m.z != 800000.0:
		return ctx.fail("World Ground sliders did not resize the macro ground.")
	if map_loader.map_data.world_geology.size_m != Vector2(750000.0, 800000.0):
		return ctx.fail("World Ground resize did not keep geology size in sync.")
	generated_map = navigation_region.get_node_or_null("GeneratedMap") as Node3D
	if generated_map.get_node_or_null(String(MapBuilderScript.WORLD_MAP_3D_LAYER_NAME)) == null:
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
	var geology := map_loader.map_data.world_geology as WorldGeologyDataScript
	if (
		geology.seed_text != "rain_shadow_suite"
		or not geology.coast_enabled
		or geology.coast_edge != WorldGeologyDataScript.COAST_EAST
		or not is_equal_approx(geology.wind_direction_degrees, 90.0)
	):
		return ctx.fail("Geology panel changes did not update WorldGeologyData.")

	editor_mode_controller.enter_editor_mode()
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if map_loader.map_data != original_map_data or map_loader.map_data.world_geology != null:
		return ctx.fail("Returning to local Editor mode did not restore the in-memory local map.")
	if camera.position.z > 100.0:
		return ctx.fail("Camera did not return to local editor scale.")
	if _button_visible(editor_panel, ^"EditorToolDockLayout/ToolButtonRow/GeologyToolButton"):
		return ctx.fail("Local editor mode should hide the Geology tool.")
	if not _button_visible(editor_panel, ^"EditorToolDockLayout/ToolButtonRow/NpcBrushToolButton"):
		return ctx.fail("Local editor mode did not restore local-map tools.")

	return true

func _button_visible(root: Node, button_path: NodePath) -> bool:
	var button := root.get_node_or_null(button_path) as Button
	return button != null and button.visible
