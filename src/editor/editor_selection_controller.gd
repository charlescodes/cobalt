class_name EditorSelectionController
extends Node

const EditorSelectionHighlighterScript := preload("res://src/editor/editor_selection_highlighter.gd")
const DoorSocketDataScript := preload("res://src/environment/door_socket_data.gd")
const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MapLoaderScript := preload("res://src/maps/map_loader.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const TOOL_SELECT_INSPECT: StringName = &"select_inspect"
const TOOL_NPC_BRUSH: StringName = &"npc_brush"
const TOOL_PC_BRUSH: StringName = &"pc_brush"
const TOOL_WALL_BRUSH: StringName = &"wall_brush"
const TOOL_DOOR_BRUSH: StringName = &"door_brush"
const WALL_BRUSH_MODE_LINE: StringName = &"line"
const WALL_BRUSH_MODE_RECTANGLE: StringName = &"rectangle"
const PC_KIND: StringName = &"player_character"
const PC_SIZE_M: Vector3 = Vector3(0.5, 1.83, 0.5)
const PC_COLOR: Color = Color(0.1, 0.25, 1.0, 1.0)
const NPC_KIND: StringName = &"non_player_character"
const NPC_SIZE_M: Vector3 = Vector3(0.5, 1.83, 0.5)
const NPC_COLOR: Color = Color(0.45, 0.45, 0.45, 1.0)
const WALL_HEIGHT_M: float = 2.2
const WALL_THICKNESS_M: float = 0.18
const WALL_COLOR: Color = Color(0.35, 0.34, 0.32, 1.0)
const MIN_WALL_LENGTH_M: float = 0.01
const DOOR_SOCKET_WIDTH_M: float = 1.0
const DOOR_SOCKET_EDGE_CLEARANCE_M: float = 0.5
const DOOR_SOCKET_SNAP_DISTANCE_M: float = 0.75
const DOOR_SOCKET_COLOR: Color = Color(0.82, 0.9, 0.84, 1.0)

@export var camera_path: NodePath = ^"../CameraRig/PitchPivot/Camera3D"
@export var map_loader_path: NodePath = ^"../MapLoader"
@export_range(1.0, 500.0, 1.0) var max_ray_distance_m: float = 100.0
@export_flags_3d_physics var collision_mask: int = 1

var _camera: Camera3D
var _is_editor_mode: bool = false
var _active_tool: StringName = TOOL_SELECT_INSPECT
var _wall_brush_mode: StringName = WALL_BRUSH_MODE_LINE
var _has_wall_brush_start: bool = false
var _wall_brush_start_position: Vector3 = Vector3.ZERO
var _selected_node: Node
var _selected_data: Resource
var _selected_kind: StringName = &""
var _highlighter: EditorSelectionHighlighterScript

func _ready() -> void:
	_camera = _resolve_camera()
	_highlighter = EditorSelectionHighlighterScript.new()
	_highlighter.name = "EditorSelectionHighlighter"
	add_child(_highlighter)

	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	var mode_callable := Callable(self, "_on_editor_mode_changed")
	var map_loaded_callable := Callable(self, "_on_editor_map_loaded")
	var tool_callable := Callable(self, "_on_editor_tool_changed")
	var wall_mode_callable := Callable(self, "_on_editor_wall_brush_mode_changed")
	if event_bus.has_signal(&"editor_mode_changed") and not event_bus.is_connected(&"editor_mode_changed", mode_callable):
		event_bus.connect(&"editor_mode_changed", mode_callable)
	if event_bus.has_signal(&"editor_map_loaded") and not event_bus.is_connected(&"editor_map_loaded", map_loaded_callable):
		event_bus.connect(&"editor_map_loaded", map_loaded_callable)
	if event_bus.has_signal(&"editor_tool_changed") and not event_bus.is_connected(&"editor_tool_changed", tool_callable):
		event_bus.connect(&"editor_tool_changed", tool_callable)
	if event_bus.has_signal(&"editor_wall_brush_mode_changed") and not event_bus.is_connected(&"editor_wall_brush_mode_changed", wall_mode_callable):
		event_bus.connect(&"editor_wall_brush_mode_changed", wall_mode_callable)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_editor_mode:
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if _active_tool == TOOL_NPC_BRUSH:
			place_npc_at_screen(mouse_event.position)
		elif _active_tool == TOOL_PC_BRUSH:
			place_pc_at_screen(mouse_event.position)
		elif _active_tool == TOOL_WALL_BRUSH:
			add_wall_brush_point_at_screen(mouse_event.position)
		elif _active_tool == TOOL_DOOR_BRUSH:
			place_door_socket_at_screen(mouse_event.position)
		else:
			select_at_screen(mouse_event.position)
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func get_active_tool() -> StringName:
	return _active_tool

func get_wall_brush_mode() -> StringName:
	return _wall_brush_mode

func has_pending_wall_brush_point() -> bool:
	return _has_wall_brush_start

func select_at_screen(screen_position: Vector2) -> bool:
	if not _is_editor_mode:
		return false

	var hit := _raycast_editor_selectable_at(screen_position)
	if hit.is_empty():
		clear_selection()
		return false

	_set_selection(
		hit.get("node") as Node,
		hit.get("data") as Resource,
		hit.get("kind", &"") as StringName
	)
	return true

func place_npc_at_screen(screen_position: Vector2) -> WorldObjectDataScript:
	if not _is_editor_mode:
		return null

	var hit := _raycast_editor_selectable_at(screen_position)
	if hit.is_empty() or hit.get("kind", &"") != MapBuilderScript.EDITOR_KIND_GROUND:
		return null

	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		return null

	var placement_position: Vector3 = hit.get("position", Vector3.ZERO)
	placement_position.y = 0.0
	var object_data := WorldObjectDataScript.new(
		_next_npc_id(map_loader.map_data),
		NPC_KIND,
		placement_position,
		NPC_SIZE_M,
		NPC_COLOR,
		true
	)
	map_loader.map_data.world_objects.append(object_data)
	map_loader.replace_map_data(map_loader.map_data, true)
	clear_selection()
	return object_data

func place_pc_at_screen(screen_position: Vector2) -> WorldObjectDataScript:
	if not _is_editor_mode:
		return null

	var hit := _raycast_editor_selectable_at(screen_position)
	if hit.is_empty() or hit.get("kind", &"") != MapBuilderScript.EDITOR_KIND_GROUND:
		return null

	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		return null

	var placement_position: Vector3 = hit.get("position", Vector3.ZERO)
	placement_position.y = 0.0
	var object_data := WorldObjectDataScript.new(
		_next_pc_id(map_loader.map_data),
		PC_KIND,
		placement_position,
		PC_SIZE_M,
		PC_COLOR,
		true
	)
	map_loader.map_data.world_objects.append(object_data)
	map_loader.replace_map_data(map_loader.map_data, true)
	clear_selection()
	return object_data

func place_door_socket_at_screen(screen_position: Vector2) -> DoorSocketDataScript:
	if not _is_editor_mode:
		return null

	var hit := _raycast_editor_selectable_at(screen_position)
	if hit.is_empty():
		return null

	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		return null

	var click_position := _floor_plane_position(hit.get("position", Vector3.ZERO))
	var placement := _door_socket_placement_for_position(map_loader.map_data, click_position)
	if placement.is_empty():
		return null

	var wall_index := int(placement.get("wall_index", -1))
	if wall_index < 0 or wall_index >= map_loader.map_data.static_walls.size():
		return null

	var wall_data := map_loader.map_data.static_walls[wall_index]
	var socket_position: Vector3 = placement.get("position", Vector3.ZERO)
	var direction: Vector3 = placement.get("direction", Vector3.FORWARD)
	var replacement_walls := _wall_segments_after_door_gap(
		wall_data,
		socket_position,
		direction,
		DOOR_SOCKET_WIDTH_M
	)
	if replacement_walls.size() != 2:
		return null

	var socket_data := DoorSocketDataScript.new(
		_next_door_socket_id(map_loader.map_data),
		socket_position,
		DOOR_SOCKET_WIDTH_M,
		atan2(direction.x, direction.z),
		DOOR_SOCKET_COLOR
	)

	map_loader.map_data.static_walls.remove_at(wall_index)
	for replacement_index in range(replacement_walls.size()):
		map_loader.map_data.static_walls.insert(wall_index + replacement_index, replacement_walls[replacement_index])
	map_loader.map_data.door_sockets.append(socket_data)
	map_loader.replace_map_data(map_loader.map_data, true)
	clear_selection()
	return socket_data

func add_wall_brush_point_at_screen(screen_position: Vector2) -> Array[WallDataScript]:
	var added_walls: Array[WallDataScript] = []
	if not _is_editor_mode:
		return added_walls

	var hit := _raycast_editor_ground_at(screen_position)
	if hit.is_empty():
		return added_walls

	var clicked_position := _floor_plane_position(hit.get("position", Vector3.ZERO))
	if not _has_wall_brush_start:
		_wall_brush_start_position = clicked_position
		_has_wall_brush_start = true
		clear_selection()
		return added_walls

	var start_position := _wall_brush_start_position
	_clear_wall_brush_points()
	if _wall_brush_mode == WALL_BRUSH_MODE_RECTANGLE:
		added_walls = _rectangle_walls_from_points(start_position, clicked_position)
	else:
		var wall := _wall_from_points(start_position, clicked_position)
		if wall != null:
			added_walls.append(wall)

	if added_walls.is_empty():
		clear_selection()
		return added_walls

	var map_loader := _resolve_map_loader()
	if map_loader == null or map_loader.map_data == null:
		added_walls.clear()
		clear_selection()
		return added_walls

	for wall_data in added_walls:
		map_loader.map_data.static_walls.append(wall_data)
	map_loader.replace_map_data(map_loader.map_data, true)
	clear_selection()
	return added_walls

func clear_selection() -> void:
	if _selected_node == null and _selected_data == null and _selected_kind == &"":
		return

	_selected_node = null
	_selected_data = null
	_selected_kind = &""
	if _highlighter != null:
		_highlighter.clear()
	_emit_selection_changed()

func get_selected_node() -> Node:
	return _selected_node

func get_selected_data() -> Resource:
	return _selected_data

func get_selected_kind() -> StringName:
	return _selected_kind

func _set_selection(selected_node: Node, selected_data: Resource, selected_kind: StringName) -> void:
	_selected_node = selected_node
	_selected_data = selected_data
	_selected_kind = selected_kind
	if _highlighter != null:
		_highlighter.highlight(_selected_node)
	_emit_selection_changed()

func _raycast_editor_selectable_at(screen_position: Vector2) -> Dictionary:
	return _raycast_editor_selectable_matching(screen_position, &"")

func _raycast_editor_ground_at(screen_position: Vector2) -> Dictionary:
	return _raycast_editor_selectable_matching(screen_position, MapBuilderScript.EDITOR_KIND_GROUND)

func _raycast_editor_selectable_matching(screen_position: Vector2, required_kind: StringName) -> Dictionary:
	if _camera == null:
		_camera = _resolve_camera()
		if _camera == null:
			return {}

	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + (_camera.project_ray_normal(screen_position) * max_ray_distance_m)
	var excluded: Array[RID] = []

	for _attempt in range(32):
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, collision_mask)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = excluded

		var result := _camera.get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			return {}

		var collider := result.get("collider") as Object
		var selectable := _find_editor_selectable(collider)
		if not selectable.is_empty():
			var selectable_kind: StringName = selectable.get("kind", &"") as StringName
			if required_kind == &"" or selectable_kind == required_kind:
				selectable["position"] = result.get("position", Vector3.ZERO)
				return selectable

		var collision_object := collider as CollisionObject3D
		if collision_object == null:
			return {}
		excluded.append(collision_object.get_rid())

	return {}

