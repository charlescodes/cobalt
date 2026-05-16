extends SceneTree

const EventBusScript := preload("res://src/core/event_bus.gd")
const CameraRigScript := preload("res://src/camera/camera_rig.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const InteractionLogPanelScript := preload("res://src/ui/interaction_log_panel.gd")
const MovementControllerScript := preload("res://src/movement/movement_controller.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const WallLayoutViewScript := preload("res://src/walls/wall_layout_view.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WallVisualResolverScript := preload("res://src/walls/wall_visual_resolver.gd")

var _move_requested_count: int = 0
var _move_requested_actor: Node
var _move_requested_destination: Resource
var _movement_failed_count: int = 0
var _movement_failed_reason: StringName = &""

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
	if not pc_interaction_target.is_in_group(InteractionTargetScript.GROUP_NAME):
		return _fail("InteractionTarget did not join the expected group.")
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
	var npc_interaction_target := npc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if _has_action(InteractionActionResolverScript.get_actions(npc_interaction_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("NPC interaction target should not expose Move.")
	if MoveTargetResolverScript.can_start_move(npc_interaction_target):
		return _fail("MoveTargetResolver accepted an NPC as a move source.")

	var move_target_parent := Node3D.new()
	get_root().add_child(move_target_parent)
	var move_target := InteractionTargetScript.new()
	move_target.target_domain = InteractionActionResolverScript.DOMAIN_MOVE_TARGET
	move_target.target_data = Resource.new()
	move_target_parent.add_child(move_target)
	if MoveTargetResolverScript.can_select_destination(move_target):
		return _fail("MoveTargetResolver accepted an interim move destination before navmesh support.")
	if MoveTargetResolverScript.can_move(pc_interaction_target, move_target):
		return _fail("MoveTargetResolver accepted PC movement before navmesh support.")

	_move_requested_count = 0
	_move_requested_actor = null
	_move_requested_destination = null
	var move_requested_callable := Callable(self, "_record_move_requested")
	if root_event_bus != null:
		root_event_bus.connect(&"move_requested", move_requested_callable)

	var targeting_controller := InteractionControllerScript.new()
	get_root().add_child(targeting_controller)
	targeting_controller._ready()
	if not targeting_controller.start_targeting(pc_interaction_target, InteractionActionResolverScript.ACTION_MOVE):
		return _fail("InteractionController did not enter move targeting for a PC source.")
	if not targeting_controller.is_targeting_interaction():
		return _fail("InteractionController did not report active move targeting.")
	if targeting_controller.try_confirm_targeting_target(move_target):
		return _fail("InteractionController confirmed an interim move destination.")
	if _move_requested_count != 0:
		return _fail("InteractionController emitted move_requested for an invalid interim destination.")
	var right_click := InputEventMouseButton.new()
	right_click.pressed = true
	right_click.button_index = MOUSE_BUTTON_RIGHT
	targeting_controller._input(right_click)
	if targeting_controller.is_targeting_interaction():
		return _fail("InteractionController did not cancel move targeting on RMB.")
	if root_event_bus != null:
		root_event_bus.disconnect(&"move_requested", move_requested_callable)
	targeting_controller.free()
	move_target_parent.free()

	var movement_controller := MovementControllerScript.new()
	get_root().add_child(movement_controller)
	movement_controller._ready()
	var movement_controller_has_event_bus := movement_controller._get_event_bus() != null
	var movement_failed_callable := Callable(self, "_record_movement_failed")
	if root_event_bus != null and movement_controller_has_event_bus:
		root_event_bus.connect(&"movement_failed", movement_failed_callable)
	_movement_failed_count = 0
	_movement_failed_reason = &""
	if movement_controller.request_move(pc_view, pc_data, Resource.new()):
		return _fail("MovementController accepted movement before navmesh support.")
	if movement_controller.is_actor_busy(pc_view):
		return _fail("MovementController marked an actor busy for a rejected movement.")
	if root_event_bus != null and movement_controller_has_event_bus:
		if _movement_failed_count != 1:
			return _fail("MovementController did not emit one movement_failed event.")
		if _movement_failed_reason != &"navigation_unavailable":
			return _fail("MovementController emitted the wrong interim failure reason.")
		root_event_bus.disconnect(&"movement_failed", movement_failed_callable)
	movement_controller.free()

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
	if not wall_segment.is_valid_span_mode():
		return _fail("WallSegmentData rejected a valid span mode.")
	var wall_endpoints := WallVisualResolverScript.visual_endpoints(wall_segment)
	if wall_endpoints.size() != 2:
		return _fail("WallVisualResolver did not return visual segment endpoints.")

	var wall_layout := WallLayoutViewScript.new()
	wall_layout.wall_segments.append(wall_segment)
	get_root().add_child(wall_layout)
	wall_layout.apply_layout()
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
	wall_layout.free()

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

	var interaction_menu := InteractionMenuScript.new()
	interaction_menu.free()
	var interaction_log_panel := InteractionLogPanelScript.new()
	interaction_log_panel.free()

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("Main scene did not load.")
	var main := main_scene.instantiate()
	get_root().add_child(main)
	if main.get_node_or_null("HexGridManager") != null:
		return _fail("Main scene still contains HexGridManager.")
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
	if main_pc == null:
		return _fail("Main scene is missing PlayerCharacter.")
	if main_pc.object_data == null or main_pc.object_data.position != Vector3.ZERO:
		return _fail("PlayerCharacter is not using direct Vector3 object data.")
	var main_npc := main.get_node_or_null("NPC") as BlockoutObjectViewScript
	if main_npc == null:
		return _fail("Main scene is missing NPC.")
	if main_npc.object_data == null or main_npc.object_data.object_kind != &"non_player_character":
		return _fail("NPC object data is missing or has the wrong kind.")
	if main_npc.position != main_npc.object_data.position:
		return _fail("NPC view is not using WorldObjectData.position.")
	if main_npc.object_data.color != Color(0.45, 0.45, 0.45, 1.0):
		return _fail("NPC is not using the expected gray color.")
	var main_npc_interaction_target := main_npc.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if main_npc_interaction_target == null:
		return _fail("NPC did not create an InteractionTarget.")
	if main_npc_interaction_target.target_domain != &"world_object":
		return _fail("NPC InteractionTarget has the wrong domain.")
	if not (main_npc_interaction_target.target_data is WorldObjectDataScript):
		return _fail("NPC InteractionTarget does not carry WorldObjectData.")
	if _has_action(InteractionActionResolverScript.get_actions(main_npc_interaction_target), InteractionActionResolverScript.ACTION_MOVE):
		return _fail("NPC interaction target should not expose Move.")
	if MoveTargetResolverScript.can_start_move(main_npc_interaction_target):
		return _fail("MoveTargetResolver accepted an NPC as a move source.")

	var main_ui_has_event_bus := (
		root_event_bus != null
		and main_interaction_menu._get_event_bus() != null
		and main_interaction_controller._get_event_bus() != null
	)
	if main_ui_has_event_bus:
		root_event_bus.emit_signal(&"interaction_menu_requested", main_npc_interaction_target, Vector2.ZERO)
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
		main_interaction_menu._on_interaction_menu_requested(main_npc_interaction_target, Vector2.ZERO)
		if not main_interaction_menu.visible:
			return _fail("InteractionMenu did not open from a direct menu request.")
		main_interaction_menu._on_interaction_ui_cancel_requested()
		if main_interaction_menu.visible:
			return _fail("InteractionMenu did not close from a direct cancel request.")
	main.free()

	var camera_distance: float = CameraRigScript.camera_distance_for_height(7.0, deg_to_rad(-55.0))
	if not camera_distance > 7.0:
		return _fail("Camera rig distance should exceed its vertical height at an angled pitch.")

	npc_view.free()
	pc_view.free()
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
