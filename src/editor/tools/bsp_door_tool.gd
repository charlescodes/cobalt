class_name BspDoorTool
extends "res://src/editor/tools/editor_tool.gd"

const BspEditorContextScript := preload("res://src/editor/tools/bsp_editor_context.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")
const BspRoomSelectToolScript := preload("res://src/editor/tools/bsp_room_select_tool.gd")
const EditorSnappingResolverScript := preload("res://src/editor/editor_snapping_resolver.gd")

const DOOR_CONTEXT_PICK_DISTANCE_M: float = 0.75

var _context: BspEditorContextScript
var _select_tool: BspRoomSelectToolScript

func _init(
	context: BspEditorContextScript = null,
	select_tool: BspRoomSelectToolScript = null
) -> void:
	_context = context
	_select_tool = select_tool

func set_context(context: BspEditorContextScript) -> void:
	_context = context

func set_select_tool(select_tool: BspRoomSelectToolScript) -> void:
	_select_tool = select_tool

func activate(_editor_controller: Node) -> void:
	if _context != null:
		_context.lock_current_selection()

func on_cancel(_modifiers: Dictionary) -> void:
	if _context != null:
		_context.clear_selection_context()

func on_left_click_down(raycast_hit: Vector3, _modifiers: Dictionary) -> void:
	if _context == null:
		return

	if _context.get_selected_room_id() == &"":
		_lock_room_at_position(raycast_hit)
		return

	if not _context.is_selection_context_locked():
		_context.lock_current_selection()
	if _is_outside_locked_room_context(raycast_hit):
		_context.clear_selection_context()
		return

	toggle_manual_door_at_position(raycast_hit)

func uses_snapping_grid() -> bool:
	return true

func get_snapping_context(_raw_pos: Vector3, _modifiers: Dictionary) -> Dictionary:
	if _context == null:
		return {}

	var data := _context.current_bsp_data()
	var room_id := _context.get_selected_room_id()
	if data == null or room_id == &"":
		return {&"elevation_y": 0.0}

	var wall_segments: Array[Dictionary] = []
	for side in [&"north", &"east", &"south", &"west"]:
		var side_info := BspRoomProcessorScript.room_side_info(data, room_id, side)
		if not bool(side_info.get("ok", false)):
			continue
		wall_segments.append({
			&"start": side_info.get("start", Vector3.ZERO) as Vector3,
			&"end": side_info.get("end", Vector3.ZERO) as Vector3,
		})

	return {
		&"elevation_y": 0.0,
		&"wall_segments": wall_segments,
		&"wall_snap_distance_m": DOOR_CONTEXT_PICK_DISTANCE_M,
	}

func toggle_manual_door_at_position(position: Vector3) -> bool:
	if _context == null:
		return false

	var data := _context.current_bsp_data()
	if data == null or _context.get_selected_room_id() == &"":
		return false
	if not _context.is_selection_context_locked():
		_context.lock_current_selection()
	if _is_outside_locked_room_context(position):
		_context.clear_selection_context()
		return false

	var snapped_position := EditorSnappingResolverScript.snap_with_context(
		position,
		get_snapping_context(position, {}),
		get_snapping_step()
	)
	var result := BspRoomProcessorScript.toggle_manual_door_at_position(
		data,
		_context.get_selected_room_id(),
		snapped_position,
		DOOR_CONTEXT_PICK_DISTANCE_M
	)
	if not bool(result.get("ok", false)):
		return false

	return _context.commit_edits()

func _lock_room_at_position(position: Vector3) -> bool:
	if _context == null:
		return false

	var data := _context.current_bsp_data()
	if data == null:
		_context.clear_selection_context()
		return false

	var room := BspRoomProcessorScript.room_at_position(data, position)
	if room != null:
		_context.lock_selected_room_id(room.id)
		return true

	var side_info := _nearest_room_side_at_position(data, position, DOOR_CONTEXT_PICK_DISTANCE_M)
	if bool(side_info.get("ok", false)):
		_context.lock_selected_room_id(side_info.get("room_id", &"") as StringName)
		return _context.get_selected_room_id() != &""

	_context.clear_selection_context()
	return false

func _is_outside_locked_room_context(position: Vector3) -> bool:
	if _context == null or not _context.is_selection_context_locked():
		return false

	var data := _context.current_bsp_data()
	var room_id := _context.get_selected_room_id()
	if data == null or room_id == &"":
		return true

	var side_info := BspRoomProcessorScript.nearest_room_side(
		data,
		room_id,
		position,
		DOOR_CONTEXT_PICK_DISTANCE_M
	)
	if bool(side_info.get("ok", false)):
		return false

	var room := BspRoomProcessorScript.room_at_position(data, position)
	return room == null or room.id != room_id

func _nearest_room_side_at_position(
	data,
	position: Vector3,
	max_distance_m: float
) -> Dictionary:
	var best := {}
	var best_distance := INF
	for room in data.rooms:
		var candidate := BspRoomProcessorScript.nearest_room_side(
			data,
			room.id,
			position,
			max_distance_m
		)
		if not bool(candidate.get("ok", false)):
			continue

		var distance := float(candidate.get("distance_m", INF))
		if distance < best_distance:
			best = candidate
			best_distance = distance

	if best.is_empty() or best_distance > max_distance_m:
		return {"ok": false, "reason": &"side_not_found"}

	best["ok"] = true
	return best
