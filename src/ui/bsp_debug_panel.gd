class_name BspDebugPanel
extends PanelContainer

const BspDebugMapControllerScript := preload("res://src/debug/bsp_debug_map_controller.gd")
const BspModuleDataScript := preload("res://src/debug/bsp_module_data.gd")

@export var controller_path: NodePath = ^"../../BspDebugMapController"
@export var auto_apply: bool = true

var _controller: BspDebugMapControllerScript
var _width_slider: HSlider
var _depth_slider: HSlider
var _min_room_slider: HSlider
var _depth_spin_box: SpinBox
var _seed_spin_box: SpinBox
var _width_value_label: Label
var _depth_value_label: Label
var _min_room_value_label: Label
var _is_syncing: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_configure_layout()
	_configure_style()
	_build_controls()
	_controller = _resolve_controller()
	if _controller != null:
		_controller.bsp_debug_map_changed.connect(_on_bsp_debug_map_changed)
	_sync_from_controller()

func _process(_delta: float) -> void:
	if _controller == null:
		_controller = _resolve_controller()
		if _controller != null:
			_controller.bsp_debug_map_changed.connect(_on_bsp_debug_map_changed)
			_sync_from_controller()

func _configure_layout() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -316.0
	offset_top = 76.0
	offset_right = -16.0
	offset_bottom = 336.0

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.04, 0.045, 0.88)
	panel_style.border_color = Color(0.2, 0.24, 0.27, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", panel_style)

func _build_controls() -> void:
	if get_node_or_null("Margin") != null:
		return

	var margin := MarginContainer.new()
	margin.name = "Margin"
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "BSP DEBUG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)

	_width_value_label = _add_value_label(rows, "Width")
	_width_slider = _add_slider(rows, 8.0, 48.0, 1.0)
	_depth_value_label = _add_value_label(rows, "Depth")
	_depth_slider = _add_slider(rows, 8.0, 48.0, 1.0)
	_min_room_value_label = _add_value_label(rows, "Min Room")
	_min_room_slider = _add_slider(rows, 2.0, 12.0, 0.5)

	var depth_row := HBoxContainer.new()
	depth_row.add_theme_constant_override("separation", 8)
	rows.add_child(depth_row)
	var depth_label := Label.new()
	depth_label.text = "Split Depth"
	depth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_row.add_child(depth_label)
	_depth_spin_box = SpinBox.new()
	_depth_spin_box.min_value = 1.0
	_depth_spin_box.max_value = 8.0
	_depth_spin_box.step = 1.0
	_depth_spin_box.custom_minimum_size = Vector2(80.0, 0.0)
	depth_row.add_child(_depth_spin_box)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	rows.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_label)
	_seed_spin_box = SpinBox.new()
	_seed_spin_box.min_value = 0.0
	_seed_spin_box.max_value = 999999.0
	_seed_spin_box.step = 1.0
	_seed_spin_box.custom_minimum_size = Vector2(110.0, 0.0)
	seed_row.add_child(_seed_spin_box)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	rows.add_child(button_row)
	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(apply_button)
	var new_seed_button := Button.new()
	new_seed_button.text = "New Seed"
	new_seed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(new_seed_button)

	_width_slider.value_changed.connect(_on_value_changed)
	_depth_slider.value_changed.connect(_on_value_changed)
	_min_room_slider.value_changed.connect(_on_value_changed)
	_depth_spin_box.value_changed.connect(_on_value_changed)
	_seed_spin_box.value_changed.connect(_on_value_changed)
	apply_button.pressed.connect(_apply_from_controls)
	new_seed_button.pressed.connect(_randomize_seed)

func _add_value_label(parent: VBoxContainer, label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	return label

func _add_slider(parent: VBoxContainer, min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slider)
	return slider

func _sync_from_controller() -> void:
	if _controller == null:
		visible = false
		return

	var data := _controller.get_bsp_data()
	_is_syncing = true
	_width_slider.value = data.building_size_m.x
	_depth_slider.value = data.building_size_m.y
	_min_room_slider.value = data.min_room_size_m
	_depth_spin_box.value = data.max_split_depth
	_seed_spin_box.value = data.seed
	_is_syncing = false
	visible = _controller.is_bsp_enabled()
	_update_value_labels()

func _apply_from_controls() -> void:
	if _controller == null:
		return
	_controller.apply_bsp_parameters(
		Vector2(float(_width_slider.value), float(_depth_slider.value)),
		float(_min_room_slider.value),
		int(_depth_spin_box.value),
		int(_seed_spin_box.value)
	)

func _randomize_seed() -> void:
	_seed_spin_box.value = randi_range(1, 999999)
	if not auto_apply:
		_apply_from_controls()

func _on_value_changed(_value: float) -> void:
	_update_value_labels()
	if auto_apply and not _is_syncing:
		_apply_from_controls()

func _on_bsp_debug_map_changed(_enabled: bool, _data: Resource) -> void:
	_sync_from_controller()

func _update_value_labels() -> void:
	if _width_value_label != null:
		_width_value_label.text = "Width %.0fm" % _width_slider.value
	if _depth_value_label != null:
		_depth_value_label.text = "Depth %.0fm" % _depth_slider.value
	if _min_room_value_label != null:
		_min_room_value_label.text = "Min Room %.1fm" % _min_room_slider.value

func _resolve_controller() -> BspDebugMapControllerScript:
	return get_node_or_null(controller_path) as BspDebugMapControllerScript
