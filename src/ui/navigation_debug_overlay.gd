class_name NavigationDebugOverlay
extends Node3D

const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")
const BspRoomProcessorScript := preload("res://src/debug/bsp_room_processor.gd")

const PATH_ROOT_NAME: StringName = &"PathDebug"
const MARKER_ROOT_NAME: StringName = &"MarkerDebug"
const BSP_ROOT_NAME: StringName = &"BspInterestDebug"
const EDITOR_SNAP_ROOT_NAME: StringName = &"EditorSnapDebug"
const BSP_EDITOR_HOVER_ROOT_NAME: StringName = &"BspEditorHoverDebug"
const PATH_LINE_NAME: StringName = &"PathLine"
const DESTINATION_MARKER_NAME: StringName = &"DestinationMarker"
const FAILURE_MARKER_NAME: StringName = &"FailureMarker"
const DRAW_Y_OFFSET_M: float = 0.06
const BSP_DRAW_Y_OFFSET_M: float = 0.08
const BSP_ROUTE_Y_OFFSET_M: float = 0.14
const EDITOR_SNAP_DRAW_Y_OFFSET_M: float = 0.16
const BSP_HOVER_DRAW_Y_OFFSET_M: float = 0.22

@export var waypoint_radius_m: float = 0.08
@export var destination_radius_m: float = 0.12
@export var failure_radius_m: float = 0.14
@export var show_bsp_interest_debug: bool = true
@export var show_bsp_exit_route: bool = true
@export var show_editor_snap_grid: bool = true
@export_range(0.2, 2.0, 0.1) var editor_snap_grid_radius_m: float = 0.6

var _path_root: Node3D
var _marker_root: Node3D
var _bsp_root: Node3D
var _editor_snap_root: Node3D
var _bsp_editor_hover_root: Node3D
var _bsp_data: BspModuleDataScript
var _selected_bsp_room_id: StringName = &""
var _last_requested_position: Vector3 = Vector3.ZERO
var _has_last_requested_position: bool = false

func _ready() -> void:
	visible = false
	_path_root = _get_or_create_root(PATH_ROOT_NAME)
	_marker_root = _get_or_create_root(MARKER_ROOT_NAME)
	_bsp_root = _get_or_create_root(BSP_ROOT_NAME)
	_editor_snap_root = _get_or_create_root(EDITOR_SNAP_ROOT_NAME)
	_bsp_editor_hover_root = _get_or_create_root(BSP_EDITOR_HOVER_ROOT_NAME)
	_connect_events()

func set_bsp_debug_data(data: BspModuleDataScript) -> void:
	_bsp_data = data
	if _bsp_data == null:
		_selected_bsp_room_id = &""
	_redraw_bsp_interest_debug()

func clear_bsp_debug_data() -> void:
	_bsp_data = null
	_selected_bsp_room_id = &""
	_clear_bsp_interest_debug()
	clear_bsp_editor_hover_segment()

func set_selected_bsp_room_id(room_id: StringName) -> void:
	if _selected_bsp_room_id == room_id:
		return

	_selected_bsp_room_id = room_id
	_redraw_bsp_interest_debug()

func get_selected_bsp_room_id() -> StringName:
	return _selected_bsp_room_id

func set_bsp_interest_visible(is_visible: bool) -> void:
	if show_bsp_interest_debug == is_visible:
		return

	show_bsp_interest_debug = is_visible
	_redraw_bsp_interest_debug()
	if not show_bsp_interest_debug:
		clear_bsp_editor_hover_segment()

func set_bsp_exit_route_visible(is_visible: bool) -> void:
	if show_bsp_exit_route == is_visible:
		return

	show_bsp_exit_route = is_visible
	_redraw_bsp_interest_debug()

func set_editor_snap_grid_cursor(
	_raw_position: Vector3,
	snapped_position: Vector3,
	step_m: float = 0.1
) -> void:
	clear_editor_snap_grid()
	if not show_editor_snap_grid or step_m <= 0.0:
		return

	if _editor_snap_root == null:
		_editor_snap_root = _get_or_create_root(EDITOR_SNAP_ROOT_NAME)

	var cloud := _new_snap_point_cloud(snapped_position, step_m)
	if cloud != null:
		_editor_snap_root.add_child(cloud)
	_editor_snap_root.add_child(_new_snap_cursor_marker(snapped_position))

