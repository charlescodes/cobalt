class_name NavigationDebugOverlay
extends Node3D

const PATH_ROOT_NAME: StringName = &"PathDebug"
const MARKER_ROOT_NAME: StringName = &"MarkerDebug"
const PATH_LINE_NAME: StringName = &"PathLine"
const DESTINATION_MARKER_NAME: StringName = &"DestinationMarker"
const FAILURE_MARKER_NAME: StringName = &"FailureMarker"
const DRAW_Y_OFFSET_M: float = 0.06

@export var waypoint_radius_m: float = 0.08
@export var destination_radius_m: float = 0.12
@export var failure_radius_m: float = 0.14

var _path_root: Node3D
var _marker_root: Node3D
var _last_requested_position: Vector3 = Vector3.ZERO
var _has_last_requested_position: bool = false

func _ready() -> void:
	visible = false
	_path_root = _get_or_create_root(PATH_ROOT_NAME)
	_marker_root = _get_or_create_root(MARKER_ROOT_NAME)
	_connect_events()

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

func _clear_path() -> void:
	for child in _path_root.get_children():
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
	material.no_depth_test = true
	return material

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
