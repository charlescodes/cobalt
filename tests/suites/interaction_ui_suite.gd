extends RefCounted

const HoverHighlighterScript := preload("res://src/interaction/hover_highlighter.gd")
const InteractionActionResolverScript := preload("res://src/interaction/interaction_action_resolver.gd")
const InteractionControllerScript := preload("res://src/interaction/interaction_controller.gd")
const InteractionMenuScript := preload("res://src/ui/interaction_menu.gd")
const InteractionLogPanelScript := preload("res://src/ui/interaction_log_panel.gd")
const ObjectInspectorPanelScript := preload("res://src/ui/object_inspector_panel.gd")
const EventBusPanelScript := preload("res://src/ui/event_bus_panel.gd")
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
	ctx.root().add_child(interaction_menu)
	interaction_menu._ready()
	var object_inspector := ObjectInspectorPanelScript.new()
	ctx.root().add_child(object_inspector)
	object_inspector._ready()
	var event_bus_panel := EventBusPanelScript.new()
	ctx.root().add_child(event_bus_panel)
	event_bus_panel._ready()
	var npc_target: Node = ctx.make_interaction_target(
		InteractionActionResolverScript.DOMAIN_WORLD_OBJECT,
		WorldObjectDataScript.new(&"npc_ui", &"non_player_character", Vector3.ZERO)
	)
	ctx.root().add_child(npc_target)
	if not ctx.has_action(InteractionActionResolverScript.get_actions(npc_target), InteractionActionResolverScript.ACTION_INSPECT):
		npc_target.free()
		event_bus_panel.free()
		object_inspector.free()
		interaction_menu.free()
		interaction_controller.free()
		return ctx.fail("InteractionActionResolver did not expose Inspect for inspectable targets.")
	if root_event_bus != null and interaction_menu._get_event_bus() != null and interaction_controller._get_event_bus() != null:
		root_event_bus.emit_signal(&"interaction_menu_requested", npc_target, Vector2.ZERO)
		if not interaction_menu.visible:
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not open from a menu request.")
		if not interaction_controller.is_interaction_pointer_captured():
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionController did not capture pointer when the menu opened.")
		if event_bus_panel.get_event_count() <= 0 or not event_bus_panel.get_latest_line().contains("interaction_menu_requested"):
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("EventBusPanel did not log interaction_menu_requested.")
		root_event_bus.emit_signal(&"interaction_ui_cancel_requested")
		if interaction_menu.visible:
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not close from a cancel request.")
		root_event_bus.emit_signal(&"interaction_inspector_requested", npc_target, Vector2(32.0, 32.0))
		if not object_inspector.visible or object_inspector.get_inspected_target() != npc_target:
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("ObjectInspectorPanel did not open from an inspector request.")
		if object_inspector.get_rendered_value("object_id") != "npc_ui":
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("ObjectInspectorPanel did not render target Resource properties.")
	else:
		interaction_menu._on_interaction_menu_requested(npc_target, Vector2.ZERO)
		if not interaction_menu.visible:
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not open from a direct menu request.")
		interaction_menu._on_interaction_ui_cancel_requested()
		if interaction_menu.visible:
			npc_target.free()
			event_bus_panel.free()
			object_inspector.free()
			interaction_menu.free()
			interaction_controller.free()
			return ctx.fail("InteractionMenu did not close from a direct cancel request.")

	npc_target.free()
	event_bus_panel.free()
	object_inspector.free()
	interaction_menu.free()
	var interaction_log_panel := InteractionLogPanelScript.new()
	interaction_log_panel.free()
	interaction_controller.free()
	return true