func _find_editor_selectable(collider: Object) -> Dictionary:
	var node := collider as Node
	while node != null:
		if node.has_meta(MapBuilderScript.EDITOR_KIND_META):
			var root := node.get_meta(MapBuilderScript.EDITOR_ROOT_META, node) as Node
			var data := node.get_meta(MapBuilderScript.EDITOR_SOURCE_META, null) as Resource
			var kind_value: Variant = node.get_meta(MapBuilderScript.EDITOR_KIND_META, &"")
			var kind: StringName = kind_value if kind_value is StringName else StringName(str(kind_value))
			return {
				"node": root if root != null else node,
				"data": data,
				"kind": kind,
			}

		node = node.get_parent()

	return {}

func _on_editor_mode_changed(mode: StringName) -> void:
	_is_editor_mode = mode == &"editor"
	if not _is_editor_mode:
		_clear_wall_brush_points()
		clear_selection()

func _on_editor_map_loaded(_map_data: Resource, _path: String) -> void:
	_clear_wall_brush_points()
	clear_selection()

func _on_editor_tool_changed(tool_id: StringName) -> void:
	if (
		tool_id == TOOL_SELECT_INSPECT
		or tool_id == TOOL_NPC_BRUSH
		or tool_id == TOOL_PC_BRUSH
		or tool_id == TOOL_WALL_BRUSH
		or tool_id == TOOL_DOOR_BRUSH
	):
		_active_tool = tool_id
		if _active_tool != TOOL_WALL_BRUSH:
			_clear_wall_brush_points()

