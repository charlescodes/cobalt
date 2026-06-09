class_name MpcDirectControlController
extends Node

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const DIRECT_CONTROL_RADIUS_NODE_NAME := "MpcDirectControlRadius"
const MIN_MOVE_STEP_M: float = 0.001

@export var camera_path: NodePath = ^"../CameraRig/PitchPivot/Camera3D"
@export var movement_controller_path: NodePath = ^"../MovementController"
@export var world_objects_path: NodePath = ^"../NavigationRegion3D/GeneratedMap/WorldObjects"
@export_range(1.0, 500.0, 1.0) var max_ray_distance_m: float = 100.0
@export_flags_3d_physics var collision_mask: int = 1
@export_range(0.5, 8.0, 0.1) var walk_radius_m: float = 2.5
@export_range(0.05, 2.0, 0.05) var stop_radius_m: float = 0.35
@export_range(0.1, 8.0, 0.1) var walk_speed_mps: float = 1.8
@export_range(0.1, 12.0, 0.1) var run_speed_mps: float = 4.8
@export_range(0.5, 40.0, 0.5) var walk_acceleration_mps2: float = 8.0
@export_range(0.5, 60.0, 0.5) var run_acceleration_mps2: float = 18.0
@export_range(0.5, 60.0, 0.5) var stop_deceleration_mps2: float = 24.0
@export_range(0.01, 0.25, 0.01) var radius_ring_width_m: float = 0.08
@export_range(24, 192, 1) var radius_ring_segments: int = 96

var _camera: Camera3D
var _active_actor: Node3D
var _active_actor_data: WorldObjectDataScript
var _current_speed_mps: float = 0.0
var _is_direct_control_active: bool = false
var _is_gameplay_input_enabled: bool = false
var _is_interaction_pointer_captured: bool = false
var _is_targeting_interaction: bool = false
var _radius_ring: MeshInstance3D

func _ready() -> void:
	set_physics_process(false)
	_camera = _resolve_camera()
	_connect_event_bus()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
			return

		if not mouse_event.pressed:
			if _is_direct_control_active:
				stop_direct_control()
				_mark_input_handled()
			return

		if _is_input_already_handled():
			return
		if start_direct_control():
			_mark_input_handled()

func _physics_process(delta: float) -> void:
	if not _is_direct_control_active:
		set_physics_process(false)
		return
	if not _is_gameplay_input_enabled or _is_interaction_pointer_captured or _is_targeting_interaction:
		stop_direct_control()
		return
	if _active_actor == null or not is_instance_valid(_active_actor):
		stop_direct_control()
		return

	var target_hit := _raycast_move_target_under_mouse()
	if target_hit.is_empty():
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, stop_deceleration_mps2 * delta)
		return

	var hit_position: Vector3 = target_hit.get("position", _active_actor.position)
	drive_active_control_toward(hit_position, delta)

func start_direct_control(actor: Node = null) -> bool:
	if not _can_accept_direct_control():
		return false

	var actor3d := actor as Node3D
	if actor3d == null:
		actor3d = _resolve_primary_player_actor()
	if actor3d == null:
		return false

	var actor_data := _actor_data_for_node(actor3d)
	if not MoveTargetResolverScript.can_start_move_data(actor_data):
		return false
	if _get_navigation_agent(actor3d) == null:
		return false

	_cancel_scripted_movement(actor3d)
	_active_actor = actor3d
	_active_actor_data = actor_data
	_current_speed_mps = 0.0
	_is_direct_control_active = true
	_show_radius_ring(actor3d)
	set_physics_process(true)
	return true

func stop_direct_control() -> void:
	_is_direct_control_active = false
	_current_speed_mps = 0.0
	_active_actor = null
	_active_actor_data = null
	_hide_radius_ring()
	set_physics_process(false)

func drive_active_control_toward(target_position: Vector3, delta: float) -> bool:
	if _active_actor == null or not is_instance_valid(_active_actor) or _active_actor_data == null:
		return false

	var agent := _get_navigation_agent(_active_actor)
	if agent == null:
		return false

	var distance_to_target := _planar_distance(_active_actor.position, target_position)
	if distance_to_target <= stop_radius_m:
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, stop_deceleration_mps2 * delta)
		return true

	var navigation_map := _navigation_map_for_actor(_active_actor)
	var validation := MoveTargetResolverScript.navigation_path_result(
		navigation_map,
		_active_actor_data.position,
		target_position
	)
	if not bool(validation.get("ok", false)):
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, stop_deceleration_mps2 * delta)
		return false

	var desired_speed := run_speed_mps if distance_to_target > walk_radius_m else walk_speed_mps
	var acceleration := run_acceleration_mps2 if distance_to_target > walk_radius_m else walk_acceleration_mps2
	_current_speed_mps = move_toward(_current_speed_mps, desired_speed, acceleration * delta)

	agent.target_position = validation.get("snapped_target", target_position)
	return _move_actor_along_agent(agent, delta)

func is_direct_control_active() -> bool:
	return _is_direct_control_active

