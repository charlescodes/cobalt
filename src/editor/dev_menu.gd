class_name DevMenu
extends PanelContainer

signal game_mode_requested
signal editor_mode_requested
signal save_map_requested(filename: String)
signal load_map_requested(filename: String)

const DEFAULT_FILENAME := "editor_blank"

var _filename_edit: LineEdit
var _game_mode_button: Button
var _editor_mode_button: Button
var _status_label: Label

func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_configure_position()
	_configure_style()
	_ensure_layout()

func show_menu() -> void:
	show()
	grab_focus()

func hide_menu() -> void:
	hide()

func toggle_menu() -> void:
	visible = not visible
	if visible:
		grab_focus()

func get_filename() -> String:
	return _filename_edit.text if _filename_edit != null else DEFAULT_FILENAME

func set_mode(mode: StringName) -> void:
	if _game_mode_button != null:
		_game_mode_button.disabled = mode == &"game"
	if _editor_mode_button != null:
		_editor_mode_button.disabled = mode == &"editor"

func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

func _configure_position() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -170.0
	offset_top = -116.0
	offset_right = 170.0
	offset_bottom = 116.0

func _configure_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.05, 0.052, 0.96)
	panel_style.border_color = Color(0.27, 0.3, 0.29, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", panel_style)

func _ensure_layout() -> void:
	if _filename_edit != null:
		return

	var layout := VBoxContainer.new()
	layout.name = "MenuLayout"
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	var mode_row := HBoxContainer.new()
	mode_row.name = "ModeRow"
	mode_row.add_theme_constant_override("separation", 8)
	layout.add_child(mode_row)

	_game_mode_button = Button.new()
	_game_mode_button.name = "GameModeButton"
	_game_mode_button.text = "Game Mode"
	_game_mode_button.custom_minimum_size = Vector2(150.0, 34.0)
	_game_mode_button.pressed.connect(_on_game_mode_pressed)
	mode_row.add_child(_game_mode_button)

	_editor_mode_button = Button.new()
	_editor_mode_button.name = "EditorModeButton"
	_editor_mode_button.text = "Editor Mode"
	_editor_mode_button.custom_minimum_size = Vector2(150.0, 34.0)
	_editor_mode_button.pressed.connect(_on_editor_mode_pressed)
	mode_row.add_child(_editor_mode_button)

	_filename_edit = LineEdit.new()
	_filename_edit.name = "Filename"
	_filename_edit.text = DEFAULT_FILENAME
	_filename_edit.placeholder_text = "map_name"
	_filename_edit.custom_minimum_size = Vector2(316.0, 32.0)
	layout.add_child(_filename_edit)

	var file_row := HBoxContainer.new()
	file_row.name = "FileRow"
	file_row.add_theme_constant_override("separation", 8)
	layout.add_child(file_row)

	var save_button := Button.new()
	save_button.name = "SaveMapButton"
	save_button.text = "Save Map"
	save_button.custom_minimum_size = Vector2(150.0, 34.0)
	save_button.pressed.connect(_on_save_map_pressed)
	file_row.add_child(save_button)

	var load_button := Button.new()
	load_button.name = "LoadMapButton"
	load_button.text = "Load Map"
	load_button.custom_minimum_size = Vector2(150.0, 34.0)
	load_button.pressed.connect(_on_load_map_pressed)
	file_row.add_child(load_button)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status_label)

func _on_game_mode_pressed() -> void:
	emit_signal(&"game_mode_requested")

func _on_editor_mode_pressed() -> void:
	emit_signal(&"editor_mode_requested")

func _on_save_map_pressed() -> void:
	emit_signal(&"save_map_requested", get_filename())

func _on_load_map_pressed() -> void:
	emit_signal(&"load_map_requested", get_filename())