func _on_editor_wall_brush_mode_changed(mode: StringName) -> void:
	if mode != WALL_BRUSH_MODE_LINE and mode != WALL_BRUSH_MODE_RECTANGLE:
		return

	_wall_brush_mode = mode
	_clear_wall_brush_points()

func _resolve_camera() -> Camera3D:
	var configured_camera := get_node_or_null(camera_path) as Camera3D
	if configured_camera != null:
		return configured_camera

	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null

func _resolve_map_loader() -> MapLoaderScript:
	return get_node_or_null(map_loader_path) as MapLoaderScript

func _next_npc_id(map_data: MapDataScript) -> StringName:
	var index := 1
	while _object_id_exists(map_data, StringName("npc_%03d" % index)):
		index += 1

	return StringName("npc_%03d" % index)

func _object_id_exists(map_data: MapDataScript, object_id: StringName) -> bool:
	for world_object in map_data.world_objects:
		if world_object != null and world_object.object_id == object_id:
			return true

	return false

func _next_pc_id(map_data: MapDataScript) -> StringName:
	var index := 1
	while _object_id_exists(map_data, StringName("pc_%03d" % index)):
		index += 1

	return StringName("pc_%03d" % index)

func _next_door_socket_id(map_data: MapDataScript) -> StringName:
	var index := 1
	while _door_socket_id_exists(map_data, StringName("door_socket_%03d" % index)):
		index += 1

	return StringName("door_socket_%03d" % index)