func is_gameplay_input_enabled() -> bool:
	return _is_gameplay_input_enabled

func get_current_speed_mps() -> float:
	return _current_speed_mps

func is_radius_ring_visible() -> bool:
	return _radius_ring != null and is_instance_valid(_radius_ring) and _radius_ring.visible

func _connect_event_bus() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	var mode_callable := Callable(self, "_handle_editor_mode_changed")
	var capture_callable := Callable(self, "_handle_interaction_pointer_capture_changed")
	var targeting_started_callable := Callable(self, "_handle_interaction_targeting_started")
	var targeting_cancelled_callable := Callable(self, "_handle_interaction_targeting_cancelled")
	var targeting_failed_callable := Callable(self, "_handle_interaction_targeting_failed")
	var move_requested_callable := Callable(self, "_handle_move_requested")
	var map_loaded_callable := Callable(self, "_handle_editor_map_loaded")
	if event_bus.has_signal(&"editor_mode_changed") and not event_bus.is_connected(&"editor_mode_changed", mode_callable):
		event_bus.connect(&"editor_mode_changed", mode_callable)
	if event_bus.has_signal(&"interaction_pointer_capture_changed") and not event_bus.is_connected(&"interaction_pointer_capture_changed", capture_callable):
		event_bus.connect(&"interaction_pointer_capture_changed", capture_callable)
	if event_bus.has_signal(&"interaction_targeting_started") and not event_bus.is_connected(&"interaction_targeting_started", targeting_started_callable):
		event_bus.connect(&"interaction_targeting_started", targeting_started_callable)
	if event_bus.has_signal(&"interaction_targeting_cancelled") and not event_bus.is_connected(&"interaction_targeting_cancelled", targeting_cancelled_callable):
		event_bus.connect(&"interaction_targeting_cancelled", targeting_cancelled_callable)
	if event_bus.has_signal(&"interaction_targeting_failed") and not event_bus.is_connected(&"interaction_targeting_failed", targeting_failed_callable):
		event_bus.connect(&"interaction_targeting_failed", targeting_failed_callable)
	if event_bus.has_signal(&"move_requested") and not event_bus.is_connected(&"move_requested", move_requested_callable):
		event_bus.connect(&"move_requested", move_requested_callable)
	if event_bus.has_signal(&"editor_map_loaded") and not event_bus.is_connected(&"editor_map_loaded", map_loaded_callable):
		event_bus.connect(&"editor_map_loaded", map_loaded_callable)

func _handle_editor_mode_changed(mode: StringName) -> void:
	_is_gameplay_input_enabled = mode != &"editor"
	if not _is_gameplay_input_enabled:
		stop_direct_control()

func _handle_interaction_pointer_capture_changed(is_captured: bool) -> void:
	_is_interaction_pointer_captured = is_captured
	if is_captured and _is_direct_control_active:
		stop_direct_control()

func _handle_interaction_targeting_started(_source: Node, _action_id: StringName) -> void:
	_is_targeting_interaction = true

func _handle_interaction_targeting_cancelled(_source: Node, _action_id: StringName) -> void:
	_is_targeting_interaction = false

func _handle_interaction_targeting_failed(
	_source: Node,
	_target: Node,
	_action_id: StringName,
	_reason: StringName,
	_details: Dictionary
) -> void:
	_is_targeting_interaction = false

func _handle_move_requested(_actor: Node, _actor_data: Resource, _destination_data: Resource) -> void:
	_is_targeting_interaction = false

func _handle_editor_map_loaded(_map_data: Resource, _path: String) -> void:
	stop_direct_control()

func _can_accept_direct_control() -> bool:
	return (
		_is_gameplay_input_enabled
		and not _is_interaction_pointer_captured
		and not _is_targeting_interaction
	)

func _raycast_move_target_under_mouse() -> Dictionary:
	var viewport := get_viewport()
	if viewport == null:
		return {}

	return _raycast_move_target_at(viewport.get_mouse_position())

func _raycast_move_target_at(mouse_position: Vector2) -> Dictionary:
	if _camera == null:
		_camera = _resolve_camera()
	if _camera == null or _camera.get_world_3d() == null:
		return {}

	var ray_origin := _camera.project_ray_origin(mouse_position)
	var ray_end := ray_origin + (_camera.project_ray_normal(mouse_position) * max_ray_distance_m)
	var excluded: Array[RID] = []

	for _attempt in range(32):
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, collision_mask)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.exclude = excluded

		var result := _camera.get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			return {}

		var collider := result.get("collider") as Object
		var target := _find_interaction_target(collider)
		if target != null and target.target_domain == InteractionActionResolverScript.DOMAIN_MOVE_TARGET:
			var hit_position: Variant = result.get("position")
			if hit_position is Vector3:
				return {
					"target": target,
					"position": hit_position,
				}
			return {}

		var collision_object := collider as CollisionObject3D
		if collision_object == null:
			return {}

		excluded.append(collision_object.get_rid())

	return {}

