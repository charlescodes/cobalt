class_name CameraRig
extends Node3D

const RUNTIME_MODE_GAME: StringName = &"game"
const CONTROL_MODE_REAL_TIME: StringName = &"real_time"

@export var pitch_pivot_path: NodePath = ^"PitchPivot"
@export var camera_path: NodePath = ^"PitchPivot/Camera3D"
@export_range(1.0, 50.0, 0.5) var start_height_m: float = 7.0
@export_range(1.0, 50.0, 0.5) var min_height_m: float = 2.0
@export_range(1.0, 50.0, 0.5) var max_height_m: float = 18.0
@export_range(0.25, 5.0, 0.25) var height_step_m: float = 1.0
@export_range(-180.0, 180.0, 1.0, "degrees") var start_yaw_degrees: float = 45.0
@export_range(-89.0, -5.0, 1.0, "degrees") var start_pitch_degrees: float = -55.0
@export_range(-89.0, -5.0, 1.0, "degrees") var min_pitch_degrees: float = -80.0
@export_range(-89.0, -5.0, 1.0, "degrees") var max_pitch_degrees: float = -20.0
@export_range(0.001, 0.1, 0.001) var pan_speed_m_per_pixel: float = 0.015
@export_range(0.001, 0.02, 0.001) var look_sensitivity: float = 0.005
@export var world_start_height_m: float = 350000.0
@export var world_min_height_m: float = 25000.0
@export var world_max_height_m: float = 850000.0
@export var world_height_step_m: float = 25000.0
@export var world_pan_speed_m_per_pixel: float = 750.0
@export var world_camera_far_m: float = 2500000.0
@export var world_camera_near_m: float = 10.0

var _height_m: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_panning: bool = false
var _is_looking: bool = false
var _pitch_pivot: Node3D
var _camera: Camera3D
var _active_min_height_m: float = 0.0
var _active_max_height_m: float = 0.0
var _active_height_step_m: float = 0.0
var _active_pan_speed_m_per_pixel: float = 0.0
var _local_camera_far_m: float = 0.0
var _local_camera_near_m: float = 0.0
var _local_position: Vector3 = Vector3.ZERO
var _local_height_m: float = 0.0
var _local_yaw: float = 0.0
var _local_pitch: float = 0.0
var _world_position: Vector3 = Vector3.ZERO
var _world_height_m: float = 0.0
var _world_yaw: float = 0.0
var _world_pitch: float = 0.0
var _is_world_camera_mode: bool = false
var _runtime_mode: StringName = &"editor"
var _gameplay_control_mode: StringName = &"none"
var _follow_target: Node3D
var _is_temporary_follow_pan: bool = false

func _ready() -> void:
	_active_min_height_m = min_height_m
	_active_max_height_m = max_height_m
	_active_height_step_m = height_step_m
	_active_pan_speed_m_per_pixel = pan_speed_m_per_pixel
	_height_m = clampf(start_height_m, _active_min_height_m, _active_max_height_m)
	_yaw = deg_to_rad(start_yaw_degrees)
	_pitch = deg_to_rad(clampf(start_pitch_degrees, min_pitch_degrees, max_pitch_degrees))
	_pitch_pivot = _get_or_create_pitch_pivot()
	_camera = _get_or_create_camera()
	_local_camera_far_m = _camera.far
	_local_camera_near_m = _camera.near
	_local_position = position
	_local_height_m = _height_m
	_local_yaw = _yaw
	_local_pitch = _pitch
	_world_position = Vector3.ZERO
	_world_height_m = world_start_height_m
	_world_yaw = _yaw
	_world_pitch = _pitch
	_camera.current = true
	_apply_camera_transform()
	_connect_event_bus()

func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or key_event.pressed or not _is_temporary_follow_pan:
		return
	if key_event.keycode == KEY_CTRL or key_event.physical_keycode == KEY_CTRL:
		_end_temporary_follow_pan()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _process(_delta: float) -> void:
	if _is_realtime_follow_active() and not _is_temporary_follow_pan:
		_snap_to_follow_target()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_is_panning = false
		_is_looking = false
		_is_temporary_follow_pan = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if _is_realtime_follow_active():
			_snap_to_follow_target()

func set_height_m(value: float) -> void:
	_height_m = clampf(value, _active_min_height_m, _active_max_height_m)
	_apply_camera_transform()

