class_name RealtimeGameplayController
extends Node

const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

const CONTROL_MODE_REAL_TIME: StringName = &"real_time"
const PLAYER_CHARACTER_KIND: StringName = &"player_character"
const MOVEMENT_BAND_IDLE: StringName = &"idle"
const MOVEMENT_BAND_TIPTOE: StringName = &"tiptoe"
const MOVEMENT_BAND_WALK: StringName = &"walk"
const MOVEMENT_BAND_RUN: StringName = &"run"
const REFERENCE_MASS_KG: float = 100.0
const MIN_SPEED_MPS: float = 0.001

@export var camera_path: NodePath = ^"../CameraRig/PitchPivot/Camera3D"
@export var movement_controller_path: NodePath = ^"../MovementController"
@export var world_objects_path: NodePath = ^"../NavigationRegion3D/GeneratedMap/WorldObjects"
@export_range(0.0, 0.25, 0.01) var stop_radius_m: float = 0.05
@export_range(0.1, 1.0, 0.05) var tiptoe_radius_m: float = 0.5
@export_range(0.5, 5.0, 0.1) var walk_radius_m: float = 2.0
@export_range(0.1, 2.0, 0.1) var tiptoe_speed_mps: float = 0.6
@export_range(0.5, 4.0, 0.1) var walk_speed_mps: float = 1.8
@export_range(1.0, 12.0, 0.1) var run_speed_mps: float = 5.0
@export_range(0.1, 20.0, 0.1) var tiptoe_acceleration_mps2: float = 2.0
@export_range(0.1, 20.0, 0.1) var walk_acceleration_mps2: float = 3.5
@export_range(0.1, 30.0, 0.1) var run_acceleration_mps2: float = 6.0
@export_range(0.1, 40.0, 0.1) var braking_mps2: float = 8.0

var _camera: Camera3D
var _player_actors: Array[Node3D] = []
var _active_actor: Node3D
var _active_actor_data: WorldObjectDataScript
var _active_actor_id: StringName = &""
var _planar_velocity: Vector3 = Vector3.ZERO
var _is_real_time_mode: bool = false
var _is_pointer_captured: bool = false
var _is_direct_movement_held: bool = false

func _ready() -> void:
	set_physics_process(false)
	_camera = _resolve_camera()
	_connect_event_bus()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_real_time_mode:
		return

	if event.is_action_pressed("cycle_player_character"):
		if cycle_active_player_character():
			_mark_input_handled()
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return

	if mouse_event.pressed:
		if mouse_event.ctrl_pressed or _is_pointer_captured:
			return
		if begin_direct_movement():
			_mark_input_handled()
	elif _is_direct_movement_held:
		end_direct_movement()
		_mark_input_handled()

func _physics_process(delta: float) -> void:
	if not _is_real_time_mode or _active_actor == null or not is_instance_valid(_active_actor):
		_stop_immediately()
		return

	if _is_direct_movement_held:
		var target_position: Variant = _cursor_ground_position()
		if target_position is Vector3:
			drive_active_actor_toward(target_position, delta)
		else:
			_apply_braking(delta)
	else:
		_apply_braking(delta)

	if not _is_direct_movement_held and _planar_velocity.length() <= MIN_SPEED_MPS:
		_planar_velocity = Vector3.ZERO
		set_physics_process(false)

func begin_direct_movement() -> bool:
	if not _is_real_time_mode or _is_pointer_captured:
		return false
	if not _ensure_active_player_character():
		return false

	_cancel_scripted_movement(_active_actor)
	_is_direct_movement_held = true
	set_physics_process(true)
	return true

func end_direct_movement() -> void:
	_is_direct_movement_held = false
	if _planar_velocity.length() > MIN_SPEED_MPS:
		set_physics_process(true)

func cancel_direct_movement() -> void:
	_stop_immediately()

func drive_active_actor_toward(target_position: Vector3, delta: float) -> bool:
	if not _ensure_active_player_character() or delta <= 0.0:
		return false

	var offset := target_position - _active_actor.global_position
	offset.y = 0.0
	var distance_m := offset.length()
	var movement_band := movement_band_for_distance(distance_m)
	if movement_band == MOVEMENT_BAND_IDLE or offset.length_squared() <= 0.000001:
		_apply_braking(delta)
		return true

	var desired_speed := target_speed_for_band(movement_band)
	var desired_velocity := offset.normalized() * desired_speed
	var acceleration := _mass_adjusted_acceleration(acceleration_for_band(movement_band))
	_planar_velocity = _planar_velocity.move_toward(desired_velocity, acceleration * delta)
	_move_active_actor(delta)
	return true