func clear_editor_snap_grid() -> void:
	if _editor_snap_root == null:
		_editor_snap_root = _get_or_create_root(EDITOR_SNAP_ROOT_NAME)
	for child in _editor_snap_root.get_children():
		child.free()

func set_bsp_editor_hover_segment(target: Dictionary) -> void:
	clear_bsp_editor_hover_segment()
	if target.is_empty():
		return
	if not show_bsp_interest_debug:
		return

	var start_value: Variant = target.get(&"start")
	var end_value: Variant = target.get(&"end")
	if not (start_value is Vector3) or not (end_value is Vector3):
		return

	if _bsp_editor_hover_root == null:
		_bsp_editor_hover_root = _get_or_create_root(BSP_EDITOR_HOVER_ROOT_NAME)

	var segment := _new_segment_bar(
		"HoverSegment",
		start_value as Vector3,
		end_value as Vector3,
		0.14,
		0.045,
		Color(0.08, 1.0, 0.9, 0.95),
		BSP_HOVER_DRAW_Y_OFFSET_M
	)
	_bsp_editor_hover_root.add_child(segment)

func clear_bsp_editor_hover_segment() -> void:
	if _bsp_editor_hover_root == null:
		_bsp_editor_hover_root = _get_or_create_root(BSP_EDITOR_HOVER_ROOT_NAME)
	for child in _bsp_editor_hover_root.get_children():
		child.free()

func _on_move_requested(_actor: Node, _actor_data: Resource, destination_data: Resource) -> void:
	var destination_position: Variant = _position_from_resource(destination_data)
	if destination_position == null:
		_has_last_requested_position = false
		return

	_last_requested_position = destination_position
	_has_last_requested_position = true
	_draw_destination_marker(_last_requested_position)

func _on_movement_started(_actor: Node, path: PackedVector3Array) -> void:
	_clear_path()
	_clear_failure_marker()
	_draw_path(path)
	if _has_last_requested_position:
		_draw_destination_marker(_last_requested_position)
	elif not path.is_empty():
		_draw_destination_marker(path[path.size() - 1])

func _on_movement_failed(
	_actor: Node,
	destination_data: Resource,
	_reason: StringName
) -> void:
	var failure_position: Variant = _position_from_resource(destination_data)
	if failure_position != null:
		_clear_path()
		_clear_failure_marker()
		_draw_failure_marker(failure_position)

func _on_interaction_targeting_failed(
	_source: Node,
	target: Node,
	_action_id: StringName,
	_reason: StringName,
	details: Dictionary
) -> void:
	var failure_position: Variant = _position_from_target(target)
	if failure_position == null:
		failure_position = _position_from_details(details)
	if failure_position != null:
		_clear_path()
		_clear_failure_marker()
		_draw_failure_marker(failure_position)

func _draw_path(path: PackedVector3Array) -> void:
	if path.is_empty():
		return

	if path.size() > 1:
		var line := MeshInstance3D.new()
		line.name = String(PATH_LINE_NAME)
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(Color(0.2, 0.85, 1.0, 0.95)))
		for point_index in range(path.size() - 1):
			mesh.surface_add_vertex(_draw_position(path[point_index]))
			mesh.surface_add_vertex(_draw_position(path[point_index + 1]))
		mesh.surface_end()
		line.mesh = mesh
		_path_root.add_child(line)

	for point_index in range(path.size()):
		_path_root.add_child(_new_marker(
			"Waypoint_%02d" % point_index,
			path[point_index],
			waypoint_radius_m,
			Color(0.35, 0.9, 1.0, 0.95)
		))

func _draw_destination_marker(position: Vector3) -> void:
	_remove_marker(DESTINATION_MARKER_NAME)
	_marker_root.add_child(_new_marker(
		String(DESTINATION_MARKER_NAME),
		position,
		destination_radius_m,
		Color(0.95, 0.85, 0.25, 0.95)
	))

