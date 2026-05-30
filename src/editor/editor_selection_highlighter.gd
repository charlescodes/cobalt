class_name EditorSelectionHighlighter
extends Node

const SHELL_NODE_NAME: StringName = &"EditorSelectionShell"
const SHELL_META_KEY: StringName = &"is_editor_selection_highlight_shell"
const HOVER_SHELL_META_KEY: StringName = &"is_hover_highlight_shell"

@export var highlight_color: Color = Color(0.1, 0.78, 1.0, 0.42)
@export var shell_scale: Vector3 = Vector3(1.06, 1.06, 1.06)

var _shells: Array[MeshInstance3D] = []

func highlight(root: Node) -> void:
	clear()
	if root == null:
		return

	var source_meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, source_meshes)
	var material := _build_material()
	for source_mesh in source_meshes:
		_add_shell(source_mesh, material)

func clear() -> void:
	for shell in _shells:
		if is_instance_valid(shell):
			shell.free()
	_shells.clear()

func _collect_meshes(root: Node, source_meshes: Array[MeshInstance3D]) -> void:
	if root.has_meta(SHELL_META_KEY) or root.has_meta(HOVER_SHELL_META_KEY):
		return

	var mesh_instance := root as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
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

func _build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = highlight_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
