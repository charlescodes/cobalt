class_name HoverHighlighter
extends Node

const SHELL_NODE_NAME: StringName = &"HoverShell"
const SHELL_META_KEY: StringName = &"is_hover_highlight_shell"

@export var root_path: NodePath = ^".."
@export var highlight_color: Color = Color(1.0, 0.9, 0.05, 0.5)
@export var shell_scale: Vector3 = Vector3(1.04, 1.04, 1.04)

var _is_highlighted: bool = false
var _shells: Array[MeshInstance3D] = []

func set_highlighted(is_highlighted: bool) -> void:
	if _is_highlighted == is_highlighted:
		return

	if is_highlighted:
		_apply_highlight()
	else:
		clear_highlight()

func clear_highlight() -> void:
	for shell in _shells:
		if is_instance_valid(shell):
			shell.free()

	_shells.clear()
	_is_highlighted = false

static func build_highlight_material(color: Color = Color(1.0, 0.9, 0.05, 0.5)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _apply_highlight() -> void:
	clear_highlight()

	var root := get_node_or_null(root_path)
	if root == null:
		return

	var source_meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, source_meshes)

	var material := build_highlight_material(highlight_color)
	for source_mesh in source_meshes:
		_add_shell(source_mesh, material)

	_is_highlighted = not _shells.is_empty()

func _collect_meshes(root: Node, source_meshes: Array[MeshInstance3D]) -> void:
	if root.has_meta(SHELL_META_KEY):
		return

	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null:
			source_meshes.append(mesh_instance)

	for child in root.get_children():
		_collect_meshes(child, source_meshes)

func _add_shell(source_mesh: MeshInstance3D, material: StandardMaterial3D) -> void:
	var shell := MeshInstance3D.new()
	shell.name = String(SHELL_NODE_NAME)
	shell.mesh = source_mesh.mesh
	shell.layers = source_mesh.layers
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.material_override = material
	shell.scale = shell_scale
	shell.set_meta(SHELL_META_KEY, true)
	source_mesh.add_child(shell)
	_shells.append(shell)