func _draw_failure_marker(position: Vector3) -> void:
	_remove_marker(FAILURE_MARKER_NAME)
	_marker_root.add_child(_new_marker(
		String(FAILURE_MARKER_NAME),
		position,
		failure_radius_m,
		Color(1.0, 0.18, 0.12, 0.95)
	))

func _new_marker(marker_name: String, position: Vector3, radius_m: float, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	marker.position = _draw_position(position)
	var sphere := SphereMesh.new()
	sphere.radius = radius_m
	sphere.height = radius_m * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	marker.mesh = sphere
	marker.material_override = _material(color)
	return marker

func _redraw_bsp_interest_debug() -> void:
	_clear_bsp_interest_debug()
	if _bsp_data == null or not show_bsp_interest_debug:
		return

	var data := _bsp_data if _bsp_data.root_node != null else BspRoomProcessorScript.generate(_bsp_data)
	_draw_bsp_rooms(data)
	_draw_bsp_walls(data)
	_draw_bsp_sockets(data)
	if show_bsp_exit_route:
		_draw_bsp_exit_route(data)

func _draw_bsp_rooms(data: BspModuleDataScript) -> void:
	var rooms_root := _new_debug_root("Rooms")
	for room in data.rooms:
		var room_root := Node3D.new()
		room_root.name = "Room_%s" % _debug_name(room.id)
		rooms_root.add_child(room_root)
		var is_selected := room.id == _selected_bsp_room_id
		if is_selected:
			room_root.add_child(_new_room_fill(room.bounds, Color(0.45, 0.7, 1.0, 0.22)))
		_add_rect_outline(
			room_root,
			room.bounds,
			Color(0.95, 0.95, 0.28, 0.95) if is_selected else Color(0.2, 0.75, 1.0, 0.82),
			0.08 if is_selected else 0.045,
			0.035 if is_selected else 0.025,
			BSP_DRAW_Y_OFFSET_M
		)

func _draw_bsp_walls(data: BspModuleDataScript) -> void:
	var walls_root := _new_debug_root("Walls")
	var walls := BspRoomProcessorScript.compile_to_walls(data)
	for wall_index in range(walls.size()):
		walls_root.add_child(_new_segment_bar(
			"Wall_%02d" % wall_index,
			walls[wall_index].start_position,
			walls[wall_index].end_position,
			0.08,
			0.035,
			Color(1.0, 0.36, 0.22, 0.9),
			BSP_DRAW_Y_OFFSET_M + 0.025
		))

func _draw_bsp_sockets(data: BspModuleDataScript) -> void:
	var sockets_root := _new_debug_root("Sockets")
	var sockets := BspRoomProcessorScript.compile_interest_sockets(data)
	for socket in sockets:
		var kind := socket.get("kind", &"") as StringName
		var position := socket.get("position", Vector3.ZERO) as Vector3
		var socket_id := socket.get("id", &"socket") as StringName
		if kind == &"object_socket":
			sockets_root.add_child(_new_socket_box(socket_id, position, _socket_color(kind, socket)))
			continue

		var width_m := float(socket.get("width_m", 1.0))
		sockets_root.add_child(_new_socket_disc(socket_id, position, maxf(width_m * 0.32, 0.18), _socket_color(kind, socket)))

func _draw_bsp_exit_route(data: BspModuleDataScript) -> void:
	var player_position: Variant = null
	for socket in BspRoomProcessorScript.compile_interest_sockets(data):
		if socket.get("object_kind", &"") == &"player_character":
			player_position = socket.get("position")
			break

	if not (player_position is Vector3):
		return

	var route_points := BspRoomProcessorScript.exterior_route_points_for_position(data, player_position as Vector3)
	if route_points.size() < 2:
		return

	var route_root := _new_debug_root("ExitRoute")
	for point_index in range(route_points.size() - 1):
		route_root.add_child(_new_segment_bar(
			"RouteSegment_%02d" % point_index,
			route_points[point_index],
			route_points[point_index + 1],
			0.07,
			0.035,
			Color(0.4, 1.0, 0.5, 0.95),
			BSP_ROUTE_Y_OFFSET_M
		))
	for point_index in range(route_points.size()):
		route_root.add_child(_new_marker(
			"RoutePoint_%02d" % point_index,
			route_points[point_index] + Vector3(0.0, BSP_ROUTE_Y_OFFSET_M, 0.0),
			0.08,
			Color(0.5, 1.0, 0.55, 0.95)
		))

func _add_rect_outline(
	parent: Node3D,
	rect: Rect2,
	color: Color,
	thickness_m: float,
	height_m: float,
	y_offset_m: float
) -> void:
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z0 := rect.position.y
	var z1 := rect.end.y
	var corners := [
		Vector3(x0, 0.0, z0),
		Vector3(x1, 0.0, z0),
		Vector3(x1, 0.0, z1),
		Vector3(x0, 0.0, z1),
	]
	for side_index in range(corners.size()):
		parent.add_child(_new_segment_bar(
			"Bounds_%02d" % side_index,
			corners[side_index],
			corners[(side_index + 1) % corners.size()],
			thickness_m,
			height_m,
			color,
			y_offset_m
		))

func _new_segment_bar(
	segment_name: String,
	start: Vector3,
	end: Vector3,
	thickness_m: float,
	height_m: float,
	color: Color,
	y_offset_m: float
) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.name = segment_name
	var delta := end - start
	delta.y = 0.0
	var length := maxf(delta.length(), thickness_m)
	segment.position = Vector3(
		(start.x + end.x) * 0.5,
		y_offset_m,
		(start.z + end.z) * 0.5
	)
	if delta.length_squared() > 0.000001:
		segment.rotation.y = atan2(delta.x, delta.z)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness_m, height_m, length)
	segment.mesh = mesh
	segment.material_override = _material(color)
	return segment

