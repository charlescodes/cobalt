class_name FloatingPanel
extends PanelContainer

signal close_requested()
signal collapsed_changed(is_collapsed: bool)

@export var title: String = "Panel":
	set(value):
		title = value
		_sync_chrome()
@export var default_position: Vector2 = Vector2(16.0, 16.0)
@export var default_size: Vector2 = Vector2(320.0, 240.0)
@export var min_panel_size: Vector2 = Vector2(220.0, 120.0)
@export var start_visible: bool = true
@export var allow_close: bool = false:
	set(value):
		allow_close = value
		_sync_chrome()
@export var allow_collapse: bool = true:
	set(value):
		allow_collapse = value
		_sync_chrome()
@export var allow_resize: bool = true:
	set(value):
		allow_resize = value
		_sync_chrome()

var _title_label: Label
var _collapse_button: Button
var _close_button: Button
var _content_scroll: ScrollContainer
var _content_root: VBoxContainer
var _resize_row: HBoxContainer
var _resize_grip: Button
var _content_built: bool = false
var _is_collapsed: bool = false
var _is_dragging: bool = false
var _is_resizing: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = maxi(z_index, 20)
	custom_minimum_size = min_panel_size
	position = default_position
	size = Vector2(
		maxf(default_size.x, min_panel_size.x),
		maxf(default_size.y, min_panel_size.y)
	)
	_configure_style()
	_ensure_chrome()
	if not _content_built:
		_content_built = true
		_build_panel_content(_content_root)
	_sync_chrome()
	visible = start_visible
	_on_floating_panel_ready()
	call_deferred("fit_to_viewport")

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT and not button_event.pressed:
			_is_dragging = false
			_is_resizing = false
			return

	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if _is_dragging:
			position += motion_event.relative
			fit_to_viewport()
			_mark_input_handled()
		elif _is_resizing:
			size = Vector2(
				maxf(min_panel_size.x, size.x + motion_event.relative.x),
				maxf(min_panel_size.y, size.y + motion_event.relative.y)
			)
			fit_to_viewport()
			_mark_input_handled()

func get_content_root() -> VBoxContainer:
	return _content_root

func set_collapsed(is_collapsed: bool) -> void:
	if _is_collapsed == is_collapsed:
		return

	_is_collapsed = is_collapsed
	_sync_chrome()
	emit_signal(&"collapsed_changed", _is_collapsed)

func is_collapsed() -> bool:
	return _is_collapsed

func fit_to_viewport() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return

	var viewport_size := get_viewport_rect().size
	size.x = minf(maxf(size.x, min_panel_size.x), maxf(min_panel_size.x, viewport_size.x))
	size.y = minf(maxf(size.y, min_panel_size.y), maxf(min_panel_size.y, viewport_size.y))
	position.x = clampf(position.x, 0.0, maxf(0.0, viewport_size.x - size.x))
	position.y = clampf(position.y, 0.0, maxf(0.0, viewport_size.y - size.y))

func _build_panel_content(_content: VBoxContainer) -> void:
	pass

func _on_floating_panel_ready() -> void:
	pass

func _ensure_chrome() -> void:
	if get_node_or_null("ChromeMargin") != null:
		_title_label = get_node_or_null("ChromeMargin/Chrome/TitleBar/Title") as Label
		_collapse_button = get_node_or_null("ChromeMargin/Chrome/TitleBar/CollapseButton") as Button
		_close_button = get_node_or_null("ChromeMargin/Chrome/TitleBar/CloseButton") as Button
		_content_scroll = get_node_or_null("ChromeMargin/Chrome/ContentScroll") as ScrollContainer
		_content_root = get_node_or_null("ChromeMargin/Chrome/ContentScroll/Content") as VBoxContainer
		_resize_row = get_node_or_null("ChromeMargin/Chrome/ResizeRow") as HBoxContainer
		_resize_grip = get_node_or_null("ChromeMargin/Chrome/ResizeRow/ResizeGrip") as Button
		return

	var margin := MarginContainer.new()
	margin.name = "ChromeMargin"
	add_child(margin)

	var chrome := VBoxContainer.new()
	chrome.name = "Chrome"
	chrome.add_theme_constant_override("separation", 6)
	margin.add_child(chrome)

	var title_bar := HBoxContainer.new()
	title_bar.name = "TitleBar"
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.add_theme_constant_override("separation", 6)
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	chrome.add_child(title_bar)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(_title_label)

	_collapse_button = Button.new()
	_collapse_button.name = "CollapseButton"
	_collapse_button.custom_minimum_size = Vector2(26.0, 24.0)
	_collapse_button.tooltip_text = "Collapse"
	_collapse_button.pressed.connect(_toggle_collapsed)
	title_bar.add_child(_collapse_button)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "x"
	_close_button.custom_minimum_size = Vector2(26.0, 24.0)
	_close_button.tooltip_text = "Close"
	_close_button.pressed.connect(_close_panel)
	title_bar.add_child(_close_button)

	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "ContentScroll"
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.custom_minimum_size = Vector2(0.0, maxf(64.0, default_size.y - 74.0))
	chrome.add_child(_content_scroll)

	_content_root = VBoxContainer.new()
	_content_root.name = "Content"
	_content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_root.add_theme_constant_override("separation", 6)
	_content_scroll.add_child(_content_root)

	_resize_row = HBoxContainer.new()
	_resize_row.name = "ResizeRow"
	chrome.add_child(_resize_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resize_row.add_child(spacer)

	_resize_grip = Button.new()
	_resize_grip.name = "ResizeGrip"
	_resize_grip.text = "Resize"
	_resize_grip.flat = true
	_resize_grip.tooltip_text = "Drag to resize"
	_resize_grip.custom_minimum_size = Vector2(72.0, 22.0)
	_resize_grip.gui_input.connect(_on_resize_grip_gui_input)
	_resize_row.add_child(_resize_grip)

func _sync_chrome() -> void:
	if _title_label != null:
		_title_label.text = title
	if _collapse_button != null:
		_collapse_button.visible = allow_collapse
		_collapse_button.text = "+" if _is_collapsed else "-"
	if _close_button != null:
		_close_button.visible = allow_close
	if _content_scroll != null:
		_content_scroll.visible = not _is_collapsed
	if _resize_row != null:
		_resize_row.visible = allow_resize and not _is_collapsed

func _toggle_collapsed() -> void:
	set_collapsed(not _is_collapsed)

func _close_panel() -> void:
	hide()
	emit_signal(&"close_requested")

func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = button_event.pressed
			_mark_input_handled()

func _on_resize_grip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			_is_resizing = button_event.pressed
			_mark_input_handled()

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.04, 0.045, 0.92)
	panel_style.border_color = Color(0.2, 0.25, 0.28, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", panel_style)

func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