func _find_interaction_target(collider: Object) -> InteractionTargetScript:
	var node := collider as Node
	while node != null:
		if node is InteractionTargetScript:
			return node

		node = node.get_parent()

	return null

func _move_actor_along_agent(agent: NavigationAgent3D, delta: float) -> bool:
	var target_position := agent.target_position
	var next_position := agent.get_next_path_position()
	if absf(next_position.y - _active_actor.position.y) <= 0.001:
		next_position.y = _active_actor.position.y

	var to_next := next_position - _active_actor.position
	if to_next.length() <= MIN_MOVE_STEP_M:
		to_next = target_position - _active_actor.position
		if absf(to_next.y) <= 0.001:
			to_next.y = 0.0

	if to_next.length() <= MIN_MOVE_STEP_M or _current_speed_mps <= 0.001:
		return false

	var move_budget := _current_speed_mps * delta
	_active_actor.position += to_next.normalized() * minf(move_budget, to_next.length())
	_active_actor_data.position = _active_actor.position
	return true

func _resolve_primary_player_actor() -> Node3D:
	var world_objects := get_node_or_null(world_objects_path)
	if world_objects == null:
		return null

	for child in world_objects.get_children():
		var actor := child as Node3D
		if actor == null:
			continue
		var actor_data := _actor_data_for_node(actor)
		if MoveTargetResolverScript.can_start_move_data(actor_data):
			return actor

	return null

func _actor_data_for_node(actor: Node) -> WorldObjectDataScript:
	if actor == null:
		return null
	var actor_data: Variant = actor.get("object_data")
	return actor_data as WorldObjectDataScript

func _get_navigation_agent(actor: Node) -> NavigationAgent3D:
	if actor == null:
		return null
	if actor.has_method("get_navigation_agent"):
		return actor.call("get_navigation_agent") as NavigationAgent3D

	return actor.get_node_or_null("NavigationAgent3D") as NavigationAgent3D

func _navigation_map_for_actor(actor: Node) -> RID:
	var agent := _get_navigation_agent(actor)
	if agent != null:
		var agent_map := agent.get_navigation_map()
		if agent_map.is_valid():
			return agent_map

	var actor3d := actor as Node3D
	if actor3d != null and actor3d.is_inside_tree() and actor3d.get_world_3d() != null:
		return actor3d.get_world_3d().navigation_map

	return RID()

func _cancel_scripted_movement(actor: Node) -> void:
	var movement_controller := get_node_or_null(movement_controller_path)
	if movement_controller != null and movement_controller.has_method("cancel_actor_movement"):
		movement_controller.call("cancel_actor_movement", actor)

func _show_radius_ring(actor: Node3D) -> void:
	var ring := actor.get_node_or_null(DIRECT_CONTROL_RADIUS_NODE_NAME) as MeshInstance3D
	if ring == null:
		ring = MeshInstance3D.new()
		ring.name = DIRECT_CONTROL_RADIUS_NODE_NAME
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		actor.add_child(ring)

	ring.position = Vector3(0.0, 0.035, 0.0)
	ring.mesh = _build_radius_ring_mesh()
	ring.material_override = _radius_ring_material()
	ring.visible = true
	_radius_ring = ring

func _hide_radius_ring() -> void:
	if _radius_ring != null and is_instance_valid(_radius_ring):
		_radius_ring.visible = false

func _build_radius_ring_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var outer_radius := maxf(walk_radius_m, 0.01)
	var inner_radius := maxf(0.01, outer_radius - radius_ring_width_m)
	var segments := maxi(radius_ring_segments, 12)

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(segments):
		var angle_a := (TAU * float(index)) / float(segments)
		var angle_b := (TAU * float(index + 1)) / float(segments)
		var inner_a := Vector3(cos(angle_a) * inner_radius, 0.0, sin(angle_a) * inner_radius)
		var outer_a := Vector3(cos(angle_a) * outer_radius, 0.0, sin(angle_a) * outer_radius)
		var inner_b := Vector3(cos(angle_b) * inner_radius, 0.0, sin(angle_b) * inner_radius)
		var outer_b := Vector3(cos(angle_b) * outer_radius, 0.0, sin(angle_b) * outer_radius)
		mesh.surface_add_vertex(inner_a)
		mesh.surface_add_vertex(outer_a)
		mesh.surface_add_vertex(outer_b)
		mesh.surface_add_vertex(inner_a)
		mesh.surface_add_vertex(outer_b)
		mesh.surface_add_vertex(inner_b)
	mesh.surface_end()
	return mesh

func _radius_ring_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.78, 0.92, 0.42)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _resolve_camera() -> Camera3D:
	var configured_camera := get_node_or_null(camera_path) as Camera3D
	if configured_camera != null:
		return configured_camera

	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null

func _planar_distance(a: Vector3, b: Vector3) -> float:
	var flat_a := Vector2(a.x, a.z)
	var flat_b := Vector2(b.x, b.z)
	return flat_a.distance_to(flat_b)

func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()

func _is_input_already_handled() -> bool:
	var viewport := get_viewport()
	return viewport != null and viewport.is_input_handled()

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
