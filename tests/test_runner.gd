extends SceneTree

const EventBusScript := preload("res://src/core/event_bus.gd")
const CameraRigScript := preload("res://src/camera/camera_rig.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const InteractionLogPanelScript := preload("res://src/ui/interaction_log_panel.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MovementControllerScript := preload("res://src/movement/movement_controller.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const WallLayoutViewScript := preload("res://src/walls/wall_layout_view.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WallVisualResolverScript := preload("res://src/walls/wall_visual_resolver.gd")

var _move_requested_count: int = 0
var _move_requested_actor: Node
var _move_requested_actor_data: Resource
var _move_requested_destination: Resource
var _hover_changed_count: int = 0
var _hover_changed_target: Node
var _examined_count: int = 0
var _examined_target_domain: StringName = &""
var _examined_target_data: Resource
var _examined_output: Dictionary = {}
var _movement_started_count: int = 0
var _movement_started_path: PackedVector3Array
var _movement_completed_count: int = 0
var _movement_failed_count: int = 0
var _movement_failed_reason: StringName = &""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await physics_frame
	if not await _run_smoke_checks():
		quit(1)
		return

	print("Smoke Test Passed: Compilation successful")
	quit()

func _run_smoke_checks() -> bool:
	var root_event_bus := _ensure_root_event_bus()
	if not _check_project_basics():
		return false
	if not _check_world_objects_and_interaction():
		return false
	if not await _check_native_navigation_resolver():
		return false
	if not await _check_targeting_and_controller(root_event_bus):
		return false
	if not _check_walls():
		return false
	if not _check_hover_and_ui(root_event_bus):
		return false
	if not _check_main_scene(root_event_bus):
		return false
	if not await _check_main_scene_interaction_raycast(root_event_bus):
		return false

	var camera_distance: float = CameraRigScript.camera_distance_for_height(7.0, deg_to_rad(-55.0))
	if not camera_distance > 7.0:
		return _fail("Camera rig distance should exceed its vertical height at an angled pitch.")

	return true

func _check_project_basics() -> bool:
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
	if not InputMap.has_action("toggle_interaction_log"):
		return _fail("toggle_interaction_log input action is missing.")
	if ResourceLoader.exists("res://src/movement/hex_pathfinder.gd"):
		return _fail("HexPathfinder script should be deleted.")
	if ResourceLoader.exists("res://src/walls/wall_cell_resolver.gd"):
		return _fail("WallCellResolver script should be deleted.")
	if ResourceLoader.exists("res://src/movement/grid_movement_animator.gd"):
		return _fail("GridMovementAnimator script should be deleted.")

	return true

func _check_world_objects_and_interaction() -> bool:
	var pc_position := Vector3(2.0, 0.0, 3.0)
	var pc_size := Vector3(0.5, 1.83, 0.5)
	var pc_data := WorldObjectDataScript.new(
		&"pc_001",
		&"player_character",
		pc_position,
		pc_size,
		Color(0.1, 0.25, 1.0, 1.0),
		true
	)
	if pc_data.position != pc_position:
		return _fail("WorldObjectData did not preserve the Vector3 position.")
	if pc_data.size_m != pc_size:
		return _fail("Player character dimensions are incorrect.")

	var pc_view := BlockoutObjectViewScript.new()
	pc_view.object_data = pc_data
	get_root().add_child(pc_view)
	if pc_view.position != pc_position:
		return _fail("BlockoutObjectView did not use WorldObjectData.position.")
	if pc_view.get_node_or_null("GridMovementAnimator") != null:
		return _fail("BlockoutObjectView should not create grid movement components.")
	var pc_agent := pc_view.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if pc_agent == null:
		return _fail("BlockoutObjectView did not create a NavigationAgent3D.")
	if pc_view.get_navigation_agent() != pc_agent:
		return _fail("BlockoutObjectView did not expose its NavigationAgent3D helper.")
	if not is_equal_approx(pc_agent.target_desired_distance, 0.1):
		return _fail("NavigationAgent3D target distance is not configured.")

	var pc_body := pc_view.get_node_or_null("Body") as MeshInstance3D
	if pc_body == null:
		return _fail("BlockoutObjectView did not create Body mesh.")
	var pc_body_offset := Vector3(0.0, pc_size.y * 0.5, 0.0)
	if pc_body.position != pc_body_offset:
		return _fail("Player character mesh is not centered above its feet.")

	var pc_mesh := pc_body.mesh as BoxMesh
	if pc_mesh == null or pc_mesh.size != pc_size:
		return _fail("Player character mesh dimensions are incorrect.")

	var pc_target := pc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if pc_target == null:
		return _fail("Player character did not create an InteractionTarget.")
	if not pc_target.is_in_group(InteractionTargetScript.GROUP_NAME):
		return _fail("InteractionTarget did not join the expected group.")
	if pc_target.target_domain != &"world_object":
		return _fail("Player character InteractionTarget has the wrong domain.")
	if not (pc_target.target_data is WorldObjectDataScript):
		return _fail("Player character InteractionTarget does not carry WorldObjectData.")
	if not _has_action(InteractionActionResolverScript.get_actions(pc_target), InteractionActionResolverScript.ACTION_EXAMINE):
		return _fail("World object interaction target should expose Examine.")
	if not _has_action(InteractionActionResolverScript.get_actions(pc_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("Player character interaction target should expose Move.")
	if not MoveTargetResolverScript.can_start_move(pc_target):
		return _fail("MoveTargetResolver did not accept the player character as a move source.")

	var examine_output := InteractionActionResolverScript.build_examine_output(pc_target)
	if examine_output.get("domain") != &"world_object":
		return _fail("Examine output has the wrong domain.")
	if examine_output.get("object_kind") != &"player_character":
		return _fail("Examine output has the wrong object kind.")
	if examine_output.get("object_id") != &"pc_001":
		return _fail("Examine output has the wrong object id.")

	var move_target_data := MoveTargetDataScript.new(Vector3(1.25, 0.0, -2.5))
	if move_target_data.position != Vector3(1.25, 0.0, -2.5):
		return _fail("MoveTargetData did not preserve the Vector3 position.")

	var npc_data := WorldObjectDataScript.new(
		&"npc_001",
		&"non_player_character",
		Vector3(1.0, 0.0, 1.0),
		pc_size,
		Color(0.45, 0.45, 0.45, 1.0),
		true
	)
	var npc_view := BlockoutObjectViewScript.new()
	npc_view.object_data = npc_data
	get_root().add_child(npc_view)
	var npc_target := npc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if _has_action(InteractionActionResolverScript.get_actions(npc_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("NPC interaction target should not expose Move.")
	if MoveTargetResolverScript.can_start_move(npc_target):
		return _fail("MoveTargetResolver accepted an NPC as a move source.")

	npc_view.free()
	pc_view.free()
	return true

func _check_native_navigation_resolver() -> bool:
	var nav := _create_square_nav_map()
	var navigation_map: RID = nav["map"]
	var navigation_region: RID = nav["region"]
	await _wait_for_navigation_map(navigation_map)

	var reachable_path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		Vector3(0.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 2.0)
	)
	if reachable_path.is_empty():
		_free_nav_map(navigation_map, navigation_region)
		return _fail("MoveTargetResolver did not return a native nav path across the square region.")

	var off_nav_path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		Vector3(0.0, 0.0, 0.0),
		Vector3(6.0, 0.0, 6.0)
	)
	if not off_nav_path.is_empty():
		_free_nav_map(navigation_map, navigation_region)
		return _fail("MoveTargetResolver accepted a destination outside the nav snap tolerance.")

	var source := _make_interaction_target(
		InteractionActionResolverScript.DOMAIN_WORLD_OBJECT,
		WorldObjectDataScript.new(&"pc_nav", &"player_character", Vector3.ZERO)
	)
	var destination := _make_interaction_target(
		InteractionActionResolverScript.DOMAIN_MOVE_TARGET,
		MoveTargetDataScript.new(Vector3(2.0, 0.0, 2.0))
	)
	if not MoveTargetResolverScript.can_select_destination(destination):
		_free_nav_map(navigation_map, navigation_region)
		return _fail("MoveTargetResolver did not accept a move_target destination.")
	if not MoveTargetResolverScript.can_move(source, destination, navigation_map):
		_free_nav_map(navigation_map, navigation_region)
		return _fail("MoveTargetResolver did not validate movement over the native nav map.")

	(destination.target_data as MoveTargetDataScript).position = Vector3(6.0, 0.0, 6.0)
	if MoveTargetResolverScript.can_move(source, destination, navigation_map):
		_free_nav_map(navigation_map, navigation_region)
		return _fail("MoveTargetResolver accepted an unreachable off-nav destination.")

	source.free()
	destination.free()
	_free_nav_map(navigation_map, navigation_region)
	return true

func _check_targeting_and_controller(root_event_bus: Node) -> bool:
	var pc_data := WorldObjectDataScript.new(&"pc_target", &"player_character", Vector3.ZERO)
	var pc_view := BlockoutObjectViewScript.new()
	pc_view.object_data = pc_data
	get_root().add_child(pc_view)
	var pc_target := pc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript

	var move_target_parent := Node3D.new()
	get_root().add_child(move_target_parent)
	var move_target := InteractionTargetScript.new()
	move_target.target_domain = InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	move_target.target_data = MoveTargetDataScript.new(Vector3(1.0, 0.0, 1.0))
	move_target_parent.add_child(move_target)

	_move_requested_count = 0
	_move_requested_actor = null
	_move_requested_actor_data = null
	_move_requested_destination = null
	var move_requested_callable := Callable(self, "_record_move_requested")
	if root_event_bus != null:
		root_event_bus.connect(&"move_requested", move_requested_callable)

	var targeting_controller := InteractionControllerScript.new()
	get_root().add_child(targeting_controller)
	targeting_controller._ready()
	if not targeting_controller.start_targeting(pc_target, InteractionActionResolverScript.ACTION_MOVE):
		return _fail("InteractionController did not enter move targeting for a PC source.")
	if targeting_controller.try_confirm_targeting_target(move_target):
		return _fail("InteractionController confirmed a target without an attached native nav map.")
	if _move_requested_count != 0:
		return _fail("InteractionController emitted move_requested for an invalid destination.")
	targeting_controller.cancel_targeting()
	if root_event_bus != null:
		root_event_bus.disconnect(&"move_requested", move_requested_callable)
	targeting_controller.free()
	move_target_parent.free()

	var nav := _create_square_nav_map()
	var navigation_map: RID = nav["map"]
	var navigation_region: RID = nav["region"]
	pc_view.get_navigation_agent().set_navigation_map(navigation_map)
	await _wait_for_navigation_map(navigation_map)
	var setup_path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		pc_data.position,
		Vector3(2.0, 0.0, 0.0)
	)
	if setup_path.is_empty():
		var start_snap := NavigationServer3D.map_get_closest_point(navigation_map, pc_data.position)
		var target_snap := NavigationServer3D.map_get_closest_point(navigation_map, Vector3(2.0, 0.0, 0.0))
		_free_nav_map(navigation_map, navigation_region)
		return _fail(
			"Test native navigation map did not produce a path. Iteration=%d start_snap=%s target_snap=%s."
			% [
				NavigationServer3D.map_get_iteration_id(navigation_map),
				start_snap,
				target_snap,
			]
		)

	var movement_controller := MovementControllerScript.new()
	movement_controller.movement_speed_mps = 10.0
	get_root().add_child(movement_controller)
	movement_controller._ready()
	var movement_controller_has_event_bus := movement_controller._get_event_bus() != null
	var movement_started_callable := Callable(self, "_record_movement_started")
	var movement_completed_callable := Callable(self, "_record_movement_completed")
	var movement_failed_callable := Callable(self, "_record_movement_failed")
	if root_event_bus != null and movement_controller_has_event_bus:
		root_event_bus.connect(&"movement_started", movement_started_callable)
		root_event_bus.connect(&"movement_completed", movement_completed_callable)
		root_event_bus.connect(&"movement_failed", movement_failed_callable)

	_movement_started_count = 0
	_movement_started_path = PackedVector3Array()
	_movement_completed_count = 0
	_movement_failed_count = 0
	_movement_failed_reason = &""
	var valid_destination := MoveTargetDataScript.new(Vector3(2.0, 0.0, 0.0))
	if not movement_controller.request_move(pc_view, pc_data, valid_destination):
		return _fail("MovementController rejected a valid nav-backed movement: %s." % _movement_failed_reason)
	if not movement_controller.is_actor_busy(pc_view):
		return _fail("MovementController did not mark the actor busy after movement start.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_started_count != 1 or _movement_started_path.is_empty():
			return _fail("MovementController did not emit movement_started with a native path.")

	_movement_failed_count = 0
	_movement_failed_reason = &""
	if movement_controller.request_move(pc_view, pc_data, MoveTargetDataScript.new(Vector3(1.0, 0.0, 0.0))):
		return _fail("MovementController accepted a second move while the actor was busy.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_failed_count != 1 or _movement_failed_reason != &"actor_busy":
			return _fail("MovementController did not emit actor_busy for a repeated request.")

	for _index in range(40):
		await physics_frame
		movement_controller._physics_process(0.1)
		if not movement_controller.is_actor_busy(pc_view):
			break

	if movement_controller.is_actor_busy(pc_view):
		return _fail("MovementController did not complete movement within the expected ticks.")
	if pc_view.position.distance_to(valid_destination.position) > 0.001:
		return _fail("MovementController did not snap the actor to the target position.")
	if pc_data.position.distance_to(valid_destination.position) > 0.001:
		return _fail("MovementController did not update WorldObjectData.position on completion.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_completed_count != 1:
			return _fail("MovementController did not emit movement_completed.")

	_movement_failed_count = 0
	_movement_failed_reason = &""
	if movement_controller.request_move(pc_view, pc_data, MoveTargetDataScript.new(valid_destination.position)):
		return _fail("MovementController accepted already-at-destination movement.")
	if movement_controller.is_actor_busy(pc_view):
		return _fail("MovementController marked an actor busy for a rejected movement.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_failed_count != 1 or _movement_failed_reason != &"already_at_destination":
			return _fail("MovementController did not emit already_at_destination.")

	_movement_failed_count = 0
	_movement_failed_reason = &""
	if movement_controller.request_move(
		pc_view,
		WorldObjectDataScript.new(&"npc_move", &"non_player_character", pc_data.position),
		MoveTargetDataScript.new(Vector3(1.0, 0.0, 1.0))
	):
		return _fail("MovementController accepted non-player movement data.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_failed_count != 1 or _movement_failed_reason != &"invalid_request":
			return _fail("MovementController did not reject non-player movement data.")

	_movement_failed_count = 0
	_movement_failed_reason = &""
	var bare_actor := Node3D.new()
	bare_actor.position = pc_data.position
	get_root().add_child(bare_actor)
	if movement_controller.request_move(
		bare_actor,
		WorldObjectDataScript.new(&"pc_no_agent", &"player_character", pc_data.position),
		MoveTargetDataScript.new(Vector3(1.0, 0.0, 1.0))
	):
		return _fail("MovementController accepted an actor without a NavigationAgent3D.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_failed_count != 1 or _movement_failed_reason != &"missing_navigation_agent":
			return _fail("MovementController did not emit missing_navigation_agent.")
	bare_actor.free()

	_movement_failed_count = 0
	_movement_failed_reason = &""
	if movement_controller.request_move(pc_view, pc_data, MoveTargetDataScript.new(Vector3(8.0, 0.0, 8.0))):
		return _fail("MovementController accepted movement without a nav path.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_failed_count != 1 or _movement_failed_reason != &"no_path":
			return _fail("MovementController did not emit no_path for missing nav.")
		root_event_bus.disconnect(&"movement_started", movement_started_callable)
		root_event_bus.disconnect(&"movement_completed", movement_completed_callable)
		root_event_bus.disconnect(&"movement_failed", movement_failed_callable)

	movement_controller.free()
	_free_nav_map(navigation_map, navigation_region)
	pc_view.free()
	return true

func _check_walls() -> bool:
	var wall_segment := WallSegmentDataScript.new(
		Vector3(-1.0, 0.0, 2.0),
		Vector3(2.0, 0.0, 2.0),
		2.2,
		0.18,
		Color(0.35, 0.34, 0.32, 1.0)
	)
	if not wall_segment.is_valid_segment():
		return _fail("WallSegmentData rejected a valid Vector3 segment.")

	var wall_endpoints := WallVisualResolverScript.visual_endpoints(wall_segment)
	if wall_endpoints.size() != 2 or wall_endpoints[0] != wall_segment.start_position:
		return _fail("WallVisualResolver did not return Vector3 segment endpoints.")
	if not is_equal_approx(WallVisualResolverScript.visual_length(wall_segment), 3.0):
		return _fail("WallVisualResolver returned the wrong wall length.")

	var wall_layout := WallLayoutViewScript.new()
	wall_layout.rebake_navigation_on_apply = false
	wall_layout.wall_segments.append(wall_segment)
	get_root().add_child(wall_layout)
	wall_layout.apply_layout()
	var wall_visual_root := wall_layout.get_node_or_null("WallVisuals")
	if wall_visual_root == null or wall_visual_root.get_child_count() != 1:
		return _fail("WallLayoutView did not create wall visuals.")
	var wall := wall_visual_root.get_child(0) as Node3D
	if wall == null:
		return _fail("WallLayoutView did not create a Node3D wall root.")
	var wall_mesh_instance := wall.get_node_or_null("Mesh") as MeshInstance3D
	var wall_box_mesh := wall_mesh_instance.mesh as BoxMesh
	if wall_box_mesh == null:
		return _fail("WallLayoutView visual is not a BoxMesh.")
	if not is_equal_approx(wall_box_mesh.size.y, wall_segment.height_m):
		return _fail("WallLayoutView visual does not use the configured wall height.")
	if not is_equal_approx(wall_box_mesh.size.x, wall_segment.thickness_m):
		return _fail("WallLayoutView visual does not use the configured wall thickness.")
	var static_body := wall.get_node_or_null("StaticBody3D") as StaticBody3D
	if static_body == null:
		return _fail("WallLayoutView did not create static wall collision.")
	var wall_collision := static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if wall_collision == null or not (wall_collision.shape is BoxShape3D):
		return _fail("WallLayoutView static wall collision is missing a BoxShape3D.")
	wall_layout.free()
	return true

func _check_hover_and_ui(root_event_bus: Node) -> bool:
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
	highlighter.clear_highlight()
	if mesh.get_node_or_null("HoverShell") != null:
		return _fail("HoverHighlighter did not remove shell meshes after clearing.")
	mesh.free()

	var interaction_controller := InteractionControllerScript.new()
	get_root().add_child(interaction_controller)
	interaction_controller._ready()
	interaction_controller._handle_interaction_pointer_capture_changed(true)
	if not interaction_controller.is_interaction_pointer_captured():
		return _fail("InteractionController did not pause for interaction pointer capture.")
	interaction_controller._handle_interaction_pointer_capture_changed(false)
	if interaction_controller.is_interaction_pointer_captured():
		return _fail("InteractionController did not resume after pointer capture release.")

	var interaction_menu := InteractionMenuScript.new()
	interaction_menu._ready()
	var npc_target := _make_interaction_target(
		InteractionActionResolverScript.DOMAIN_WORLD_OBJECT,
		WorldObjectDataScript.new(&"npc_ui", &"non_player_character", Vector3.ZERO)
	)
	if root_event_bus != null and interaction_menu._get_event_bus() != null and interaction_controller._get_event_bus() != null:
		root_event_bus.emit_signal(&"interaction_menu_requested", npc_target, Vector2.ZERO)
		if not interaction_menu.visible:
			return _fail("InteractionMenu did not open from a menu request.")
		if not interaction_controller.is_interaction_pointer_captured():
			return _fail("InteractionController did not capture pointer when the menu opened.")
		root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
		if interaction_menu.visible:
			return _fail("InteractionMenu did not close from a cancel request.")
	else:
		interaction_menu._on_interaction_menu_requested(npc_target, Vector2.ZERO)
		if not interaction_menu.visible:
			return _fail("InteractionMenu did not open from a direct menu request.")
		interaction_menu._on_interaction_ui_cancel_requested()
		if interaction_menu.visible:
			return _fail("InteractionMenu did not close from a direct cancel request.")

	npc_target.free()
	interaction_menu.free()
	var interaction_log_panel := InteractionLogPanelScript.new()
	interaction_log_panel.free()
	interaction_controller.free()
	return true

func _check_main_scene(root_event_bus: Node) -> bool:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("Main scene did not load.")
	var main := main_scene.instantiate()
	get_root().add_child(main)
	if main.get_node_or_null("HexGridManager") != null:
		return _fail("Main scene still contains HexGridManager.")
	if main.get_node_or_null("NavigationRegion3D") == null:
		return _fail("Main scene is missing NavigationRegion3D.")
	var navigation_region := main.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if navigation_region.navigation_mesh == null:
		return _fail("NavigationRegion3D is missing a NavigationMesh.")
	if navigation_region.get_node_or_null("Floor") as StaticBody3D == null:
		return _fail("Main scene is missing a static floor body.")
	var floor_target := navigation_region.get_node_or_null("Floor/FloorMoveTarget") as InteractionTargetScript
	if floor_target == null:
		return _fail("Main scene is missing the floor move target.")
	if floor_target.target_domain != InteractionActionResolverScript.DOMAIN_MOVE_TARGET:
		return _fail("Floor move target has the wrong domain.")
	if not (floor_target.target_data is MoveTargetDataScript):
		return _fail("Floor move target does not carry MoveTargetData.")
	var main_wall_layout := navigation_region.get_node_or_null("WallLayout") as WallLayoutViewScript
	if main_wall_layout == null:
		return _fail("Main scene wall layout should be inside the navigation region.")
	if main_wall_layout.wall_segments.size() != 2:
		return _fail("Main scene wall layout should contain two sample wall segments.")
	if not main_wall_layout.wall_segments[0].is_valid_segment():
		return _fail("Main scene first wall segment is invalid.")
	main_wall_layout.apply_layout()
	var main_wall_visual_root := main_wall_layout.get_node_or_null("WallVisuals")
	if main_wall_visual_root == null or main_wall_visual_root.get_child_count() != 2:
		return _fail("Main scene wall layout did not build its static wall nodes.")
	if main.get_node_or_null("MovementController") == null:
		return _fail("Main scene is missing MovementController.")
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
	var main_pc := main.get_node_or_null("PlayerCharacter") as BlockoutObjectViewScript
	if main_pc == null or main_pc.object_data == null:
		return _fail("Main scene is missing PlayerCharacter data.")
	if main_pc.get_navigation_agent() == null:
		return _fail("Main scene PlayerCharacter is missing a NavigationAgent3D.")
	var main_npc := main.get_node_or_null("NPC") as BlockoutObjectViewScript
	if main_npc == null or main_npc.object_data == null:
		return _fail("Main scene is missing NPC data.")
	if main_npc.get_navigation_agent() == null:
		return _fail("Main scene NPC is missing a NavigationAgent3D.")
	if main_npc.position != main_npc.object_data.position:
		return _fail("NPC view is not using WorldObjectData.position.")
	var main_npc_target := main_npc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if main_npc_target == null:
		return _fail("NPC did not create an InteractionTarget.")
	if _has_action(InteractionActionResolverScript.get_actions(main_npc_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("NPC interaction target should not expose Move.")
	if MoveTargetResolverScript.can_start_move(main_npc_target):
		return _fail("MoveTargetResolver accepted an NPC as a move source.")

	var main_interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	if main_interaction_controller == null:
		return _fail("Main scene is missing InteractionController.")
	main_interaction_controller._ready()
	if root_event_bus != null and main_interaction_menu._get_event_bus() != null and main_interaction_controller._get_event_bus() != null:
		root_event_bus.emit_signal(&"interaction_menu_requested", main_npc_target, Vector2.ZERO)
		if not main_interaction_menu.visible:
			return _fail("InteractionMenu did not open from a main scene menu request.")
		root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
		if main_interaction_menu.visible:
			return _fail("InteractionMenu did not close from a main scene cancel request.")

	main.free()
	return true

func _check_main_scene_interaction_raycast(root_event_bus: Node) -> bool:
	if root_event_bus == null:
		return _fail("Main scene interaction raycast check requires EventBus.")

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("Main scene did not load for interaction raycast check.")

	var original_root_size := get_root().size
	get_root().size = Vector2i(1280, 720)
	var main := main_scene.instantiate() as Node3D
	get_root().add_child(main)
	await process_frame
	await physics_frame

	var camera := main.get_node_or_null("CameraRig/PitchPivot/Camera3D") as Camera3D
	var interaction_controller := main.get_node_or_null("InteractionController") as InteractionControllerScript
	var interaction_ui := main.get_node_or_null("InteractionUI") as CanvasLayer
	var interaction_menu := interaction_ui.get_node_or_null("InteractionMenu") as InteractionMenuScript
	var interaction_log_panel := interaction_ui.get_node_or_null("InteractionLogPanel") as InteractionLogPanelScript
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
		main.free()
		return _fail("Main scene interaction raycast check is missing required nodes.")

	interaction_controller._ready()
	interaction_menu._ready()
	interaction_log_panel._ready()

	var pc_target := main_pc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	var npc_target := main_npc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	var floor_target := navigation_region.get_node_or_null("Floor/FloorMoveTarget") as InteractionTargetScript
	if pc_target == null or npc_target == null or floor_target == null:
		main.free()
		return _fail("Main scene interaction raycast check is missing interaction targets.")
	if not pc_target.input_ray_pickable or not npc_target.input_ray_pickable or not floor_target.input_ray_pickable:
		main.free()
		return _fail("Main scene interaction targets are not ray-pickable.")
	if pc_target.target_data != main_pc.object_data or npc_target.target_data != main_npc.object_data:
		main.free()
		return _fail("World-object interaction targets do not carry their object data.")

	var nav := _create_square_nav_map()
	var navigation_map: RID = nav["map"]
	var navigation_region_rid: RID = nav["region"]
	main_pc.get_navigation_agent().set_navigation_map(navigation_map)
	await _wait_for_navigation_map(navigation_map)

	var hover_callable := Callable(self, "_record_hover_target_changed")
	var move_requested_callable := Callable(self, "_record_move_requested")
	var examined_callable := Callable(self, "_record_examined_output")
	if not root_event_bus.is_connected(&"hover_target_changed", hover_callable):
		root_event_bus.connect(&"hover_target_changed", hover_callable)
	if not root_event_bus.is_connected(&"move_requested", move_requested_callable):
		root_event_bus.connect(&"move_requested", move_requested_callable)
	if not root_event_bus.is_connected(&"examined_output", examined_callable):
		root_event_bus.connect(&"examined_output", examined_callable)

	_hover_changed_count = 0
	_hover_changed_target = null
	var pc_hover_position := main_pc.global_position + BlockoutObjectViewScript.body_center_offset(main_pc.object_data.size_m)
	var pc_screen_position := _warp_mouse_to_world(camera, pc_hover_position)
	await process_frame
	await physics_frame
	_drive_interaction_hover_at_screen(interaction_controller, pc_screen_position)
	if _hover_changed_target != pc_target:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("CameraRig raycast did not hover the player character InteractionTarget.")
	if main_pc.get_node_or_null("Body/HoverShell") == null:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Player hover did not apply a highlight shell.")

	var hover_count_before_capture := _hover_changed_count
	interaction_controller._handle_interaction_pointer_capture_changed(true)
	var npc_hover_position := main_npc.global_position + BlockoutObjectViewScript.body_center_offset(main_npc.object_data.size_m)
	_warp_mouse_to_world(camera, npc_hover_position)
	await process_frame
	await physics_frame
	interaction_controller._physics_process(0.016)
	if _hover_changed_count != hover_count_before_capture or _hover_changed_target != pc_target:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("InteractionController changed hover while pointer capture was active.")
	interaction_controller._handle_interaction_pointer_capture_changed(false)

	_warp_mouse_to_world(camera, npc_hover_position)
	await process_frame
	await physics_frame
	_drive_interaction_hover_at_screen(interaction_controller, camera.unproject_position(npc_hover_position))
	if _hover_changed_target != npc_target:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("CameraRig raycast did not hover the NPC InteractionTarget.")
	if main_pc.get_node_or_null("Body/HoverShell") != null:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Player hover highlight was not cleared after hovering the NPC.")
	if main_npc.get_node_or_null("Body/HoverShell") == null:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("NPC hover did not apply a highlight shell.")

	_warp_mouse_to_world(camera, pc_hover_position)
	await process_frame
	await physics_frame
	_drive_interaction_hover_at_screen(interaction_controller, pc_screen_position)
	interaction_controller._request_menu_for_current_target(pc_screen_position)
	await process_frame
	await process_frame
	if not interaction_menu.visible:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("InteractionMenu did not open from the hovered player target.")
	if not interaction_controller.is_interaction_pointer_captured():
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("InteractionMenu did not capture the interaction pointer.")
	if not _control_inside_viewport(interaction_menu):
		var menu_rect := Rect2(interaction_menu.position, interaction_menu.size)
		var viewport_size := interaction_menu.get_viewport_rect().size
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail(
			"InteractionMenu was not clamped inside the viewport. rect=%s viewport=%s."
			% [menu_rect, viewport_size]
		)
	root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
	if interaction_menu.visible or interaction_controller.is_interaction_pointer_captured():
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("InteractionMenu did not close from a cancel request.")

	interaction_controller._request_menu_for_current_target(pc_screen_position)
	await process_frame
	await process_frame
	root_event_bus.emit_signal(&"hover_target_changed", npc_target)
	if interaction_menu.visible:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("InteractionMenu did not close when hover changed targets.")

	_examined_count = 0
	_examined_target_domain = &""
	_examined_target_data = null
	_examined_output = {}
	root_event_bus.emit_signal(&"interaction_action_requested", npc_target, InteractionActionResolverScript.ACTION_EXAMINE)
	if _examined_count != 1:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Examine action did not emit examined_output.")
	if _examined_target_domain != InteractionActionResolverScript.DOMAIN_WORLD_OBJECT:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Examine output carried the wrong target domain.")
	if _examined_target_data != main_npc.object_data:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Examine output carried the wrong target data.")
	if _examined_output.get("object_id") != main_npc.object_data.object_id:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Examine output did not include the NPC object id.")
	var log_label := interaction_log_panel.get_node_or_null("Content") as Label
	if log_label == null or not log_label.text.contains("npc_001"):
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("InteractionLogPanel did not render the examined NPC data.")

	if interaction_controller.start_targeting(npc_target, InteractionActionResolverScript.ACTION_MOVE):
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("NPC target started move targeting.")
	if not interaction_controller.start_targeting(pc_target, InteractionActionResolverScript.ACTION_MOVE):
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("PC target did not start move targeting.")

	_warp_mouse_to_world(camera, pc_hover_position)
	await process_frame
	await physics_frame
	_drive_interaction_hover_at_screen(
		interaction_controller,
		pc_screen_position,
		InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	)
	if _hover_changed_target == pc_target:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Move targeting raycast did not filter out world-object targets.")

	var floor_click_position := Vector3(2.0, 0.0, 0.0)
	var floor_screen_position := _warp_mouse_to_world(camera, floor_click_position)
	await process_frame
	await physics_frame
	var expected_floor_hit := _raycast_first_area_hit(camera, floor_screen_position)
	if expected_floor_hit.is_empty() or expected_floor_hit.get("collider") != floor_target:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("CameraRig raycast did not hit the floor move target.")
	_drive_interaction_hover_at_screen(
		interaction_controller,
		floor_screen_position,
		InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	)
	if _hover_changed_target != floor_target:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Move targeting did not hover the floor move target.")
	var expected_floor_position: Vector3 = expected_floor_hit.get("position", Vector3.ZERO)
	var floor_data := floor_target.target_data as MoveTargetDataScript
	if floor_data == null or floor_data.position.distance_to(expected_floor_position) > 0.001:
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Floor MoveTargetData did not preserve the exact raycast hit position.")

	_move_requested_count = 0
	_move_requested_actor = null
	_move_requested_actor_data = null
	_move_requested_destination = null
	if not interaction_controller.try_confirm_targeting_target(floor_target):
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Move targeting did not confirm a reachable floor target.")
	if (
		_move_requested_count != 1
		or _move_requested_actor != main_pc
		or _move_requested_actor_data != main_pc.object_data
		or _move_requested_destination != floor_data
	):
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Move targeting emitted the wrong move_requested payload.")
	if interaction_controller.is_targeting_interaction():
		_free_nav_map(navigation_map, navigation_region_rid)
		main.free()
		return _fail("Move targeting stayed active after confirmation.")

	root_event_bus.disconnect(&"hover_target_changed", hover_callable)
	root_event_bus.disconnect(&"move_requested", move_requested_callable)
	root_event_bus.disconnect(&"examined_output", examined_callable)
	_free_nav_map(navigation_map, navigation_region_rid)
	main.free()
	get_root().size = original_root_size
	return true

func _create_square_nav_map() -> Dictionary:
	var navigation_map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(navigation_map, true)

	var navigation_region := _create_square_nav_region_on_map(navigation_map)
	return {
		"map": navigation_map,
		"region": navigation_region,
	}

func _wait_for_navigation_map(navigation_map: RID) -> void:
	for _index in range(8):
		if NavigationServer3D.map_get_iteration_id(navigation_map) > 0:
			return

		await process_frame
		await physics_frame
		NavigationServer3D.map_force_update(navigation_map)

func _create_square_nav_region_on_map(navigation_map: RID) -> RID:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.vertices = PackedVector3Array([
		Vector3(-3.0, 0.0, -3.0),
		Vector3(3.0, 0.0, -3.0),
		Vector3(3.0, 0.0, 3.0),
		Vector3(-3.0, 0.0, 3.0),
	])
	navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var navigation_region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_navigation_layers(navigation_region, 1)
	NavigationServer3D.region_set_navigation_mesh(navigation_region, navigation_mesh)
	NavigationServer3D.region_set_map(navigation_region, navigation_map)
	NavigationServer3D.region_set_enabled(navigation_region, true)
	NavigationServer3D.map_force_update(navigation_map)
	return navigation_region

func _free_nav_map(navigation_map: RID, navigation_region: RID) -> void:
	if navigation_region.is_valid():
		NavigationServer3D.free_rid(navigation_region)
	if navigation_map.is_valid():
		NavigationServer3D.free_rid(navigation_map)

func _make_interaction_target(target_domain: StringName, target_data: Resource) -> InteractionTargetScript:
	var target := InteractionTargetScript.new()
	target.target_domain = target_domain
	target.target_data = target_data
	return target

func _warp_mouse_to_world(camera: Camera3D, world_position: Vector3) -> Vector2:
	var screen_position := camera.unproject_position(world_position)
	get_root().warp_mouse(screen_position)
	return screen_position

func _raycast_first_area_hit(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + (camera.project_ray_normal(screen_position) * 100.0)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return camera.get_world_3d().direct_space_state.intersect_ray(query)

func _drive_interaction_hover_at_screen(
	interaction_controller: InteractionControllerScript,
	screen_position: Vector2,
	required_domain: StringName = &""
) -> InteractionTargetScript:
	var target := interaction_controller._raycast_interaction_target_at(screen_position, required_domain)
	interaction_controller._set_hover_target(target)
	return target

func _control_inside_viewport(control: Control) -> bool:
	var viewport_rect := control.get_viewport_rect()
	var control_rect := Rect2(control.position, control.size)
	return (
		control_rect.position.x >= 0.0
		and control_rect.position.y >= 0.0
		and control_rect.end.x <= viewport_rect.size.x
		and control_rect.end.y <= viewport_rect.size.y
	)

func _has_action(actions: Array[Dictionary], action_id: StringName) -> bool:
	for action in actions:
		if action.get("id") == action_id:
			return true

	return false

func _record_move_requested(actor: Node, actor_data: Resource, destination_data: Resource) -> void:
	_move_requested_count += 1
	_move_requested_actor = actor
	_move_requested_actor_data = actor_data
	_move_requested_destination = destination_data

func _record_hover_target_changed(target: Node) -> void:
	_hover_changed_count += 1
	_hover_changed_target = target

func _record_examined_output(target_domain: StringName, target_data: Resource, output: Dictionary) -> void:
	_examined_count += 1
	_examined_target_domain = target_domain
	_examined_target_data = target_data
	_examined_output = output

func _record_movement_started(_actor: Node, path: PackedVector3Array) -> void:
	_movement_started_count += 1
	_movement_started_path = path

func _record_movement_completed(_actor: Node, _destination_data: Resource) -> void:
	_movement_completed_count += 1

func _record_movement_failed(_actor: Node, _destination_data: Resource, reason: StringName) -> void:
	_movement_failed_count += 1
	_movement_failed_reason = reason

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
