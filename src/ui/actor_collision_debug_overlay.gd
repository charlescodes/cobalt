class_name ActorCollisionDebugOverlay
extends Node3D

const ACTOR_DEBUG_GROUP: StringName = &"actor_collision_debug_sources"

@export var debug_color: Color = Color(1.0, 0.55, 0.12, 0.9)
@export_range(8, 64, 1) var radial_segments: int = 24

var _debug_cylinders: Dictionary = {}

func _ready() -> void:
	visible = false

func _process(_delta: float) -> void:
	if visible:
		refresh_debug_cylinders()

func refresh_debug_cylinders() -> void:
	var active_ids: Dictionary = {}
	var tree := get_tree()
	if tree == null:
		return

	for source_node in tree.get_nodes_in_group(ACTOR_DEBUG_GROUP):
		var actor := source_node as Node3D
		if actor == null:
			continue
		var collision := actor.get_node_or_null("MovementCollisionShape3D") as CollisionShape3D
		var cylinder := collision.shape as CylinderShape3D if collision != null else null
		if cylinder == null:
			continue

		var actor_id := actor.get_instance_id()
		active_ids[actor_id] = true
		var debug_mesh := _debug_cylinders.get(actor_id) as MeshInstance3D
		var dimensions := Vector2(cylinder.radius, cylinder.height)
		if debug_mesh == null or debug_mesh.get_meta(&"cylinder_dimensions", Vector2.ZERO) != dimensions:
			if debug_mesh != null:
				debug_mesh.free()
			debug_mesh = _create_debug_cylinder(actor_id, cylinder.radius, cylinder.height)
			_debug_cylinders[actor_id] = debug_mesh
		debug_mesh.global_transform = actor.global_transform * collision.transform

	for actor_id in _debug_cylinders.keys():
		if active_ids.has(actor_id):
			continue
		var stale_mesh := _debug_cylinders.get(actor_id) as MeshInstance3D
		if stale_mesh != null and is_instance_valid(stale_mesh):
			stale_mesh.free()
		_debug_cylinders.erase(actor_id)

func get_debug_cylinder_count() -> int:
	return _debug_cylinders.size()

func _create_debug_cylinder(actor_id: int, radius: float, height: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ActorCollision_%d" % actor_id
	mesh_instance.mesh = _build_wire_cylinder(radius, height)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.set_meta(&"cylinder_dimensions", Vector2(radius, height))
	add_child(mesh_instance)
	return mesh_instance

func _build_wire_cylinder(radius: float, height: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var segments := maxi(radial_segments, 8)
	var half_height := height * 0.5
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_material())
	for index in range(segments):
		var angle_a := TAU * float(index) / float(segments)
		var angle_b := TAU * float(index + 1) / float(segments)
		var bottom_a := Vector3(cos(angle_a) * radius, -half_height, sin(angle_a) * radius)
		var bottom_b := Vector3(cos(angle_b) * radius, -half_height, sin(angle_b) * radius)
		var top_a := Vector3(bottom_a.x, half_height, bottom_a.z)
		var top_b := Vector3(bottom_b.x, half_height, bottom_b.z)
		mesh.surface_add_vertex(bottom_a)
		mesh.surface_add_vertex(bottom_b)
		mesh.surface_add_vertex(top_a)
		mesh.surface_add_vertex(top_b)
		if index % maxi(segments / 8, 1) == 0:
			mesh.surface_add_vertex(bottom_a)
			mesh.surface_add_vertex(top_a)
	mesh.surface_end()
	return mesh

func _debug_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = debug_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material
