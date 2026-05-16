class_name CameraRig
extends Node3D

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

var _height_m: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_panning: bool = false
var _is_looking: bool = false
var _pitch_pivot: Node3D
var _camera: Camera3D

func _ready() -> void:
	_height_m = clampf(start_height_m, min_height_m, max_height_m)
	_yaw = deg_to_rad(start_yaw_degrees)
	_pitch = deg_to_rad(clampf(start_pitch_degrees, min_pitch_degrees, max_pitch_degrees))
	_pitch_pivot = _get_or_create_pitch_pivot()
	_camera = _get_or_create_camera()
	_camera.current = true
	_apply_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_is_panning = false
		_is_looking = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func set_height_m(value: float) -> void:
	_height_m = clampf(value, min_height_m, max_height_m)
	_apply_camera_transform()

static func camera_distance_for_height(height_m: float, pitch_radians: float) -> float:
	var vertical_ratio := maxf(sin(-pitch_radians), 0.1)
	return maxf(height_m, 0.0) / vertical_ratio

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			_is_panning = event.pressed
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			_is_looking = event.pressed
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _is_looking else Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				set_height_m(_height_m + height_step_m)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				set_height_m(_height_m - height_step_m)
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
	position += ((-right * mouse_delta.x) + (forward * mouse_delta.y)) * pan_speed_m_per_pixel
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
