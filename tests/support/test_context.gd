extends RefCounted

const EventBusScript := preload("res://src/core/event_bus.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")

var tree: SceneTree
var move_requested_count: int = 0
var move_requested_actor: Node
var move_requested_actor_data: Resource
var move_requested_destination: Resource
var hover_changed_count: int = 0
var hover_changed_target: Node
var examined_count: int = 0
var examined_target_domain: StringName = &""
var examined_target_data: Resource
var examined_output: Dictionary = {}
var movement_started_count: int = 0
var movement_started_path: PackedVector3Array
var movement_completed_count: int = 0
var movement_failed_count: int = 0
var movement_failed_reason: StringName = &""

func _init(p_tree: SceneTree) -> void:
	tree = p_tree

func root() -> Window:
	return tree.root

func idle_frame() -> void:
	await tree.process_frame

func physics_idle() -> void:
	await tree.process_frame
	await tree.physics_frame

func ensure_root_event_bus() -> Node:
	var root_event_bus := root().get_node_or_null("EventBus")
	if root_event_bus != null:
		return root_event_bus

	root_event_bus = EventBusScript.new()
	root_event_bus.name = "EventBus"
	root().add_child(root_event_bus)
	return root_event_bus

func connect_if_needed(event_bus: Node, signal_name: StringName, callable: Callable) -> void:
	if event_bus != null and not event_bus.is_connected(signal_name, callable):
		event_bus.connect(signal_name, callable)

func disconnect_if_connected(event_bus: Node, signal_name: StringName, callable: Callable) -> void:
	if event_bus != null and event_bus.is_connected(signal_name, callable):
		event_bus.disconnect(signal_name, callable)

func reset_move_requested() -> void:
	move_requested_count = 0
	move_requested_actor = null
	move_requested_actor_data = null
	move_requested_destination = null

func reset_hover_changed() -> void:
	hover_changed_count = 0
	hover_changed_target = null

func reset_examined_output() -> void:
	examined_count = 0
	examined_target_domain = &""
	examined_target_data = null
	examined_output = {}

func reset_movement_events() -> void:
	movement_started_count = 0
	movement_started_path = PackedVector3Array()
	movement_completed_count = 0
	movement_failed_count = 0
	movement_failed_reason = &""

func move_requested_callable() -> Callable:
	return Callable(self, "_record_move_requested")

func hover_changed_callable() -> Callable:
	return Callable(self, "_record_hover_target_changed")

func examined_output_callable() -> Callable:
	return Callable(self, "_record_examined_output")

func movement_started_callable() -> Callable:
	return Callable(self, "_record_movement_started")

func movement_completed_callable() -> Callable:
	return Callable(self, "_record_movement_completed")

func movement_failed_callable() -> Callable:
	return Callable(self, "_record_movement_failed")

func create_square_nav_map() -> Dictionary:
	var navigation_map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(navigation_map, true)

	var navigation_region := create_square_nav_region_on_map(navigation_map)
	return {
		"map": navigation_map,
		"region": navigation_region,
	}

func wait_for_navigation_map(navigation_map: RID) -> void:
	for _index in range(8):
		if NavigationServer3D.map_get_iteration_id(navigation_map) > 0:
			return

		await tree.process_frame
		await tree.physics_frame
		NavigationServer3D.map_force_update(navigation_map)

func create_square_nav_region_on_map(navigation_map: RID) -> RID:
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

func free_nav_map(navigation_map: RID, navigation_region: RID) -> void:
	if navigation_region.is_valid():
		NavigationServer3D.free_rid(navigation_region)
	if navigation_map.is_valid():
		NavigationServer3D.free_rid(navigation_map)

func make_interaction_target(target_domain: StringName, target_data: Resource) -> InteractionTargetScript:
	var target := InteractionTargetScript.new()
	target.target_domain = target_domain
	target.target_data = target_data
	return target

func warp_mouse_to_world(camera: Camera3D, world_position: Vector3) -> Vector2:
	var screen_position := camera.unproject_position(world_position)
	root().warp_mouse(screen_position)
	return screen_position

func raycast_first_area_hit(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + (camera.project_ray_normal(screen_position) * 100.0)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return camera.get_world_3d().direct_space_state.intersect_ray(query)

func drive_interaction_hover_at_screen(
	interaction_controller: InteractionControllerScript,
	screen_position: Vector2,
	required_domain: StringName = &""
) -> InteractionTargetScript:
	var target := interaction_controller._raycast_interaction_target_at(screen_position, required_domain)
	interaction_controller._set_hover_target(target)
	return target

func control_inside_viewport(control: Control) -> bool:
	var viewport_rect := control.get_viewport_rect()
	var control_rect := Rect2(control.position, control.size)
	return (
		control_rect.position.x >= 0.0
		and control_rect.position.y >= 0.0
		and control_rect.end.x <= viewport_rect.size.x
		and control_rect.end.y <= viewport_rect.size.y
	)

func has_action(actions: Array[Dictionary], action_id: StringName) -> bool:
	for action in actions:
		if action.get("id") == action_id:
			return true

	return false

func fail(message: String) -> bool:
	push_error(message)
	return false

func _record_move_requested(actor: Node, actor_data: Resource, destination_data: Resource) -> void:
	move_requested_count += 1
	move_requested_actor = actor
	move_requested_actor_data = actor_data
	move_requested_destination = destination_data

func _record_hover_target_changed(target: Node) -> void:
	hover_changed_count += 1
	hover_changed_target = target

func _record_examined_output(target_domain: StringName, target_data: Resource, output: Dictionary) -> void:
	examined_count += 1
	examined_target_domain = target_domain
	examined_target_data = target_data
	examined_output = output

func _record_movement_started(_actor: Node, path: PackedVector3Array) -> void:
	movement_started_count += 1
	movement_started_path = path

func _record_movement_completed(_actor: Node, _destination_data: Resource) -> void:
	movement_completed_count += 1

func _record_movement_failed(_actor: Node, _destination_data: Resource, reason: StringName) -> void:
	movement_failed_count += 1
	movement_failed_reason = reason
