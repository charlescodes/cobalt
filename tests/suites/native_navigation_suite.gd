extends RefCounted

const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var nav: Dictionary = ctx.create_square_nav_map()
	var navigation_map: RID = nav["map"]
	var navigation_region: RID = nav["region"]
	await ctx.wait_for_navigation_map(navigation_map)

	var reachable_path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		Vector3(0.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 2.0)
	)
	if reachable_path.is_empty():
		ctx.free_nav_map(navigation_map, navigation_region)
		return ctx.fail("MoveTargetResolver did not return a native nav path across the square region.")

	var off_nav_path := MoveTargetResolverScript.navigation_path(
		navigation_map,
		Vector3(0.0, 0.0, 0.0),
		Vector3(6.0, 0.0, 6.0)
	)
	if not off_nav_path.is_empty():
		ctx.free_nav_map(navigation_map, navigation_region)
		return ctx.fail("MoveTargetResolver accepted a destination outside the nav snap tolerance.")

	var source: InteractionTargetScript = ctx.make_interaction_target(
		InteractionActionResolverScript.DOMAIN_WORLD_OBJECT,
		WorldObjectDataScript.new(&"pc_nav", &"player_character", Vector3.ZERO)
	)
	var destination: InteractionTargetScript = ctx.make_interaction_target(
		InteractionActionResolverScript.DOMAIN_MOVE_TARGET,
		MoveTargetDataScript.new(Vector3(2.0, 0.0, 2.0))
	)
	if not MoveTargetResolverScript.can_select_destination(destination):
		source.free()
		destination.free()
		ctx.free_nav_map(navigation_map, navigation_region)
		return ctx.fail("MoveTargetResolver did not accept a move_target destination.")
	if not MoveTargetResolverScript.can_move(source, destination, navigation_map):
		source.free()
		destination.free()
		ctx.free_nav_map(navigation_map, navigation_region)
		return ctx.fail("MoveTargetResolver did not validate movement over the native nav map.")

	(destination.target_data as MoveTargetDataScript).position = Vector3(6.0, 0.0, 6.0)
	if MoveTargetResolverScript.can_move(source, destination, navigation_map):
		source.free()
		destination.free()
		ctx.free_nav_map(navigation_map, navigation_region)
		return ctx.fail("MoveTargetResolver accepted an unreachable off-nav destination.")

	source.free()
	destination.free()
	ctx.free_nav_map(navigation_map, navigation_region)
	return true
