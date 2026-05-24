extends RefCounted

const BspDebugEditorControllerScript := preload("res://src/debug/bsp_debug_editor_controller.gd")
const BspDebugMapControllerScript := preload("res://src/debug/bsp_debug_map_controller.gd")
const BspDebugPanelScript := preload("res://src/ui/bsp_debug_panel.gd")
const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const NavigationDebugOverlayScript := preload("res://src/ui/navigation_debug_overlay.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return ctx.fail("Main scene did not load for BSP debug editor check.")

	var main := main_scene.instantiate()
	ctx.root().add_child(main)
	await ctx.tree.process_frame
	await ctx.tree.physics_frame

	var editor := main.get_node_or_null("BspDebugEditorController") as BspDebugEditorControllerScript
	var controller := main.get_node_or_null("BspDebugMapController") as BspDebugMapControllerScript
	var overlay := main.get_node_or_null("NavigationDebugOverlay") as NavigationDebugOverlayScript
	var panel := main.get_node_or_null("InteractionUI/BspDebugPanel") as BspDebugPanelScript
	if editor == null or controller == null or overlay == null or panel == null:
		main.free()
		return ctx.fail("Main scene is missing BSP debug editor nodes.")

	await ctx.tree.process_frame
	await ctx.tree.physics_frame
	if not controller.is_bsp_enabled():
		main.free()
		return ctx.fail("BSP debug editor requires startup BSP debug mode.")

	var data := controller.get_generated_bsp_data()
	if data == null or data.rooms.is_empty():
		main.free()
		return ctx.fail("BSP debug editor did not receive generated BSP data.")

	var selected_room := data.rooms[0]
	if not editor.select_room_at_position(selected_room.center_position()):
		main.free()
		return ctx.fail("BSP debug editor did not select a room by position.")
	if overlay.get_selected_bsp_room_id() != selected_room.id:
		main.free()
		return ctx.fail("BSP debug overlay did not track the selected room id.")
	if overlay.get_node_or_null("BspInterestDebug/Rooms/Room_%s/SelectedRoomFill" % String(selected_room.id)) == null:
		main.free()
		return ctx.fail("BSP debug overlay did not draw selected room fill.")

	panel.set_edit_mode(BspDebugPanelScript.MODE_DOOR)
	await ctx.tree.process_frame
	if editor.get_edit_mode() != BspDebugPanelScript.MODE_DOOR:
		main.free()
		return ctx.fail("BSP debug editor did not sync Door mode from the panel.")

	var door_add := _add_manual_door_with_editor(editor, controller)
	if not bool(door_add.get("ok", false)):
		main.free()
		return ctx.fail("BSP debug editor did not add a manual door.")
	if BspRoomProcessorScript.manual_door_count(controller.get_generated_bsp_data()) != 1:
		main.free()
		return ctx.fail("BSP debug editor manual door add did not mutate generated BSP data.")
	if overlay.get_node_or_null("BspInterestDebug/Sockets") == null:
		main.free()
		return ctx.fail("BSP debug overlay did not redraw sockets after manual door add.")

	var manual_door := _first_manual_door(controller.get_generated_bsp_data())
	if manual_door == null:
		main.free()
		return ctx.fail("BSP debug editor could not find the manual door it added.")
	if not editor.toggle_manual_door_at_position(manual_door.position):
		main.free()
		return ctx.fail("BSP debug editor did not remove an existing manual door.")
	if BspRoomProcessorScript.manual_door_count(controller.get_generated_bsp_data()) != 0:
		main.free()
		return ctx.fail("BSP debug editor removed a manual door but count did not update.")

	var protected_remove := _attempt_generated_door_remove_with_editor(editor, controller)
	if bool(protected_remove.get("ok", false)):
		main.free()
		return ctx.fail("BSP debug editor should not remove or replace generated doors.")

	panel.set_edit_mode(BspDebugPanelScript.MODE_RESIZE)
	await ctx.tree.process_frame
	if editor.get_edit_mode() != BspDebugPanelScript.MODE_RESIZE:
		main.free()
		return ctx.fail("BSP debug editor did not sync Resize mode from the panel.")
	var resize_result := _resize_shared_side_with_editor(editor, controller)
	if not bool(resize_result.get("ok", false)):
		main.free()
		return ctx.fail("BSP debug editor did not resize a shared room side.")
	for room in controller.get_generated_bsp_data().rooms:
		if room.bounds.size.x < controller.get_generated_bsp_data().min_room_size_m - 0.001:
			main.free()
			return ctx.fail("BSP debug editor resize produced a room below minimum width.")
		if room.bounds.size.y < controller.get_generated_bsp_data().min_room_size_m - 0.001:
			main.free()
			return ctx.fail("BSP debug editor resize produced a room below minimum depth.")

	main.free()
	return true

func _add_manual_door_with_editor(
	editor: BspDebugEditorControllerScript,
	controller: BspDebugMapControllerScript
) -> Dictionary:
	var data := controller.get_generated_bsp_data()
	for room in data.rooms:
		if not editor.select_room_at_position(room.center_position()):
			continue
		for side in [&"north", &"east", &"south", &"west"]:
			for position in _door_candidate_positions(room, side):
				if editor.toggle_manual_door_at_position(position):
					return {
						"ok": true,
						"room_id": room.id,
					}
	return {"ok": false}

func _attempt_generated_door_remove_with_editor(
	editor: BspDebugEditorControllerScript,
	controller: BspDebugMapControllerScript
) -> Dictionary:
	var data := controller.get_generated_bsp_data()
	for socket in BspRoomProcessorScript.compile_interest_sockets(data):
		if socket.get("kind", &"") != &"door_socket" or bool(socket.get("is_manual", false)):
			continue
		var room_ids: Array = socket.get("room_ids", [])
		if room_ids.is_empty():
			continue
		var room := _room_by_id(data, room_ids[0] as StringName)
		if room == null:
			continue
		editor.select_room_at_position(room.center_position())
		var before_count := BspRoomProcessorScript.manual_door_count(data)
		var changed := editor.toggle_manual_door_at_position(socket.get("position", Vector3.ZERO) as Vector3)
		return {
			"ok": changed or BspRoomProcessorScript.manual_door_count(data) != before_count,
		}
	return {"ok": false}

func _resize_shared_side_with_editor(
	editor: BspDebugEditorControllerScript,
	controller: BspDebugMapControllerScript
) -> Dictionary:
	var data := controller.get_generated_bsp_data()
	for room in data.rooms:
		for side in [&"north", &"east", &"south", &"west"]:
			var side_info := BspRoomProcessorScript.room_side_info(data, room.id, side)
			if not bool(side_info.get("ok", false)) or bool(side_info.get("is_perimeter", false)):
				continue
			editor.select_room_at_position(room.center_position())
			var center := side_info.get("position", room.center_position()) as Vector3
			for delta in [1.0, -1.0]:
				var target := center
				if int(side_info.get("axis", -1)) == BspRoomProcessorScript.SPLIT_X:
					target.x += delta
				else:
					target.z += delta
				if editor.resize_selected_side_to_position(side, target):
					return {
						"ok": true,
						"room_id": room.id,
						"side": side,
					}
	return {"ok": false}

func _first_manual_door(data: BspModuleDataScript) -> BspModuleDataScript.BspDoor:
	for door in data.doors:
		if door.is_manual:
			return door
	return null

func _room_by_id(data: BspModuleDataScript, room_id: StringName) -> BspModuleDataScript.BspRoom:
	for room in data.rooms:
		if room.id == room_id:
			return room
	return null

func _door_candidate_positions(room: BspModuleDataScript.BspRoom, side: StringName) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var x0 := room.bounds.position.x
	var x1 := room.bounds.end.x
	var z0 := room.bounds.position.y
	var z1 := room.bounds.end.y
	for ratio in [0.25, 0.75, 0.5]:
		match side:
			&"north":
				positions.append(Vector3(lerpf(x0, x1, ratio), 0.0, z0))
			&"east":
				positions.append(Vector3(x1, 0.0, lerpf(z0, z1, ratio)))
			&"west":
				positions.append(Vector3(x0, 0.0, lerpf(z0, z1, ratio)))
			_:
				positions.append(Vector3(lerpf(x0, x1, ratio), 0.0, z1))
	return positions