func _new_socket_disc(
	socket_id: StringName,
	position: Vector3,
	radius_m: float,
	color: Color
) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "Socket_%s" % _debug_name(socket_id)
	marker.position = position + Vector3(0.0, BSP_ROUTE_Y_OFFSET_M, 0.0)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius_m
	cylinder.bottom_radius = radius_m
	cylinder.height = 0.04
	cylinder.radial_segments = 20
	marker.mesh = cylinder
	marker.material_override = _material(color)
	return marker

func _new_socket_box(
	socket_id: StringName,
	position: Vector3,
	color: Color
) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "Socket_%s" % _debug_name(socket_id)
	marker.position = position + Vector3(0.0, BSP_ROUTE_Y_OFFSET_M, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 0.04, 0.42)
	marker.mesh = mesh
	marker.material_override = _material(color)
	return marker

func _new_room_fill(rect: Rect2, color: Color) -> MeshInstance3D:
	var fill := MeshInstance3D.new()
	fill.name = "SelectedRoomFill"
	fill.position = Vector3(
		rect.position.x + (rect.size.x * 0.5),
		BSP_DRAW_Y_OFFSET_M - 0.025,
		rect.position.y + (rect.size.y * 0.5)
	)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x, 0.018, rect.size.y)
	fill.mesh = mesh
	fill.material_override = _material(color)
	return fill

func _new_snap_point_cloud(center: Vector3, step_m: float) -> MultiMeshInstance3D:
	var point_span := maxi(1, int(floor(editor_snap_grid_radius_m / step_m)))
	var point_count := (point_span * 2 + 1) * (point_span * 2 + 1)
	if point_count <= 0:
		return null

	var point_mesh := SphereMesh.new()
	point_mesh.radius = 0.012
	point_mesh.height = 0.024
	point_mesh.radial_segments = 6
	point_mesh.rings = 3

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = point_mesh
	multimesh.instance_count = point_count

	var point_index := 0
	for x_index in range(-point_span, point_span + 1):
		for z_index in range(-point_span, point_span + 1):
			var point_position := Vector3(
				center.x + (float(x_index) * step_m),
				center.y + EDITOR_SNAP_DRAW_Y_OFFSET_M,
				center.z + (float(z_index) * step_m)
			)
			multimesh.set_instance_transform(point_index, Transform3D(Basis.IDENTITY, point_position))
			point_index += 1

	var cloud := MultiMeshInstance3D.new()
	cloud.name = "PointCloud"
	cloud.multimesh = multimesh
	cloud.material_override = _material(Color(0.65, 0.95, 1.0, 0.2))
	return cloud

