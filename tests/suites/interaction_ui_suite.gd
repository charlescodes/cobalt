extends RefCounted

const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const InteractionLogPanelScript := preload("res://src/ui/interaction_log_panel.gd")
const WorldObjectDataScript := preload("res://src/objects/world_object_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var root_event_bus: Node = ctx.ensure_root_event_bus()
	var highlight_material: StandardMaterial3D = HoverHighlighterScript.build_highlight_material()
	if highlight_material.albedo_color.a >= 1.0:
		return ctx.fail("HoverHighlighter did not build a transparent material.")
	highlight_material = null

	var mesh := MeshInstance3D.new()
	mesh.mesh = CylinderMesh.new()
	mesh.material_override = StandardMaterial3D.new()
	var highlighter := HoverHighlighterScript.new()
	highlighter.root_path = ^".."
	mesh.add_child(highlighter)
	ctx.root().add_child(mesh)
	highlighter.set_highlighted(true)
	var shell := mesh.get_node_or_null("HoverShell") as MeshInstance3D
	if shell == null:
		mesh.free()
		return ctx.fail("HoverHighlighter did not create a shell mesh.")
	var shell_material := shell.material_override as StandardMaterial3D
	if shell_material == null or shell_material.albedo_color.a >= 1.0:
		mesh.free()
		return ctx.fail("HoverHighlighter shell is not using a transparent material.")
	highlighter.clear_highlight()
	if mesh.get_node_or_null("HoverShell") != null:
		mesh.free()
		return ctx.fail("HoverHighlighter did not remove shell meshes after clearing.")
	mesh.free()

	var interaction_controller := InteractionControllerScript.new()
	ctx.root().add_child(interaction_controller)
	interaction_controller._ready()
	interaction_controller._handle_interaction_pointer_capture_changed(true)
	if not interaction_controller.is_interaction_pointer_captured():
		interaction_controller.free()
		return ctx.fail("InteractionController did not pause for interaction pointer capture.")
	interaction_controller._handle_interaction_pointer_capture_changed(false)
	if interaction_controller.is_interaction_pointer_captured():
		interaction_controller.free()
		return ctx.fail("InteractionController did not resume after pointer capture release.")

	var interaction_menu := InteractionMenuScript.new()
	interaction_menu._ready()
	var npc_target: Node = ctx.make_interaction_target(
		InteractionActionResolverScript.DOMAIN_WORLD_OBJECT,
		WorldObjectDataScript.new(&"npc_ui", &"non_player_character", Vector3.ZERO)
	)
	if root_event_bus != null and interaction_menu._get_event_bus() != null and interaction_controller._get_event_bus() != null:
		root_event_bus.emit_signal(&"interaction_menu_requested", npc_target, Vector2.ZERO)
		if not interaction_menu.visible:
			npc_target.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not open from a menu request.")
		if not interaction_controller.is_interaction_pointer_captured():
			npc_target.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionController did not capture pointer when the menu opened.")
		root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
		if interaction_menu.visible:
			npc_target.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not close from a cancel request.")
	else:
		interaction_menu._on_interaction_menu_requested(npc_target, Vector2.ZERO)
		if not interaction_menu.visible:
			npc_target.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not open from a direct menu request.")
		interaction_menu._on_interaction_ui_cancel_requested()
		if interaction_menu.visible:
			npc_target.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not close from a direct cancel request.")

	npc_target.free()
	interaction_menu.free()
	var interaction_log_panel := InteractionLogPanelScript.new()
	interaction_log_panel.free()
	interaction_controller.free()
	return true