func refresh_player_characters() -> void:
	var previous_id := _active_actor_id
	_player_actors.clear()
	var world_objects := get_node_or_null(world_objects_path)
	if world_objects != null:
		for child in world_objects.get_children():
			var actor := child as Node3D
			var actor_data := _actor_data_for_node(actor)
			if actor != null and _is_player_character_data(actor_data):
				_player_actors.append(actor)

	_player_actors.sort_custom(_player_actor_id_less)
	var next_index := 0
	if previous_id != &"":
		for index in range(_player_actors.size()):
			if _actor_id_for_node(_player_actors[index]) == previous_id:
				next_index = index
				break

	_set_active_player_character_by_index(next_index if not _player_actors.is_empty() else -1)

func cycle_active_player_character() -> bool:
	if not _is_real_time_mode:
		return false
	refresh_player_characters()
	if _player_actors.size() <= 1:
		return not _player_actors.is_empty()

	var current_index := _player_actors.find(_active_actor)
	_set_active_player_character_by_index((current_index + 1) % _player_actors.size())
	return true

func get_active_player_character() -> Node3D:
	return _active_actor

func get_active_player_character_data() -> WorldObjectDataScript:
	return _active_actor_data

func get_current_speed_mps() -> float:
	return _planar_velocity.length()

func get_current_velocity() -> Vector3:
	return _planar_velocity

func is_real_time_mode_active() -> bool:
	return _is_real_time_mode

func is_direct_movement_held() -> bool:
	return _is_direct_movement_held

func movement_band_for_distance(distance_m: float) -> StringName:
	if distance_m <= stop_radius_m:
		return MOVEMENT_BAND_IDLE
	if distance_m <= tiptoe_radius_m:
		return MOVEMENT_BAND_TIPTOE
	if distance_m <= walk_radius_m:
		return MOVEMENT_BAND_WALK
	return MOVEMENT_BAND_RUN

func target_speed_for_band(movement_band: StringName) -> float:
	match movement_band:
		MOVEMENT_BAND_TIPTOE:
			return tiptoe_speed_mps
		MOVEMENT_BAND_WALK:
			return walk_speed_mps
		MOVEMENT_BAND_RUN:
			return run_speed_mps
		_:
			return 0.0

func acceleration_for_band(movement_band: StringName) -> float:
	match movement_band:
		MOVEMENT_BAND_TIPTOE:
			return tiptoe_acceleration_mps2
		MOVEMENT_BAND_WALK:
			return walk_acceleration_mps2
		MOVEMENT_BAND_RUN:
			return run_acceleration_mps2
		_:
			return braking_mps2

func _connect_event_bus() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	_connect_if_needed(event_bus, &"gameplay_control_mode_changed", Callable(self, "_on_gameplay_control_mode_changed"))
	_connect_if_needed(event_bus, &"interaction_pointer_capture_changed", Callable(self, "_on_interaction_pointer_capture_changed"))
	_connect_if_needed(event_bus, &"editor_map_loaded", Callable(self, "_on_editor_map_loaded"))

func _connect_if_needed(event_bus: Node, signal_name: StringName, callable: Callable) -> void:
	if event_bus.has_signal(signal_name) and not event_bus.is_connected(signal_name, callable):
		event_bus.connect(signal_name, callable)

func _on_gameplay_control_mode_changed(mode: StringName) -> void:
	_is_real_time_mode = mode == CONTROL_MODE_REAL_TIME
	if not _is_real_time_mode:
		_stop_immediately()
		_clear_active_player_character()
		return

	call_deferred("refresh_player_characters")

func _on_interaction_pointer_capture_changed(is_captured: bool) -> void:
	_is_pointer_captured = is_captured
	if is_captured:
		_stop_immediately()

func _on_editor_map_loaded(_map_data: Resource, _path: String) -> void:
	_stop_immediately()
	if _is_real_time_mode:
		call_deferred("refresh_player_characters")