func _door_socket_id_exists(map_data: MapDataScript, socket_id: StringName) -> bool:
	for socket in map_data.door_sockets:
		if socket != null and socket.socket_id == socket_id:
			return true

	return false

func _floor_plane_position(position: Vector3) -> Vector3:
	return Vector3(position.x, 0.0, position.z)

func _wall_from_points(start_position: Vector3, end_position: Vector3) -> WallDataScript:
	var clean_start := _floor_plane_position(start_position)
	var clean_end := _floor_plane_position(end_position)
	if clean_start.distance_to(clean_end) <= MIN_WALL_LENGTH_M:
		return null

	return WallDataScript.new(
		clean_start,
		clean_end,
		WALL_HEIGHT_M,
		WALL_THICKNESS_M,
		WALL_COLOR
	)

func _wall_segments_after_door_gap(
	wall_data: WallDataScript,
	socket_position: Vector3,
	direction: Vector3,
	socket_width_m: float
) -> Array[WallDataScript]:
	var wall_segments: Array[WallDataScript] = []
	if wall_data == null or direction.length_squared() <= 0.000001:
		return wall_segments

	var clean_start := _floor_plane_position(wall_data.start_position)
	var clean_end := _floor_plane_position(wall_data.end_position)
	var half_width := socket_width_m * 0.5
	var gap_start := _floor_plane_position(socket_position - (direction * half_width))
	var gap_end := _floor_plane_position(socket_position + (direction * half_width))
	_append_wall_like(wall_segments, wall_data, clean_start, gap_start)
	_append_wall_like(wall_segments, wall_data, gap_end, clean_end)
	return wall_segments

func _rectangle_walls_from_points(start_position: Vector3, end_position: Vector3) -> Array[WallDataScript]:
	var walls: Array[WallDataScript] = []
	var clean_start := _floor_plane_position(start_position)
	var clean_end := _floor_plane_position(end_position)
	if (
		absf(clean_start.x - clean_end.x) <= MIN_WALL_LENGTH_M
		or absf(clean_start.z - clean_end.z) <= MIN_WALL_LENGTH_M
	):
		return walls

	var corner_a := Vector3(clean_start.x, 0.0, clean_start.z)
	var corner_b := Vector3(clean_end.x, 0.0, clean_start.z)
	var corner_c := Vector3(clean_end.x, 0.0, clean_end.z)
	var corner_d := Vector3(clean_start.x, 0.0, clean_end.z)
	_append_wall_if_valid(walls, corner_a, corner_b)
	_append_wall_if_valid(walls, corner_b, corner_c)
	_append_wall_if_valid(walls, corner_c, corner_d)
	_append_wall_if_valid(walls, corner_d, corner_a)
	return walls