func _new_snap_cursor_marker(position: Vector3) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "SnapCursor"
	marker.position = position + Vector3(0.0, EDITOR_SNAP_DRAW_Y_OFFSET_M + 0.005, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.018, 0.07)
	marker.mesh = mesh
	marker.material_override = _material(Color(0.95, 1.0, 1.0, 0.55))
	return marker

func _socket_color(kind: StringName, socket: Dictionary) -> Color:
	if kind == &"exterior_exit_socket":
		return Color(0.2, 1.0, 0.45, 0.95)
	if bool(socket.get("is_manual", false)):
		return Color(1.0, 0.35, 0.95, 0.95)
	if kind == &"object_socket":
		if socket.get("object_kind", &"") == &"player_character":
			return Color(0.35, 0.55, 1.0, 0.95)
		return Color(0.72, 0.72, 0.76, 0.95)
	return Color(1.0, 0.78, 0.18, 0.95)

func _clear_path() -> void:
	for child in _path_root.get_children():
		child.free()

func _clear_bsp_interest_debug() -> void:
	if _bsp_root == null:
		_bsp_root = _get_or_create_root(BSP_ROOT_NAME)
	for child in _bsp_root.get_children():
		child.free()

func _clear_failure_marker() -> void:
	_remove_marker(FAILURE_MARKER_NAME)

func _remove_marker(marker_name: StringName) -> void:
	var marker := _marker_root.get_node_or_null(String(marker_name))
	if marker != null:
		marker.free()

func _position_from_target(target: Node) -> Variant:
	if target == null:
		return null
	if target.has_method("get_target_data"):
		return _position_from_resource(target.call("get_target_data") as Resource)

	return _position_from_resource(target.get("target_data") as Resource)

func _position_from_resource(resource: Resource) -> Variant:
	if resource == null:
		return null

	var position: Variant = resource.get("position")
	return position if position is Vector3 else null

func _position_from_details(details: Dictionary) -> Variant:
	var target_position: Variant = details.get("target_position")
	if target_position is Vector3:
		return target_position

	var snapped_target: Variant = details.get("snapped_target")
	return snapped_target if snapped_target is Vector3 else null

func _draw_position(position: Vector3) -> Vector3:
	return position + Vector3(0.0, DRAW_Y_OFFSET_M, 0.0)

func _get_or_create_root(root_name: StringName) -> Node3D:
	var root := get_node_or_null(String(root_name)) as Node3D
	if root != null:
		return root

	root = Node3D.new()
	root.name = String(root_name)
	add_child(root)
	return root

func _new_debug_root(root_name: String) -> Node3D:
	if _bsp_root == null:
		_bsp_root = _get_or_create_root(BSP_ROOT_NAME)

	var root := Node3D.new()
	root.name = root_name
	_bsp_root.add_child(root)
	return root

func _debug_name(id: StringName) -> String:
	return String(id).replace("/", "_")

func _connect_events() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	_connect_if_needed(event_bus, &"move_requested", Callable(self, "_on_move_requested"))
	_connect_if_needed(event_bus, &"movement_started", Callable(self, "_on_movement_started"))
	_connect_if_needed(event_bus, &"movement_failed", Callable(self, "_on_movement_failed"))
	_connect_if_needed(event_bus, &"interaction_targeting_failed", Callable(self, "_on_interaction_targeting_failed"))

func _connect_if_needed(event_bus: Node, signal_name: StringName, callable: Callable) -> void:
	if event_bus.has_signal(signal_name) and not event_bus.is_connected(signal_name, callable):
		event_bus.connect(signal_name, callable)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