func _set_active_player_character_by_index(index: int) -> void:
	_stop_immediately()
	if index < 0 or index >= _player_actors.size():
		_clear_active_player_character()
		return

	_active_actor = _player_actors[index]
	_active_actor_data = _actor_data_for_node(_active_actor)
	_active_actor_id = _active_actor_data.object_id if _active_actor_data != null else &""
	_emit_active_player_character_changed()

func _clear_active_player_character() -> void:
	_active_actor = null
	_active_actor_data = null
	_active_actor_id = &""
	_emit_active_player_character_changed()

func _ensure_active_player_character() -> bool:
	if (
		_active_actor != null
		and is_instance_valid(_active_actor)
		and _is_player_character_data(_active_actor_data)
	):
		return true

	refresh_player_characters()
	return _active_actor != null and _active_actor_data != null

func _cursor_ground_position() -> Variant:
	if _camera == null:
		_camera = _resolve_camera()
	var viewport := get_viewport()
	if _camera == null or viewport == null or _active_actor == null:
		return null

	var mouse_position := viewport.get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_position)
	var ray_direction := _camera.project_ray_normal(mouse_position)
	var actor_plane := Plane(Vector3.UP, _active_actor.global_position.y)
	return actor_plane.intersects_ray(ray_origin, ray_direction)

func _apply_braking(delta: float) -> void:
	if _planar_velocity.length() <= MIN_SPEED_MPS:
		_planar_velocity = Vector3.ZERO
		return

	_planar_velocity = _planar_velocity.move_toward(
		Vector3.ZERO,
		_mass_adjusted_acceleration(braking_mps2) * delta
	)
	_move_active_actor(delta)

func _move_active_actor(delta: float) -> void:
	if _active_actor == null or _active_actor_data == null:
		return

	var motion := _planar_velocity * delta
	var actor_body := _active_actor as CharacterBody3D
	if actor_body != null:
		actor_body.velocity = _planar_velocity
		var collision := actor_body.move_and_collide(motion)
		if collision != null:
			var slide_motion := collision.get_remainder().slide(collision.get_normal())
			if slide_motion.length_squared() > 0.000001:
				actor_body.move_and_collide(slide_motion)
			_planar_velocity = _planar_velocity.slide(collision.get_normal())
	else:
		_active_actor.position += motion

	_active_actor_data.position = _active_actor.position

func _mass_adjusted_acceleration(base_acceleration_mps2: float) -> float:
	var mass_kg := REFERENCE_MASS_KG
	if _active_actor_data != null:
		mass_kg = maxf(_active_actor_data.mass_kg, 1.0)
	return base_acceleration_mps2 * (REFERENCE_MASS_KG / mass_kg)

func _stop_immediately() -> void:
	_is_direct_movement_held = false
	_planar_velocity = Vector3.ZERO
	var actor_body := _active_actor as CharacterBody3D
	if actor_body != null:
		actor_body.velocity = Vector3.ZERO
	set_physics_process(false)

func _cancel_scripted_movement(actor: Node) -> void:
	var movement_controller := get_node_or_null(movement_controller_path)
	if movement_controller != null and movement_controller.has_method("cancel_actor_movement"):
		movement_controller.call("cancel_actor_movement", actor)

func _actor_data_for_node(actor: Node) -> WorldObjectDataScript:
	if actor == null:
		return null
	return actor.get("object_data") as WorldObjectDataScript

func _actor_id_for_node(actor: Node) -> StringName:
	var actor_data := _actor_data_for_node(actor)
	return actor_data.object_id if actor_data != null else &""

func _is_player_character_data(actor_data: WorldObjectDataScript) -> bool:
	return (
		actor_data != null
		and actor_data.object_kind == PLAYER_CHARACTER_KIND
	)

func _player_actor_id_less(a: Node3D, b: Node3D) -> bool:
	return String(_actor_id_for_node(a)) < String(_actor_id_for_node(b))

func _emit_active_player_character_changed() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null and event_bus.has_signal(&"active_player_character_changed"):
		event_bus.emit_signal(
			&"active_player_character_changed",
			_active_actor,
			_active_actor_data
		)

func _resolve_camera() -> Camera3D:
	var configured_camera := get_node_or_null(camera_path) as Camera3D
	if configured_camera != null:
		return configured_camera
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null

func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
