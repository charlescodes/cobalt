extends RefCounted

const InteractionTargetScript := preload("res://src/interaction/interaction_target.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const MoveTargetDataScript := preload("res://src/movement/move_target_data.gd")
const MoveTargetResolverScript := preload("res://src/movement/move_target_resolver.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")
const BlockoutObjectViewScript := preload("res://src/objects/blockout_object_view.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var pc_position := Vector3(2.0, 0.0, 3.0)
	var pc_size := Vector3(0.5, 1.83, 0.5)
	var pc_data := WorldObjectDataScript.new(
		&"pc_001",
		&"player_character",
		pc_position,
		pc_size,
		Color(0.1, 0.25, 1.0, 1.0),
		true
	)
	if pc_data.position != pc_position:
		return ctx.fail("WorldObjectData did not preserve the Vector3 position.")
	if pc_data.size_m != pc_size:
		return ctx.fail("Player character dimensions are incorrect.")

	var pc_view := BlockoutObjectViewScript.new()
	pc_view.object_data = pc_data
	ctx.root().add_child(pc_view)
	if pc_view.position != pc_position:
		pc_view.free()
		return ctx.fail("BlockoutObjectView did not use WorldObjectData.position.")
	if pc_view.get_node_or_null("GridMovementAnimator") != null:
		pc_view.free()
		return ctx.fail("BlockoutObjectView should not create grid movement components.")
	var pc_agent := pc_view.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if pc_agent == null:
		pc_view.free()
		return ctx.fail("BlockoutObjectView did not create a NavigationAgent3D.")
	if pc_view.get_navigation_agent() != pc_agent:
		pc_view.free()
		return ctx.fail("BlockoutObjectView did not expose its NavigationAgent3D helper.")
	if not is_equal_approx(pc_agent.target_desired_distance, 0.1):
		pc_view.free()
		return ctx.fail("NavigationAgent3D target distance is not configured.")

	var pc_body := pc_view.get_node_or_null("Body") as MeshInstance3D
	if pc_body == null:
		pc_view.free()
		return ctx.fail("BlockoutObjectView did not create Body mesh.")
	var pc_body_offset := Vector3(0.0, pc_size.y * 0.5, 0.0)
	if pc_body.position != pc_body_offset:
		pc_view.free()
		return ctx.fail("Player character mesh is not centered above its feet.")

	var pc_mesh := pc_body.mesh as BoxMesh
	if pc_mesh == null or pc_mesh.size != pc_size:
		pc_view.free()
		return ctx.fail("Player character mesh dimensions are incorrect.")

	var pc_target := pc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if pc_target == null:
		pc_view.free()
		return ctx.fail("Player character did not create an InteractionTarget.")
	if not pc_target.is_in_group(InteractionTargetScript.GROUP_NAME):
		pc_view.free()
		return ctx.fail("InteractionTarget did not join the expected group.")
	if pc_target.target_domain != &"world_object":
		pc_view.free()
		return ctx.fail("Player character InteractionTarget has the wrong domain.")
	if not (pc_target.target_data is WorldObjectDataScript):
		pc_view.free()
		return ctx.fail("Player character InteractionTarget does not carry WorldObjectData.")
	if not ctx.has_action(InteractionActionResolverScript.get_actions(pc_target), InteractionActionResolverScript.ACTION_EXAMINE):
		pc_view.free()
		return ctx.fail("World object interaction target should expose Examine.")
	if not ctx.has_action(InteractionActionResolverScript.get_actions(pc_target), InteractionActionResolverScript.ACTION_MOVE):
		pc_view.free()
		return ctx.fail("Player character interaction target should expose Move.")
	if not MoveTargetResolverScript.can_start_move(pc_target):
		pc_view.free()
		return ctx.fail("MoveTargetResolver did not accept the player character as a move source.")

	var examine_output := InteractionActionResolverScript.build_examine_output(pc_target)
	if examine_output.get("domain") != &"world_object":
		pc_view.free()
		return ctx.fail("Examine output has the wrong domain.")
	if examine_output.get("object_kind") != &"player_character":
		pc_view.free()
		return ctx.fail("Examine output has the wrong object kind.")
	if examine_output.get("object_id") != &"pc_001":
		pc_view.free()
		return ctx.fail("Examine output has the wrong object id.")

	var move_target_data := MoveTargetDataScript.new(Vector3(1.25, 0.0, -2.5))
	if move_target_data.position != Vector3(1.25, 0.0, -2.5):
		pc_view.free()
		return ctx.fail("MoveTargetData did not preserve the Vector3 position.")

	var npc_data := WorldObjectDataScript.new(
		&"npc_001",
		&"non_player_character",
		Vector3(1.0, 0.0, 1.0),
		pc_size,
		Color(0.45, 0.45, 0.45, 1.0),
		true
	)
	var npc_view := BlockoutObjectViewScript.new()
	npc_view.object_data = npc_data
	ctx.root().add_child(npc_view)
	var npc_target := npc_view.get_node_or_null("InteractionTarget") as InteractionTargetScript
	if ctx.has_action(InteractionActionResolverScript.get_actions(npc_target), InteractionActionResolverScript.ACTION_MOVE):
		npc_view.free()
		pc_view.free()
		return ctx.fail("NPC interaction target should not expose Move.")
	if MoveTargetResolverScript.can_start_move(npc_target):
		npc_view.free()
		pc_view.free()
		return ctx.fail("MoveTargetResolver accepted an NPC as a move source.")

	npc_view.free()
	pc_view.free()
	return true
