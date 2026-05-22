class_name CameraCompass
extends Control

@export var camera_path: NodePath = ^"../../CameraRig/PitchPivot/Camera3D"
@export var compass_size_px: float = 50.0

var _camera: Camera3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_layout()
	_camera = get_node_or_null(camera_path) as Camera3D

func _process(_delta: float) -> void:
	if _camera == null:
		_camera = get_node_or_null(camera_path) as Camera3D
	queue_redraw()

func _draw() -> void:
	var draw_size := minf(size.x, size.y)
	if draw_size <= 1.0:
		return

	var center := size * 0.5
	var radius := (draw_size * 0.5) - 2.0
	draw_circle(center, radius, Color(0.035, 0.04, 0.045, 0.82))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.78, 0.82, 0.78, 0.92), 1.25)
	_draw_cardinals(center, radius)
	_draw_camera_arrow(center, radius)

func _configure_layout() -> void:
	custom_minimum_size = Vector2(compass_size_px, compass_size_px)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -66.0
	offset_top = 16.0
	offset_right = -16.0
	offset_bottom = 66.0

func _draw_cardinals(center: Vector2, radius: float) -> void:
	var font := get_theme_default_font()
	var font_size := 10
	_draw_centered_text(font, "N", center + Vector2(0.0, -radius + 9.0), font_size, Color(0.95, 0.98, 0.95, 1.0))
	_draw_centered_text(font, "E", center + Vector2(radius - 8.0, 3.0), font_size, Color(0.84, 0.88, 0.84, 1.0))
	_draw_centered_text(font, "S", center + Vector2(0.0, radius - 4.0), font_size, Color(0.84, 0.88, 0.84, 1.0))
	_draw_centered_text(font, "W", center + Vector2(-radius + 8.0, 3.0), font_size, Color(0.84, 0.88, 0.84, 1.0))

func _draw_camera_arrow(center: Vector2, radius: float) -> void:
	var forward := Vector3.FORWARD
	if _camera != null:
		forward = -_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var direction := Vector2(forward.x, forward.z).normalized()
	var tip := center + (direction * (radius - 13.0))
	var tail := center - (direction * 5.0)
	draw_line(tail, tip, Color(1.0, 0.82, 0.18, 1.0), 2.5, true)
	draw_circle(tip, 3.0, Color(1.0, 0.82, 0.18, 1.0))
	draw_circle(center, 2.0, Color(0.95, 0.98, 0.95, 1.0))

func _draw_centered_text(
	font: Font,
	text: String,
	position: Vector2,
	font_size: int,
	color: Color
) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(
		font,
		position - Vector2(text_size.x * 0.5, text_size.y * -0.25),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)
