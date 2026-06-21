extends RefCounted

const GameplayModeControllerScript := preload("res://src/movement/gameplay_mode_controller.gd")
const RealtimeGameplayControllerScript := preload("res://src/movement/realtime_gameplay_controller.gd")
const EditorModeControllerScript := preload("res://src/editor/editor_mode_controller.gd")
const CameraRigScript := preload("res://src/camera/camera_rig.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const GameplayModePanelScript := preload("res://src/ui/gameplay_mode_panel.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return ctx.fail("Realtime gameplay suite could not load main.tscn.")

	var main := main_scene.instantiate()
	ctx.root().add_child(main)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var editor_mode_controller := main.get_node_or_null("EditorModeController") as EditorModeControllerScript
	var gameplay_mode_controller := main.get_node_or_null("GameplayModeController") as GameplayModeControllerScript
	var realtime_controller := main.get_node_or_null("RealtimeGameplayController") as RealtimeGameplayControllerScript
	var camera_rig := main.get_node_or_null("CameraRig") as CameraRigScript
	var map_loader := main.get_node_or_null("MapLoader") as MapLoaderScript
	var gameplay_mode_panel := main.get_node_or_null(
		"InteractionUI/GameplayModePanel"
	) as GameplayModePanelScript
	if (
		editor_mode_controller == null
		or gameplay_mode_controller == null
		or realtime_controller == null
		or camera_rig == null
		or map_loader == null
		or gameplay_mode_panel == null
	):
		main.free()
		return ctx.fail("Realtime gameplay suite is missing required main-scene controllers.")

	if gameplay_mode_controller.get_active_control_mode() != GameplayModeControllerScript.CONTROL_MODE_NONE:
		main.free()
		return ctx.fail("Realtime gameplay control should be inactive during editor startup.")
	if realtime_controller.is_real_time_mode_active():
		main.free()
		return ctx.fail("RealtimeGameplayController should be disabled during editor startup.")
	if gameplay_mode_panel.visible:
		main.free()
		return ctx.fail("GameplayModePanel should be hidden outside Game mode.")

	var local_map := map_loader.get_local_map_data()
	var test_map := local_map.duplicate(true) as MapDataScript
	if test_map == null:
		main.free()
		return ctx.fail("Realtime gameplay suite could not duplicate the local map.")
	test_map.world_objects.append(WorldObjectDataScript.new(
		&"pc_000",
		&"player_character",
		Vector3(-4.0, 0.0, -4.0),
		Vector3(0.5, 1.83, 0.5),
		Color(0.2, 0.4, 1.0, 1.0),
		true,
		100.0
	))
	map_loader.replace_map_data(test_map, true)
	root_event_bus.emit_signal(&"editor_map_loaded", test_map, "")
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var editor_camera_position := camera_rig.position
	editor_mode_controller.enter_game_mode()
	await ctx.tree.process_frame
	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if gameplay_mode_controller.get_active_control_mode() != GameplayModeControllerScript.CONTROL_MODE_REAL_TIME:
		main.free()
		return ctx.fail("Game mode did not activate the real-time gameplay control mode.")
	if not realtime_controller.is_real_time_mode_active():
		main.free()
		return ctx.fail("RealtimeGameplayController did not activate in game mode.")
	if not gameplay_mode_panel.visible or gameplay_mode_panel.get_selected_mode() != GameplayModeControllerScript.CONTROL_MODE_REAL_TIME:
		main.free()
		return ctx.fail("GameplayModePanel did not show RT as the default Game mode.")
	var turn_based_button := gameplay_mode_panel.get_node_or_null(
		"ModeButtons/TurnBasedButton"
	) as Button
	var real_time_button := gameplay_mode_panel.get_node_or_null(
		"ModeButtons/RealTimeButton"
	) as Button
	if turn_based_button == null or real_time_button == null:
		main.free()
		return ctx.fail("GameplayModePanel is missing its RT/TB buttons.")
	turn_based_button.emit_signal(&"pressed")
	await ctx.tree.process_frame
	if gameplay_mode_controller.get_active_control_mode() != GameplayModeControllerScript.CONTROL_MODE_TURN_BASED:
		main.free()
		return ctx.fail("TB button request did not activate the turn-based placeholder mode.")
	if realtime_controller.is_real_time_mode_active() or camera_rig.is_realtime_follow_active():
		main.free()
		return ctx.fail("Turn-based mode did not release real-time movement and camera follow.")
	if gameplay_mode_panel.get_selected_mode() != GameplayModeControllerScript.CONTROL_MODE_TURN_BASED:
		main.free()
		return ctx.fail("GameplayModePanel did not select TB after the mode change.")
	real_time_button.emit_signal(&"pressed")
	await ctx.tree.process_frame
	await ctx.tree.process_frame
	if not realtime_controller.is_real_time_mode_active():
		main.free()
		return ctx.fail("RT button request did not restore real-time gameplay control.")

	var active_actor := realtime_controller.get_active_player_character() as BlockoutObjectViewScript
	if active_actor == null or active_actor.object_data.object_id != &"pc_000":
		main.free()
		return ctx.fail("Real-time mode did not select the earliest player-character id.")
	if not camera_rig.is_realtime_follow_active() or camera_rig.get_follow_target() != active_actor:
		main.free()
		return ctx.fail("CameraRig did not lock to the active player character.")
	camera_rig._process(0.016)
	if not _same_planar_position(camera_rig.position, active_actor.global_position):
		main.free()
		return ctx.fail("CameraRig focus was not centered on the active player character.")

	if not realtime_controller.cycle_active_player_character():
		main.free()
		return ctx.fail("Tab-style player-character cycling was rejected.")
	active_actor = realtime_controller.get_active_player_character() as BlockoutObjectViewScript
	if active_actor == null or active_actor.object_data.object_id != &"pc_001":
		main.free()
		return ctx.fail("Player-character cycling did not advance in id order.")
	camera_rig._process(0.016)
	if camera_rig.get_follow_target() != active_actor or not _same_planar_position(camera_rig.position, active_actor.global_position):
		main.free()
		return ctx.fail("CameraRig did not transfer its lock after cycling player characters.")

	var pan_press := InputEventMouseButton.new()
	pan_press.button_index = MOUSE_BUTTON_RIGHT
	pan_press.pressed = true
	pan_press.ctrl_pressed = true
	camera_rig._unhandled_input(pan_press)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.relative = Vector2(40.0, 15.0)
	camera_rig._unhandled_input(pan_motion)
	if not camera_rig.is_temporary_follow_pan_active():
		main.free()
		return ctx.fail("Ctrl+RMB did not begin temporary real-time camera panning.")
	if _same_planar_position(camera_rig.position, active_actor.global_position):
		main.free()
		return ctx.fail("Temporary real-time camera pan did not offset the camera focus.")
	var ctrl_release := InputEventKey.new()
	ctrl_release.keycode = KEY_CTRL
	ctrl_release.pressed = false
	camera_rig._input(ctrl_release)
	if camera_rig.is_temporary_follow_pan_active():
		main.free()
		return ctx.fail("Releasing Ctrl did not end temporary camera panning.")
	if not _same_planar_position(camera_rig.position, active_actor.global_position):
		main.free()
		return ctx.fail("CameraRig did not snap back to the active player character after Ctrl release.")

	if realtime_controller.movement_band_for_distance(0.25) != RealtimeGameplayControllerScript.MOVEMENT_BAND_TIPTOE:
		main.free()
		return ctx.fail("The <=0.5m direct-control band should be tiptoe.")
	if realtime_controller.movement_band_for_distance(1.0) != RealtimeGameplayControllerScript.MOVEMENT_BAND_WALK:
		main.free()
		return ctx.fail("The 0.5m-2m direct-control band should be walk.")
	if realtime_controller.movement_band_for_distance(3.0) != RealtimeGameplayControllerScript.MOVEMENT_BAND_RUN:
		main.free()
		return ctx.fail("The >2m direct-control band should be run.")

	if not realtime_controller.cycle_active_player_character():
		main.free()
		return ctx.fail("Player-character cycling did not wrap to the earliest id.")
	active_actor = realtime_controller.get_active_player_character() as BlockoutObjectViewScript
	if active_actor == null or active_actor.object_data.object_id != &"pc_000":
		main.free()
		return ctx.fail("Player-character cycling did not wrap in id order.")
	if not realtime_controller.begin_direct_movement():
		main.free()
		return ctx.fail("Held-RMB direct movement did not start in real-time mode.")
	var direct_start := active_actor.position
	if not realtime_controller.drive_active_actor_toward(direct_start + Vector3(-6.0, 0.0, 0.0), 0.5):
		main.free()
		return ctx.fail("Real-time direct movement rejected a target without navmesh validation.")
	var run_speed := realtime_controller.get_current_speed_mps()
	if active_actor.position.distance_to(direct_start) <= 0.001 or run_speed <= 0.0:
		main.free()
		return ctx.fail("Real-time direct movement did not move and accelerate the active character.")
	if active_actor.object_data.position.distance_to(active_actor.position) > 0.001:
		main.free()
		return ctx.fail("Real-time direct movement did not synchronize WorldObjectData.position.")
	realtime_controller.end_direct_movement()
	if realtime_controller.get_current_speed_mps() <= 0.0:
		main.free()
		return ctx.fail("Releasing RMB removed all inertia instead of beginning deceleration.")
	realtime_controller._physics_process(0.1)
	if realtime_controller.get_current_speed_mps() >= run_speed:
		main.free()
		return ctx.fail("Real-time direct movement did not decelerate after RMB release.")

	realtime_controller.cancel_direct_movement()
	active_actor.position = Vector3(2.4, 0.0, 0.0)
	active_actor.object_data.position = active_actor.position
	await ctx.tree.physics_frame
	if not realtime_controller.begin_direct_movement():
		main.free()
		return ctx.fail("Real-time direct movement did not restart for collision validation.")
	realtime_controller.drive_active_actor_toward(Vector3(5.0, 0.0, 0.0), 1.0)
	if active_actor.position.x > 2.8:
		main.free()
		return ctx.fail("The cylindrical actor collider passed through a static wall.")
	realtime_controller.cancel_direct_movement()
	var npc_actor := main.get_node_or_null(
		"NavigationRegion3D/GeneratedMap/WorldObjects/npc_001"
	) as BlockoutObjectViewScript
	if npc_actor == null:
		main.free()
		return ctx.fail("Realtime collision validation could not find npc_001.")
	active_actor.position = Vector3(0.0, 0.0, 0.75)
	active_actor.object_data.position = active_actor.position
	await ctx.tree.physics_frame
	realtime_controller.begin_direct_movement()
	realtime_controller.drive_active_actor_toward(Vector3(4.0, 0.0, 0.75), 1.0)
	if active_actor.position.x > 1.2:
		main.free()
		return ctx.fail("The active player cylinder passed through an NPC cylinder.")
	realtime_controller.cancel_direct_movement()

	editor_mode_controller.enter_editor_mode()
	await ctx.tree.process_frame
	if realtime_controller.is_real_time_mode_active() or realtime_controller.is_direct_movement_held():
		main.free()
		return ctx.fail("Real-time direct movement remained active after returning to editor mode.")
	if camera_rig.is_realtime_follow_active():
		main.free()
		return ctx.fail("Camera follow remained active after returning to editor mode.")
	if camera_rig.position.distance_to(editor_camera_position) > 0.001:
		main.free()
		return ctx.fail("Returning to editor mode did not restore the pre-game free camera position.")

	main.free()
	return true

func _same_planar_position(a: Vector3, b: Vector3) -> bool:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) <= 0.001
