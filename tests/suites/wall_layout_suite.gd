extends RefCounted

const WallLayoutViewScript := preload("res://src/environment/wall_layout_view.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WallVisualResolverScript := preload("res://src/environment/wall_visual_resolver.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var wall_data := WallDataScript.new(
		Vector3(-1.0, 0.0, 2.0),
		Vector3(2.0, 0.0, 2.0),
		2.2,
		0.18,
		Color(0.35, 0.34, 0.32, 1.0)
	)
	if not wall_data.is_valid_wall():
		return ctx.fail("WallData rejected a valid floor-plane line.")

	var wall_endpoints := WallVisualResolverScript.visual_endpoints(wall_data)
	if wall_endpoints.size() != 2 or wall_endpoints[0] != wall_data.start_position:
		return ctx.fail("WallVisualResolver did not return wall line endpoints.")
	if not is_equal_approx(WallVisualResolverScript.visual_length(wall_data), 3.0):
		return ctx.fail("WallVisualResolver returned the wrong wall length.")
	if WallVisualResolverScript.visual_size(wall_data) != Vector3(0.18, 2.2, 3.0):
		return ctx.fail("WallVisualResolver returned the wrong wall box size.")

	var wall_layout := WallLayoutViewScript.new()
	wall_layout.rebake_navigation_on_apply = false
	wall_layout.walls.append(wall_data)
	ctx.root().add_child(wall_layout)
	wall_layout.apply_layout()
	var wall_visual_root := wall_layout.get_node_or_null("WallVisuals")
	if wall_visual_root == null or wall_visual_root.get_child_count() != 1:
		wall_layout.free()
		return ctx.fail("WallLayoutView did not create wall visuals.")
	var wall := wall_visual_root.get_child(0) as Node3D
	if wall == null:
		wall_layout.free()
		return ctx.fail("WallLayoutView did not create a Node3D wall root.")
	if not is_zero_approx(wall.rotation.y):
		wall_layout.free()
		return ctx.fail("WallLayoutView should not rotate generated wall roots.")
	var wall_mesh_instance := wall.get_node_or_null("Mesh") as MeshInstance3D
	if wall_mesh_instance == null:
		wall_layout.free()
		return ctx.fail("WallLayoutView visual is missing a MeshInstance3D.")
	var wall_box_mesh := wall_mesh_instance.mesh as BoxMesh
	if wall_box_mesh == null:
		wall_layout.free()
		return ctx.fail("WallLayoutView visual is not a BoxMesh.")
	if not is_equal_approx(wall_box_mesh.size.y, wall_data.height_m):
		wall_layout.free()
		return ctx.fail("WallLayoutView visual does not use the configured wall height.")
	if not is_equal_approx(wall_box_mesh.size.x, wall_data.thickness_m):
		wall_layout.free()
		return ctx.fail("WallLayoutView visual does not use the configured wall thickness.")
	if not is_equal_approx(wall_box_mesh.size.z, WallVisualResolverScript.visual_length(wall_data)):
		wall_layout.free()
		return ctx.fail("WallLayoutView visual does not use the configured wall length.")
	var static_body := wall.get_node_or_null("StaticBody3D") as StaticBody3D
	if static_body == null:
		wall_layout.free()
		return ctx.fail("WallLayoutView did not create static wall collision.")
	var wall_collision := static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if wall_collision == null or not (wall_collision.shape is BoxShape3D):
		wall_layout.free()
		return ctx.fail("WallLayoutView static wall collision is missing a BoxShape3D.")
	wall_layout.free()
	return true