static func camera_distance_for_height(height_m: float, pitch_radians: float) -> float:
	var vertical_ratio := maxf(sin(-pitch_radians), 0.1)
	return maxf(height_m, 0.0) / vertical_ratio

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			if _is_realtime_gameplay_mode():
				if event.pressed and event.ctrl_pressed and _follow_target != null:
					_is_panning = true
					_is_temporary_follow_pan = true
					get_viewport().set_input_as_handled()
				elif not event.pressed and _is_temporary_follow_pan:
					_end_temporary_follow_pan()
					get_viewport().set_input_as_handled()
				return
			_is_panning = event.pressed
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			_is_looking = event.pressed
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _is_looking else Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				set_height_m(_height_m + _active_height_step_m)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				set_height_m(_height_m - _active_height_step_m)
				get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_looking:
		_yaw -= event.relative.x * look_sensitivity
		_pitch = clampf(
			_pitch - event.relative.y * look_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		_apply_camera_transform()
		get_viewport().set_input_as_handled()
	elif _is_panning:
		_pan_ground_focus(event.relative)
		get_viewport().set_input_as_handled()

func _pan_ground_focus(mouse_delta: Vector2) -> void:
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var right := yaw_basis.x.normalized()
	var forward := -yaw_basis.z.normalized()
	position += ((-right * mouse_delta.x) + (forward * mouse_delta.y)) * _active_pan_speed_m_per_pixel
	position.y = 0.0

func _apply_camera_transform() -> void:
	if _pitch_pivot == null or _camera == null:
		return

	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	_camera.position = Vector3(0.0, 0.0, camera_distance_for_height(_height_m, _pitch))

func _get_or_create_pitch_pivot() -> Node3D:
	var pivot := get_node_or_null(pitch_pivot_path) as Node3D
	if pivot != null:
		return pivot

	pivot = Node3D.new()
	pivot.name = "PitchPivot"
	add_child(pivot)
	return pivot

func _get_or_create_camera() -> Camera3D:
	var found_camera := get_node_or_null(camera_path) as Camera3D
	if found_camera != null:
		return found_camera

	found_camera = Camera3D.new()
	found_camera.name = "Camera3D"
	_pitch_pivot.add_child(found_camera)
	return found_camera

func _connect_event_bus() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		return

	var mode_callable := Callable(self, "_on_editor_mode_changed")
	if event_bus.has_signal(&"editor_mode_changed") and not event_bus.is_connected(&"editor_mode_changed", mode_callable):
		event_bus.connect(&"editor_mode_changed", mode_callable)
	var gameplay_mode_callable := Callable(self, "_on_gameplay_control_mode_changed")
	if (
		event_bus.has_signal(&"gameplay_control_mode_changed")
		and not event_bus.is_connected(&"gameplay_control_mode_changed", gameplay_mode_callable)
	):
		event_bus.connect(&"gameplay_control_mode_changed", gameplay_mode_callable)
	var active_character_callable := Callable(self, "_on_active_player_character_changed")
	if (
		event_bus.has_signal(&"active_player_character_changed")
		and not event_bus.is_connected(&"active_player_character_changed", active_character_callable)
	):
		event_bus.connect(&"active_player_character_changed", active_character_callable)

func _on_editor_mode_changed(mode: StringName) -> void:
	var previous_runtime_mode := _runtime_mode
	if mode == RUNTIME_MODE_GAME and previous_runtime_mode != RUNTIME_MODE_GAME:
		_store_local_camera_state()
	_runtime_mode = mode
	if mode != RUNTIME_MODE_GAME:
		_is_temporary_follow_pan = false
		_is_panning = false
	if mode == &"world_editor":
		if not _is_world_camera_mode:
			if previous_runtime_mode != RUNTIME_MODE_GAME:
				_store_local_camera_state()
		_active_min_height_m = world_min_height_m
		_active_max_height_m = world_max_height_m
		_active_height_step_m = world_height_step_m
		_active_pan_speed_m_per_pixel = world_pan_speed_m_per_pixel
		if _camera != null:
			_camera.near = world_camera_near_m
			_camera.far = world_camera_far_m
		_is_world_camera_mode = true
		_apply_saved_camera_state(_world_position, _world_height_m, _world_yaw, _world_pitch)
	else:
		if _is_world_camera_mode:
			_store_world_camera_state()
		_active_min_height_m = min_height_m
		_active_max_height_m = max_height_m
		_active_height_step_m = height_step_m
		_active_pan_speed_m_per_pixel = pan_speed_m_per_pixel
		if _camera != null:
			_camera.near = _local_camera_near_m
			_camera.far = _local_camera_far_m
		_is_world_camera_mode = false
		if (
			previous_runtime_mode == &"world_editor"
			or (previous_runtime_mode == RUNTIME_MODE_GAME and mode != RUNTIME_MODE_GAME)
		):
			_apply_saved_camera_state(_local_position, _local_height_m, _local_yaw, _local_pitch)
	if _is_realtime_follow_active():
		_snap_to_follow_target()

func _on_gameplay_control_mode_changed(mode: StringName) -> void:
	_gameplay_control_mode = mode
	if mode != CONTROL_MODE_REAL_TIME:
		_is_temporary_follow_pan = false
		_is_panning = false
	elif _is_realtime_follow_active():
		_snap_to_follow_target()

func _on_active_player_character_changed(actor: Node, _actor_data: Resource) -> void:
	_follow_target = actor as Node3D
	if _is_realtime_follow_active():
		_is_temporary_follow_pan = false
		_is_panning = false
		_snap_to_follow_target()

func get_follow_target() -> Node3D:
	return _follow_target

func is_realtime_follow_active() -> bool:
	return _is_realtime_follow_active()

func is_temporary_follow_pan_active() -> bool:
	return _is_temporary_follow_pan

func _is_realtime_gameplay_mode() -> bool:
	return _runtime_mode == RUNTIME_MODE_GAME and _gameplay_control_mode == CONTROL_MODE_REAL_TIME

func _is_realtime_follow_active() -> bool:
	return (
		_is_realtime_gameplay_mode()
		and _follow_target != null
		and is_instance_valid(_follow_target)
	)

func _snap_to_follow_target() -> void:
	if not _is_realtime_follow_active():
		return

	var target_position := _follow_target.global_position
	position.x = target_position.x
	position.y = 0.0
	position.z = target_position.z

func _end_temporary_follow_pan() -> void:
	_is_temporary_follow_pan = false
	_is_panning = false
	_snap_to_follow_target()

func _store_local_camera_state() -> void:
	_local_position = position
	_local_height_m = _height_m
	_local_yaw = _yaw
	_local_pitch = _pitch

func _store_world_camera_state() -> void:
	_world_position = position
	_world_height_m = _height_m
	_world_yaw = _yaw
	_world_pitch = _pitch

func _apply_saved_camera_state(
	next_position: Vector3,
	next_height_m: float,
	next_yaw: float,
	next_pitch: float
) -> void:
	position = next_position
	position.y = 0.0
	_yaw = next_yaw
	_pitch = clampf(next_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	set_height_m(next_height_m)

func _get_event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	return tree.root.get_node_or_null("EventBus")
