extends RefCounted

const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const GroundDataScript := preload("res://src/environment/ground_data.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const WallDataScript := preload("res://src/environment/wall_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var ground := GroundDataScript.new(
		&"test_ground",
		Vector3(0.0, -0.05, 0.0),
		Vector3(4.0, 0.1, 4.0),
		Color(0.2, 0.3, 0.25, 1.0)
	)
	var wall := WallDataScript.new(
		Vector3(-1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 1.0),
		2.0,
		0.2,
		Color(0.3, 0.3, 0.3, 1.0)
	)
	var object_data := WorldObjectDataScript.new(
		&"pc_test",
		&"player_character",
		Vector3(0.5, 0.0, 0.5),
		Vector3(0.5, 1.8, 0.5),
		Color.BLUE
	)
	var grounds: Array[GroundDataScript] = []
	var walls: Array[WallDataScript] = []
	var objects: Array[WorldObjectDataScript] = []
	grounds.append(ground)
	walls.append(wall)
	objects.append(object_data)
	var map_data := MapDataScript.new("test_map", grounds, walls, objects)

	if map_data.map_id != "test_map" or map_data.grounds[0] != ground:
		return ctx.fail("MapData did not preserve ground data.")
	if map_data.static_walls[0] != wall or map_data.world_objects[0] != object_data:
		return ctx.fail("MapData did not preserve wall or world-object data.")

	var parent := Node3D.new()
	ctx.root().add_child(parent)
	var generated_map := MapBuilderScript.build(map_data, parent)
	if generated_map == null or generated_map.name != "GeneratedMap":
		parent.free()
		return ctx.fail("MapBuilder did not return GeneratedMap.")
	if parent.get_node_or_null("GeneratedMap") != generated_map:
		parent.free()
		return ctx.fail("MapBuilder did not add GeneratedMap to the parent.")

	var ground_body := generated_map.get_node_or_null("StaticGrounds/test_ground") as StaticBody3D
	if ground_body == null:
		parent.free()
		return ctx.fail("MapBuilder did not create a StaticBody3D ground.")
	if ground_body.position != ground.position:
		parent.free()
		return ctx.fail("Generated ground did not use GroundData.position.")
	var ground_mesh := ground_body.get_node_or_null("Mesh") as MeshInstance3D
	if ground_mesh == null:
		parent.free()
		return ctx.fail("Generated ground is missing a mesh instance.")
	var ground_box := ground_mesh.mesh as BoxMesh
	if ground_box == null or ground_box.size != ground.size_m:
		parent.free()
		return ctx.fail("Generated ground mesh did not use GroundData.size_m.")
	var ground_collision := ground_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if ground_collision == null or not (ground_collision.shape is BoxShape3D):
		parent.free()
		return ctx.fail("Generated ground is missing static box collision.")

	var ground_target := ground_body.get_node_or_null("GroundMoveTarget") as InteractionTargetScript
	if ground_target == null:
		parent.free()
		return ctx.fail("Generated ground is missing a movement target.")
	if ground_target.can_highlight or not ground_target.input_ray_pickable:
		parent.free()
		return ctx.fail("Generated ground movement target has wrong interaction flags.")
	if not (ground_target.target_data is MoveTargetDataScript):
		parent.free()
		return ctx.fail("Generated ground movement target does not carry MoveTargetData.")
	var target_collision := ground_target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if target_collision == null or not (target_collision.shape is BoxShape3D):
		parent.free()
		return ctx.fail("Generated ground movement target is missing area collision.")

	var wall_node := generated_map.get_node_or_null("StaticWalls/Wall_00") as Node3D
	if wall_node == null:
		parent.free()
		return ctx.fail("MapBuilder did not create a static wall node.")
	if not is_zero_approx(wall_node.rotation.y):
		parent.free()
		return ctx.fail("MapBuilder should not rotate generated wall roots.")
	var wall_mesh := wall_node.get_node_or_null("Mesh") as MeshInstance3D
	if wall_mesh == null or not (wall_mesh.mesh is BoxMesh):
		parent.free()
		return ctx.fail("Generated static wall is missing its box mesh.")
	var wall_body := wall_node.get_node_or_null("StaticBody3D") as StaticBody3D
	if wall_body == null:
		parent.free()
		return ctx.fail("Generated static wall is missing StaticBody3D.")
	var wall_collision := wall_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if wall_collision == null or not (wall_collision.shape is BoxShape3D):
		parent.free()
		return ctx.fail("Generated static wall is missing StaticBody3D collision.")

	var object_view := generated_map.get_node_or_null("WorldObjects/pc_test") as BlockoutObjectViewScript
	if object_view == null or object_view.object_data != object_data:
		parent.free()
		return ctx.fail("MapBuilder did not instantiate BlockoutObjectView with WorldObjectData.")
	if object_view.position != object_data.position:
		parent.free()
		return ctx.fail("Generated BlockoutObjectView did not use WorldObjectData.position.")

	parent.free()
	return true
