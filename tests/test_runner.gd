extends SceneTree

const EventBusScript := preload("res://src/core/event_bus.gd")
const HexDataScript := preload("res://src/grid/hex_data.gd")
const HexGridManagerScript := preload("res://src/grid/hex_grid_manager.gd")
const HexViewScript := preload("res://src/grid/hex_view.gd")
const CameraRigScript := preload("res://src/camera/camera_rig.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const InteractionLogPanelScript := preload("res://src/ui/interaction_log_panel.gd")
const GridMovementAnimatorScript := preload("res://src/movement/grid_movement_animator.gd")
const HexPathfinderScript := preload("res://src/movement/hex_pathfinder.gd")
const MovementControllerScript := preload("res://src/movement/movement_controller.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const WallCellResolverScript := preload("res://src/walls/wall_cell_resolver.gd")
const WallLayoutViewScript := preload("res://src/walls/wall_layout_view.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WallVisualResolverScript := preload("res://src/walls/wall_visual_resolver.gd")

var _move_requested_count: int = 0
var _move_requested_actor: Node
var _move_requested_destination: Resource
var _movement_started_count: int = 0
var _movement_completed_count: int = 0
var _movement_failed_count: int = 0

func _init() -> void:
	if not _run_smoke_checks():
		quit(1)
		return

	print("Smoke Test Passed: Compilation successful")
	quit()

func _run_smoke_checks() -> bool:
	var event_bus := EventBusScript.new()
	for signal_name in [
		"hover_target_changed",
		"interaction_menu_requested",
		"interaction_action_requested",
		"interaction_pointer_capture_changed",
		"interaction_ui_cancel_requested",
		"interaction_targeting_started",
		"interaction_targeting_cancelled",
		"move_requested",
		"movement_started",
		"movement_step_reached",
		"movement_completed",
		"movement_failed",
		"examined_output",
	]:
		if not event_bus.has_signal(signal_name):
			return _fail("EventBus is missing %s signal." % signal_name)
	event_bus.free()

	if ProjectSettings.get_setting("autoload/EventBus", "") != "*res://src/core/event_bus.gd":
		return _fail("EventBus autoload is not configured.")

	var root_event_bus := _ensure_root_event_bus()

	if not InputMap.has_action("toggle_interaction_log"):
		return _fail("toggle_interaction_log input action is missing.")

	var hexes: Dictionary = HexGridManagerScript.generate_hex_data(2, 3)
	if hexes.size() != 6:
		return _fail("Expected 6 generated hexes, got %d." % hexes.size())

	var origin_key := Vector3i(0, 0, 0)
	if not hexes.has(origin_key):
		return _fail("Generated grid is missing the origin hex.")

	var origin: HexDataScript = hexes[origin_key]
	if not origin.is_valid_cube():
		return _fail("Origin hex violates q + r + s == 0.")

	var center: Vector3 = HexViewScript.axial_to_world(0, 0)
	var east: Vector3 = HexViewScript.axial_to_world(1, 0)
	if not is_equal_approx(center.distance_to(east), HexViewScript.HEX_SIDE_TO_SIDE_M):
		return _fail("Adjacent hex center spacing is not 1 meter.")

	var stored_grid := HexGridManagerScript.new()
	stored_grid.width = 2
	stored_grid.length = 1
	stored_grid.generate_on_ready = false
	get_root().add_child(stored_grid)
	stored_grid.build_grid()
	if stored_grid.get_hexes().size() != 2:
		return _fail("HexGridManager did not retain generated hex data.")
	stored_grid.free()

	var path_hexes: Dictionary = HexGridManagerScript.generate_hex_data(3, 1)
	var path := HexPathfinderScript.find_path(path_hexes, Vector3i(0, 0, 0), Vector3i(2, 0, -2))
	if path.size() != 3:
		return _fail("HexPathfinder did not return the expected 3-hex path.")
	if (path[0] as HexDataScript).key() != Vector3i(0, 0, 0):
		return _fail("HexPathfinder path does not start at the source hex.")
	if (path[2] as HexDataScript).key() != Vector3i(2, 0, -2):
		return _fail("HexPathfinder path does not end at the destination hex.")
	(path_hexes[Vector3i(1, 0, -1)] as HexDataScript).is_walkable = false
	if not HexPathfinderScript.find_path(path_hexes, Vector3i(0, 0, 0), Vector3i(2, 0, -2)).is_empty():
		return _fail("HexPathfinder should return no path through blocked hexes.")

	var wall_segment := WallSegmentDataScript.new(
		0,
		1,
		2,
		1,
		WallSegmentDataScript.SPAN_CORNER_TO_CORNER,
		2.2,
		0.18,
		Color(0.35, 0.34, 0.32, 1.0)
	)
	if wall_segment.start_key() != Vector3i(0, 1, -1) or wall_segment.end_key() != Vector3i(2, 1, -3):
		return _fail("WallSegmentData did not derive valid cube keys.")
	if not wall_segment.is_valid_span_mode():
		return _fail("WallSegmentData rejected a valid span mode.")

	var blocked_wall_keys := WallCellResolverScript.blocked_keys_for_segment(wall_segment)
	if blocked_wall_keys.size() != 3:
		return _fail("WallCellResolver did not return an inclusive 3-cell wall line.")
	if blocked_wall_keys[0] != Vector3i(0, 1, -1) or blocked_wall_keys[2] != Vector3i(2, 1, -3):
		return _fail("WallCellResolver returned the wrong segment endpoints.")

	var side_segment := WallSegmentDataScript.new(
		0,
		1,
		2,
		1,
		WallSegmentDataScript.SPAN_SIDE_TO_SIDE,
		2.2,
		0.18,
		Color(0.35, 0.34, 0.32, 1.0)
	)
	var corner_endpoints := WallVisualResolverScript.visual_endpoints(wall_segment)
	var side_endpoints := WallVisualResolverScript.visual_endpoints(side_segment)
	if corner_endpoints.size() != 2 or side_endpoints.size() != 2:
		return _fail("WallVisualResolver did not return visual segment endpoints.")
	if corner_endpoints[0].distance_to(side_endpoints[0]) <= 0.001:
		return _fail("WallVisualResolver produced identical corner and side anchors.")

	var wall_path_hexes: Dictionary = HexGridManagerScript.generate_hex_data(3, 1)
	for key in WallCellResolverScript.blocked_keys_for_segment(WallSegmentDataScript.new(1, 0, 1, 0)):
		(wall_path_hexes[key] as HexDataScript).is_walkable = false
	if not HexPathfinderScript.find_path(wall_path_hexes, Vector3i(0, 0, 0), Vector3i(2, 0, -2)).is_empty():
		return _fail("HexPathfinder should not path through wall-blocked cells.")

	var wall_parent := Node3D.new()
	get_root().add_child(wall_parent)
	var wall_grid := HexGridManagerScript.new()
	wall_grid.name = "HexGridManager"
	wall_grid.width = 4
	wall_grid.length = 3
	wall_grid.generate_on_ready = false
	wall_parent.add_child(wall_grid)
	wall_grid.build_grid()

	var wall_layout := WallLayoutViewScript.new()
	wall_layout.wall_segments.append(wall_segment)
	wall_parent.add_child(wall_layout)
	var layout_blocked_keys := wall_layout.apply_layout()
	if not layout_blocked_keys.has(Vector3i(1, 1, -2)):
		return _fail("WallLayoutView did not apply the expected blocked middle cell.")
	var blocked_hex_data := wall_grid.get_hexes()[Vector3i(1, 1, -2)] as HexDataScript
	if blocked_hex_data.is_walkable or blocked_hex_data.terrain_id != &"wall":
		return _fail("WallLayoutView did not mark wall cells unwalkable.")
	var wall_visual_root := wall_layout.get_node_or_null("WallVisuals")
	if wall_visual_root == null or wall_visual_root.get_child_count() != 1:
		return _fail("WallLayoutView did not create wall visuals.")
	var wall_mesh_instance := wall_visual_root.get_child(0) as MeshInstance3D
	var wall_box_mesh := wall_mesh_instance.mesh as BoxMesh
	if wall_box_mesh == null:
		return _fail("WallLayoutView visual is not a BoxMesh.")
	if not is_equal_approx(wall_box_mesh.size.y, wall_segment.height_m):
		return _fail("WallLayoutView visual does not use the configured wall height.")
	if not is_equal_approx(wall_box_mesh.size.x, wall_segment.thickness_m):
		return _fail("WallLayoutView visual does not use the configured wall thickness.")
	wall_parent.free()

	var hex_view := HexViewScript.new()
	hex_view.hex_data = HexDataScript.new(0, 0, 0)
	get_root().add_child(hex_view)
	var interaction_target := hex_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if interaction_target == null:
		return _fail("HexView did not create an InteractionTarget child.")
	if not interaction_target.is_in_group(InteractionTargetScript.GROUP_NAME):
		return _fail("InteractionTarget did not join the expected group.")
	if interaction_target.target_domain != &"hex":
		return _fail("HexView InteractionTarget has the wrong domain.")
	if not (interaction_target.target_data is HexDataScript):
		return _fail("HexView InteractionTarget does not carry HexData.")
	var collision_shape := interaction_target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return _fail("InteractionTarget did not create a collision shape.")
	if not is_equal_approx(hex_view.rotation.y, HexViewScript.HEX_MESH_Y_ROTATION_RADIANS):
		return _fail("HexView mesh rotation is not aligned to flat-top axial spacing.")
	var hex_highlighter := interaction_target.get_node_or_null("HoverHighlighter") as HoverHighlighterScript
	if hex_highlighter == null:
		return _fail("HexView did not create a HoverHighlighter.")
	if _has_action(InteractionActionResolverScript.get_actions(interaction_target), InteractionActionResolverScript.ACTION_EXAMINE):
		return _fail("Hex interaction target should not expose Examine yet.")
	if _has_action(InteractionActionResolverScript.get_actions(interaction_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("Hex interaction target should not expose Move.")
	if not MoveTargetResolverScript.can_select_destination(interaction_target):
		return _fail("MoveTargetResolver did not accept a walkable hex destination.")
	hex_view.free()

	var blocked_hex_view := HexViewScript.new()
	blocked_hex_view.hex_data = HexDataScript.new(0, 1, -1, &"grass", false)
	get_root().add_child(blocked_hex_view)
	var blocked_hex_target := blocked_hex_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if MoveTargetResolverScript.can_select_destination(blocked_hex_target):
		return _fail("MoveTargetResolver accepted a non-walkable hex destination.")
	blocked_hex_view.free()

	var highlight_material: StandardMaterial3D = HoverHighlighterScript.build_highlight_material()
	if highlight_material.albedo_color.a >= 1.0:
		return _fail("HoverHighlighter did not build a transparent material.")
	highlight_material = null

	var mesh := MeshInstance3D.new()
	mesh.mesh = CylinderMesh.new()
	mesh.material_override = StandardMaterial3D.new()
	var highlighter := HoverHighlighterScript.new()
	highlighter.root_path = ^".."
	mesh.add_child(highlighter)
	get_root().add_child(mesh)
	highlighter.set_highlighted(true)
	var shell := mesh.get_node_or_null("HoverShell") as MeshInstance3D
	if shell == null:
		return _fail("HoverHighlighter did not create a shell mesh.")
	var shell_material := shell.material_override as StandardMaterial3D
	if shell_material == null or shell_material.albedo_color.a >= 1.0:
		return _fail("HoverHighlighter shell is not using a transparent material.")
	if shell.get_child_count() != 0:
		return _fail("HoverHighlighter shell should not create collision or helper children.")
	highlighter.clear_highlight()
	if mesh.get_node_or_null("HoverShell") != null:
		return _fail("HoverHighlighter did not remove shell meshes after clearing.")
	mesh.free()

	var interaction_controller := InteractionControllerScript.new()
	get_root().add_child(interaction_controller)
	interaction_controller._ready()
	if not interaction_controller.has_method("clear_hover"):
		return _fail("InteractionController is missing clear_hover().")
	if not interaction_controller.has_method("is_interaction_pointer_captured"):
		return _fail("InteractionController is missing pointer capture state access.")
	if not interaction_controller.has_method("is_targeting_interaction"):
		return _fail("InteractionController is missing targeting state access.")
	interaction_controller._handle_interaction_pointer_capture_changed(true)
	if not interaction_controller.is_interaction_pointer_captured():
		return _fail("InteractionController did not pause for interaction pointer capture.")
	interaction_controller._handle_interaction_pointer_capture_changed(false)
	if interaction_controller.is_interaction_pointer_captured():
		return _fail("InteractionController did not resume after pointer capture release.")
	interaction_controller.free()

	var pc_size := Vector3(0.5, 1.83, 0.5)
	var pc_data := WorldObjectDataScript.new(
		&"pc_001",
		&"player_character",
		0,
		0,
		0,
		pc_size,
		Color(0.1, 0.25, 1.0, 1.0),
		true
	)
	if not pc_data.is_valid_cube():
		return _fail("WorldObjectData did not preserve q + r + s == 0.")
	if pc_data.size_m != pc_size:
		return _fail("Player character dimensions are incorrect.")

	var pc_view := BlockoutObjectViewScript.new()
	pc_view.object_data = pc_data
	get_root().add_child(pc_view)
	if not is_equal_approx(pc_view.position.x, 0.0) or not is_equal_approx(pc_view.position.z, 0.0):
		return _fail("Player character did not land on hex origin x/z.")

	var pc_body := pc_view.get_node_or_null("Body") as MeshInstance3D
	if pc_body == null:
		return _fail("BlockoutObjectView did not create Body mesh.")
	var pc_body_offset := Vector3(0.0, pc_size.y * 0.5, 0.0)
	if pc_body.position != pc_body_offset:
		return _fail("Player character mesh is not centered above its feet.")

	var pc_mesh := pc_body.mesh as BoxMesh
	if pc_mesh == null or pc_mesh.size != pc_size:
		return _fail("Player character mesh dimensions are incorrect.")
	if not is_equal_approx(pc_body.position.y - (pc_size.y * 0.5), 0.0):
		return _fail("Player character feet are not level with y=0.")

	var pc_interaction_target := pc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if pc_interaction_target == null:
		return _fail("Player character did not create an InteractionTarget.")
	if pc_interaction_target.target_domain != &"world_object":
		return _fail("Player character InteractionTarget has the wrong domain.")
	if not (pc_interaction_target.target_data is WorldObjectDataScript):
		return _fail("Player character InteractionTarget does not carry WorldObjectData.")
	if not _has_action(InteractionActionResolverScript.get_actions(pc_interaction_target), InteractionActionResolverScript.ACTION_EXAMINE):
		return _fail("World object interaction target should expose Examine.")
	if not _has_action(InteractionActionResolverScript.get_actions(pc_interaction_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("Player character interaction target should expose Move.")
	if not MoveTargetResolverScript.can_start_move(pc_interaction_target):
		return _fail("MoveTargetResolver did not accept the player character as a move source.")
	var examine_output := InteractionActionResolverScript.build_examine_output(pc_interaction_target)
	if examine_output.get("domain") != &"world_object":
		return _fail("Examine output has the wrong domain.")
	if examine_output.get("object_kind") != &"player_character":
		return _fail("Examine output has the wrong object kind.")
	if examine_output.get("object_id") != &"pc_001":
		return _fail("Examine output has the wrong object id.")
	var pc_collision_shape := pc_interaction_target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if pc_collision_shape == null or pc_collision_shape.position != pc_body_offset:
		return _fail("Player character collision shape is missing or not centered above its feet.")
	var pc_shape := pc_collision_shape.shape as BoxShape3D
	if pc_shape == null or pc_shape.size != pc_size:
		return _fail("Player character collision dimensions are incorrect.")
	if pc_interaction_target.get_node_or_null("HoverHighlighter") == null:
		return _fail("Player character did not create a HoverHighlighter.")

	var move_dest_view := HexViewScript.new()
	move_dest_view.hex_data = HexDataScript.new(1, 0, -1)
	get_root().add_child(move_dest_view)
	var move_dest_target := move_dest_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if not MoveTargetResolverScript.can_move(pc_interaction_target, move_dest_target):
		return _fail("MoveTargetResolver did not accept PC-to-walkable-hex movement.")
	if MoveTargetResolverScript.can_move(pc_interaction_target, pc_interaction_target):
		return _fail("MoveTargetResolver accepted a world-object destination.")

	_move_requested_count = 0
	_move_requested_actor = null
	_move_requested_destination = null
	var move_requested_callable := Callable(self, "_record_move_requested")
	if root_event_bus != null:
		root_event_bus.connect(&"move_requested", move_requested_callable)

	var targeting_controller := InteractionControllerScript.new()
	get_root().add_child(targeting_controller)
	targeting_controller._ready()
	var targeting_controller_has_event_bus := targeting_controller._get_event_bus() != null
	if not targeting_controller.start_targeting(pc_interaction_target, InteractionActionResolverScript.ACTION_MOVE):
		return _fail("InteractionController did not enter move targeting for a PC source.")
	if not targeting_controller.is_targeting_interaction():
		return _fail("InteractionController did not report active move targeting.")
	if targeting_controller.try_confirm_targeting_target(pc_interaction_target):
		return _fail("InteractionController accepted a world object as a move destination.")
	if _move_requested_count != 0:
		return _fail("InteractionController emitted move_requested for an invalid destination.")
	var right_click := InputEventMouseButton.new()
	right_click.pressed = true
	right_click.button_index = MOUSE_BUTTON_RIGHT
	targeting_controller._input(right_click)
	if targeting_controller.is_targeting_interaction():
		return _fail("InteractionController did not cancel move targeting on RMB.")
	if not targeting_controller.start_targeting(pc_interaction_target, InteractionActionResolverScript.ACTION_MOVE):
		return _fail("InteractionController did not re-enter move targeting for a PC source.")
	if not targeting_controller.try_confirm_targeting_target(move_dest_target):
		return _fail("InteractionController did not confirm a walkable hex move destination.")
	if targeting_controller.is_targeting_interaction():
		return _fail("InteractionController did not exit targeting after move confirmation.")
	if targeting_controller_has_event_bus:
		if _move_requested_count != 1:
			return _fail("InteractionController did not emit exactly one move_requested event.")
		if _move_requested_actor != pc_view or _move_requested_destination != move_dest_view.hex_data:
			return _fail("InteractionController emitted move_requested with the wrong actor or destination.")
	if root_event_bus != null:
		root_event_bus.disconnect(&"move_requested", move_requested_callable)
	targeting_controller.free()
	move_dest_view.free()

	var animator_path: Array = [HexDataScript.new(0, 0, 0), HexDataScript.new(1, 0, -1)]
	if not pc_view.move_along_hex_path(animator_path, 999.0):
		return _fail("BlockoutObjectView did not accept a hex movement path.")
	var pc_animator := pc_view.get_node_or_null("GridMovementAnimator") as GridMovementAnimatorScript
	if pc_animator == null:
		return _fail("BlockoutObjectView did not create a GridMovementAnimator.")
	pc_animator._process(1.0)
	if pc_data.key() != Vector3i(1, 0, -1):
		return _fail("GridMovementAnimator did not update WorldObjectData at the reached hex.")
	if pc_view.position.distance_to(HexViewScript.axial_to_world(1, 0, 0.0)) > 0.001:
		return _fail("GridMovementAnimator did not snap the actor to the destination hex.")
	pc_view.free()

	var movement_parent := Node3D.new()
	get_root().add_child(movement_parent)
	var movement_grid := HexGridManagerScript.new()
	movement_grid.name = "HexGridManager"
	movement_grid.width = 3
	movement_grid.length = 1
	movement_grid.generate_on_ready = false
	movement_parent.add_child(movement_grid)
	movement_grid.build_grid()

	var moving_data := WorldObjectDataScript.new(
		&"pc_move_test",
		&"player_character",
		0,
		0,
		0,
		pc_size,
		Color(0.1, 0.25, 1.0, 1.0),
		true
	)
	var moving_actor := BlockoutObjectViewScript.new()
	moving_actor.object_data = moving_data
	movement_parent.add_child(moving_actor)

	var movement_controller := MovementControllerScript.new()
	movement_controller.name = "MovementController"
	movement_controller.movement_speed_mps = 999.0
	movement_parent.add_child(movement_controller)
	movement_controller._ready()
	var movement_controller_has_event_bus := movement_controller._get_event_bus() != null

	_movement_started_count = 0
	_movement_completed_count = 0
	_movement_failed_count = 0
	var movement_started_callable := Callable(self, "_record_movement_started")
	var movement_completed_callable := Callable(self, "_record_movement_completed")
	var movement_failed_callable := Callable(self, "_record_movement_failed")
	if root_event_bus != null:
		root_event_bus.connect(&"movement_started", movement_started_callable)
		root_event_bus.connect(&"movement_completed", movement_completed_callable)
		root_event_bus.connect(&"movement_failed", movement_failed_callable)

	var movement_destination := movement_grid.get_hexes()[Vector3i(2, 0, -2)] as HexDataScript
	if not movement_controller.request_move(moving_actor, moving_data, movement_destination):
		return _fail("MovementController rejected a valid movement request.")
	if movement_controller_has_event_bus and _movement_started_count != 1:
		return _fail("MovementController did not emit movement_started.")
	if not movement_controller.is_actor_busy(moving_actor):
		return _fail("MovementController did not mark the moving actor busy.")
	var moving_animator := moving_actor.get_node_or_null("GridMovementAnimator") as GridMovementAnimatorScript
	moving_animator._process(1.0)
	if not movement_controller_has_event_bus:
		movement_controller._handle_movement_completed(moving_actor, movement_destination)
	if movement_controller_has_event_bus and _movement_completed_count != 1:
		return _fail("GridMovementAnimator did not emit movement_completed.")
	if movement_controller.is_actor_busy(moving_actor):
		return _fail("MovementController did not clear actor busy state after completion.")
	if moving_data.key() != Vector3i(2, 0, -2):
		return _fail("MovementController movement did not update actor data to destination.")

	moving_data.set_cube_coords(0, 0, 0)
	moving_actor.position = BlockoutObjectViewScript.grid_to_world(moving_data)
	(movement_grid.get_hexes()[Vector3i(1, 0, -1)] as HexDataScript).is_walkable = false
	if movement_controller.request_move(moving_actor, moving_data, movement_destination):
		return _fail("MovementController accepted movement with no walkable path.")
	if movement_controller_has_event_bus and _movement_failed_count < 1:
		return _fail("MovementController did not emit movement_failed for no path.")
	if root_event_bus != null:
		root_event_bus.disconnect(&"movement_started", movement_started_callable)
		root_event_bus.disconnect(&"movement_completed", movement_completed_callable)
		root_event_bus.disconnect(&"movement_failed", movement_failed_callable)
	movement_parent.free()

	var interaction_menu := InteractionMenuScript.new()
	interaction_menu.free()
	var interaction_log_panel := InteractionLogPanelScript.new()
	interaction_log_panel.free()

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("Main scene did not load.")
	var main := main_scene.instantiate()
	get_root().add_child(main)
	var main_interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	if main_interaction_controller == null:
		return _fail("Main scene is missing InteractionController.")
	main_interaction_controller._ready()
	if main.get_node_or_null("MovementController") == null:
		return _fail("Main scene is missing MovementController.")
	var main_wall_layout := main.get_node_or_null("WallLayout") as WallLayoutViewScript
	if main_wall_layout == null:
		return _fail("Main scene is missing WallLayout.")
	if main_wall_layout.wall_segments.size() != 2:
		return _fail("Main scene wall layout should contain two sample wall segments.")
	if main_wall_layout.wall_segments[0].span_mode != WallSegmentDataScript.SPAN_CORNER_TO_CORNER:
		return _fail("Main scene first wall segment should be corner-to-corner.")
	if main_wall_layout.wall_segments[1].span_mode != WallSegmentDataScript.SPAN_SIDE_TO_SIDE:
		return _fail("Main scene second wall segment should be side-to-side.")
	var interaction_ui := main.get_node_or_null("InteractionUI") as CanvasLayer
	if interaction_ui == null:
		return _fail("Main scene is missing InteractionUI CanvasLayer.")
	var main_interaction_menu := interaction_ui.get_node_or_null("InteractionMenu") as InteractionMenuScript
	if main_interaction_menu == null:
		return _fail("Main scene is missing InteractionMenu.")
	main_interaction_menu._ready()
	if interaction_ui.get_node_or_null("InteractionLogPanel") == null:
		return _fail("Main scene is missing InteractionLogPanel.")
	if main.get_node_or_null("SunLight") == null:
		return _fail("Main scene is missing SunLight.")
	if main.get_node_or_null("PlayerCharacter") == null:
		return _fail("Main scene is missing PlayerCharacter.")
	var npc := main.get_node_or_null("NPC") as BlockoutObjectViewScript
	if npc == null:
		return _fail("Main scene is missing NPC.")
	if npc.object_data == null or npc.object_data.object_kind != &"non_player_character":
		return _fail("NPC object data is missing or has the wrong kind.")
	if npc.object_data.key() != Vector3i(1, 0, -1):
		return _fail("NPC is not assigned to the adjacent hex.")
	if npc.object_data.color != Color(0.45, 0.45, 0.45, 1.0):
		return _fail("NPC is not using the expected gray color.")
	var npc_interaction_target := npc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if npc_interaction_target == null:
		return _fail("NPC did not create an InteractionTarget.")
	if npc_interaction_target.target_domain != &"world_object":
		return _fail("NPC InteractionTarget has the wrong domain.")
	if not (npc_interaction_target.target_data is WorldObjectDataScript):
		return _fail("NPC InteractionTarget does not carry WorldObjectData.")
	if _has_action(InteractionActionResolverScript.get_actions(npc_interaction_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("NPC interaction target should not expose Move.")
	if MoveTargetResolverScript.can_start_move(npc_interaction_target):
		return _fail("MoveTargetResolver accepted an NPC as a move source.")
	var main_ui_has_event_bus := (
		root_event_bus != null
		and main_interaction_menu._get_event_bus() != null
		and main_interaction_controller._get_event_bus() != null
	)
	if main_ui_has_event_bus:
		root_event_bus.emit_signal(&"interaction_menu_requested", npc_interaction_target, Vector2.ZERO)
		if not main_interaction_menu.visible:
			return _fail("InteractionMenu did not open from a menu request.")
		if not main_interaction_controller.is_interaction_pointer_captured():
			return _fail("InteractionController did not capture pointer when the menu opened.")
		root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
		if main_interaction_menu.visible:
			return _fail("InteractionMenu did not close from a cancel request.")
		if main_interaction_controller.is_interaction_pointer_captured():
			return _fail("InteractionController did not release pointer capture after cancel.")
	else:
		main_interaction_menu._on_interaction_menu_requested(npc_interaction_target, Vector2.ZERO)
		if not main_interaction_menu.visible:
			return _fail("InteractionMenu did not open from a direct menu request.")
		main_interaction_menu._on_interaction_ui_cancel_requested()
		if main_interaction_menu.visible:
			return _fail("InteractionMenu did not close from a direct cancel request.")
	main.free()

	var camera_distance: float = CameraRigScript.camera_distance_for_height(7.0, deg_to_rad(-55.0))
	if not camera_distance > 7.0:
		return _fail("Camera rig distance should exceed its vertical height at an angled pitch.")

	return true

func _has_action(actions: Array[Dictionary], action_id: StringName) -> bool:
	for action in actions:
		if action.get("id") == action_id:
			return true

	return false

func _record_move_requested(actor: Node, _actor_data: Resource, destination_data: Resource) -> void:
	_move_requested_count += 1
	_move_requested_actor = actor
	_move_requested_destination = destination_data

func _record_movement_started(_actor: Node, _path: Array) -> void:
	_movement_started_count += 1

func _record_movement_completed(_actor: Node, _destination_data: Resource) -> void:
	_movement_completed_count += 1

func _record_movement_failed(_actor: Node, _destination_data: Resource, _reason: StringName) -> void:
	_movement_failed_count += 1

func _ensure_root_event_bus() -> Node:
	var root_event_bus := get_root().get_node_or_null("EventBus")
	if root_event_bus != null:
		return root_event_bus

	root_event_bus = EventBusScript.new()
	root_event_bus.name = "EventBus"
	get_root().add_child(root_event_bus)
	return root_event_bus

func _fail(message: String) -> bool:
	push_error(message)
	return false
