extends RefCounted

const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")
const FloorDataScript := preload("res://src/maps/floor_data.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MapBuilderScript := preload("res://src/maps/map_builder.gd")
const MapDataScript := preload("res://src/maps/map_data.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var floor := FloorDataScript.new(
		&"test_floor",
		Vector3(0.0, -0.05, 0.0),
		Vector3(4.0, 0.1, 4.0),
		Color(0.2, 0.3, 0.25, 1.0)
	)
	var wall := WallSegmentDataScript.new(
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
	var floors: Array[FloorDataScript] = []
	var walls: Array[WallSegmentDataScript] = []
	var objects: Array[WorldObjectDataScript] = []
	floors.append(floor)
	walls.append(wall)
	objects.append(object_data)
	var map_data := MapDataScript.new("test_map", floors, walls, objects)

	if map_data.map_id != "test_map" or map_data.floors[0] != floor:
		return ctx.fail("MapData did not preserve floor data.")
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

	var floor_body := generated_map.get_node_or_null("StaticFloors/test_floor") as StaticBody3D
	if floor_body == null:
		parent.free()
		return ctx.fail("MapBuilder did not create a StaticBody3D floor.")
	if floor_body.position != floor.position:
		parent.free()
		return ctx.fail("Generated floor did not use FloorData.position.")
	var floor_mesh := floor_body.get_node_or_null("Mesh") as MeshInstance3D
	if floor_mesh == null:
		parent.free()
		return ctx.fail("Generated floor is missing a mesh instance.")
	var floor_box := floor_mesh.mesh as BoxMesh
	if floor_box == null or floor_box.size != floor.size_m:
		parent.free()
		return ctx.fail("Generated floor mesh did not use FloorData.size_m.")
	var floor_collision := floor_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if floor_collision == null or not (floor_collision.shape is BoxShape3D):
		parent.free()
		return ctx.fail("Generated floor is missing static box collision.")

	var floor_target := floor_body.get_node_or_null("FloorMoveTarget") as InteractionTargetScript
	if floor_target == null:
		parent.free()
		return ctx.fail("Generated floor is missing a movement target.")
	if floor_target.can_highlight or not floor_target.input_ray_pickable:
		parent.free()
		return ctx.fail("Generated floor movement target has wrong interaction flags.")
	if not (floor_target.target_data is MoveTargetDataScript):
		parent.free()
		return ctx.fail("Generated floor movement target does not carry MoveTargetData.")
	var target_collision := floor_target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if target_collision == null or not (target_collision.shape is BoxShape3D):
		parent.free()
		return ctx.fail("Generated floor movement target is missing area collision.")

	var wall_node := generated_map.get_node_or_null("StaticWalls/Wall_00") as Node3D
	if wall_node == null:
		parent.free()
		return ctx.fail("MapBuilder did not create a static wall node.")
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