func _append_wall_if_valid(
	walls: Array[WallDataScript],
	start_position: Vector3,
	end_position: Vector3
) -> void:
	var wall := _wall_from_points(start_position, end_position)
	if wall != null:
		walls.append(wall)

func _append_wall_like(
	walls: Array[WallDataScript],
	template_wall: WallDataScript,
	start_position: Vector3,
	end_position: Vector3
) -> void:
	var clean_start := _floor_plane_position(start_position)
	var clean_end := _floor_plane_position(end_position)
	if clean_start.distance_to(clean_end) <= MIN_WALL_LENGTH_M:
		return

	walls.append(WallDataScript.new(
		clean_start,
		clean_end,
		template_wall.height_m,
		template_wall.thickness_m,
		template_wall.color
	))

func _door_socket_placement_for_position(map_data: MapDataScript, click_position: Vector3) -> Dictionary:
	var best_placement := {}
	var best_distance := INF
	for wall_index in range(map_data.static_walls.size()):
		var wall_data := map_data.static_walls[wall_index]
		var placement := _door_socket_placement_on_wall(wall_data, wall_index, click_position)
		if placement.is_empty():
			continue

		var snap_distance := float(placement.get("snap_distance", INF))
		var socket_position: Vector3 = placement.get("position", Vector3.ZERO)
		if (
			snap_distance < best_distance
			and not _door_socket_overlaps_existing(map_data, socket_position, DOOR_SOCKET_WIDTH_M)
		):
			best_distance = snap_distance
			best_placement = placement

	return best_placement

func _door_socket_placement_on_wall(
	wall_data: WallDataScript,
	wall_index: int,
	click_position: Vector3
) -> Dictionary:
	if wall_data == null or not wall_data.is_valid_wall():
		return {}

	var start_position := _floor_plane_position(wall_data.start_position)
	var end_position := _floor_plane_position(wall_data.end_position)
	var wall_delta := end_position - start_position
	var wall_length := wall_delta.length()
	var minimum_center_offset := (DOOR_SOCKET_WIDTH_M * 0.5) + DOOR_SOCKET_EDGE_CLEARANCE_M
	if wall_length < minimum_center_offset * 2.0:
		return {}

	var direction := wall_delta / wall_length
	var relative_click := _floor_plane_position(click_position) - start_position
	var raw_distance_along_wall := relative_click.dot(direction)
	var closest_distance_along_wall := clampf(raw_distance_along_wall, 0.0, wall_length)
	var closest_point := start_position + (direction * closest_distance_along_wall)
	var snap_distance := _floor_plane_position(click_position).distance_to(closest_point)
	if snap_distance > DOOR_SOCKET_SNAP_DISTANCE_M:
		return {}

	var socket_distance_along_wall := clampf(
		raw_distance_along_wall,
		minimum_center_offset,
		wall_length - minimum_center_offset
	)
	return {
		"wall_index": wall_index,
		"position": start_position + (direction * socket_distance_along_wall),
		"direction": direction,
		"snap_distance": snap_distance,
	}

func _door_socket_overlaps_existing(
	map_data: MapDataScript,
	socket_position: Vector3,
	socket_width_m: float
) -> bool:
	for existing_socket in map_data.door_sockets:
		if existing_socket == null:
			continue

		var existing_position := _floor_plane_position(existing_socket.position)
		var minimum_distance := (existing_socket.width_m + socket_width_m) * 0.5
		if existing_position.distance_to(_floor_plane_position(socket_position)) < minimum_distance:
			return true

	return false

func _clear_wall_brush_points() -> void:
	_has_wall_brush_start = false
	_wall_brush_start_position = Vector3.ZERO

func _emit_selection_changed() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal(&"editor_selection_changed", _selected_node, _selected_data, _selected_kind)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
