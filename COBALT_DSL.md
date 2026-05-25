# COBALT DSL

Purpose: compact project-context DSL for future Codex sessions and planning passes. This file does not replace `ARCHITECTURE.md`; it narrows recurring decisions into machine-scannable rules, feature funnels, and backlog tags so future work can start closer to implementation.

Use this file when a task needs architecture validation, backlog grouping, node portability decisions, or pre-coding decomposition.

```yaml
!COBALT_CORE_DSL
meta:
  engine: godot_4.4
  genre: 3d_isometric_rpg
  paradigm: decoupled_data_driven_ecs_lite
  scale: 1_unit_equals_1_meter
  active_scene: res://scenes/main.tscn
  authored_map: res://data/maps/main_blockout_map.tres

absolute_rules:
  no_grids:
    rule: Continuous Vector3 only. The old hex/grid movement layer is permanently removed.
    reject: [hex_coords, square_cells, tile_cost_maps, custom_astar]
  stateless_processors:
    rule: Durable rules live in stateless resolvers/processors that take Resource, Vector3, or Node inputs.
    reject: persistent tactical state inside scene managers
    state_container_escape_hatch: Mutable workflows may use explicit Resource/context containers for editor session state, undo history, staged generation, or active selections.
  event_bus_comm:
    rule: Domain-level gameplay events go through EventBus.
    examples: [move_requested, movement_started, movement_completed, movement_failed, examined_output, future_combat_started, future_turn_ended]
    allow: local signals, typed references, and NodePath wiring for UI controls, hover visuals, parent-child adapters, editor tools, and debug panels
  native_nav:
    rule: Use Godot NavigationServer3D and NavigationAgent3D for movement/path validation.
    reject: parallel navigation graph systems
  composition_over_inheritance:
    rule: Prefer node composition, typed COBALT Resource/processor/adapter APIs, groups, and shallow scripts.
    duck_typing_scope: Use has_method, has_signal, or group checks at scene/plugin/composition boundaries where static typing would over-couple nodes.
    reject: deep inheritance trees
  strict_typing:
    rule: Modern typed GDScript for Godot 4.4.

core_state_models:
  WorldObjectData:
    canonical_fields: [object_id, object_kind, position, primitive_size, primitive_color, is_hoverable]
    position: Vector3_canonical
  MoveTargetData:
    position: Vector3_exact_raycast_hit
  WallSegmentData:
    endpoints: [start_position, end_position]
    unit: meters
  MapData:
    arrays: [grounds, static_walls, world_objects]
  BspModuleData:
    scope: runtime_debug_generation
    generated_state: [root_node, rooms, partitions, doors]

architecture_pipeline:
  map_pipeline:
    - MapData resources hold authored/generated content.
    - MapPipelineCompiler runs enabled MapGenerator resources.
    - ManualOverrideLayer applies curated object overrides last.
    - MapBuilder is the scene-instantiation boundary.
  navigation_layer:
    - Walls and grounds generate StaticBody3D collision on layer 1.
    - MapLoader rebakes NavigationRegion3D from static collision.
    - Walls block movement through native navmesh geometry.
  interaction_layer:
    decoupled_from_navigation: true
    input: Camera raycasts hit Area3D InteractionTarget nodes on layer 1.
    outputs: [hover_target_changed, interaction_menu_requested, move_requested, examined_output]
  movement_resolution:
    validator: MoveTargetResolver
    executor: MovementController
    path_source: NavigationServer3D.map_get_path
  state_container_pattern:
    purpose: Allow mutable workflows without moving rules into controllers.
    allowed_containers: [Resource, narrowly_scoped_context_object]
    examples: [editor_active_selection, undo_redo_history, staged_bsp_geometry, generated_map_override_state]
    processor_contract: container_plus_operation_in_result_or_mutation_out
  runtime_editor:
    coordinator: LevelEditorController
    rule_surface: BspRoomProcessor
    tools: [BspRoomSelectTool, BspDoorTool, BspResizeTool]
    snap_step_m: 0.1
    modal_selection: room_context_locked_until_outside_click_or_cancel

node_type_portability:
  goal: Keep COBALT portable across Godot scene-node changes by treating concrete node classes as adapters, not domain concepts.
  canonical_roles:
    navigation_region: NavigationRegion3D owner for baked map geometry
    map_loader: scene adapter from MapData to GeneratedMap nodes
    interaction_controller: camera-raycast adapter for interaction targets
    movement_controller: EventBus movement executor using NavigationAgent3D
    debug_map_controller: runtime BSP debug map adapter
    level_editor_controller: editor input projection and tool lifecycle adapter
    navigation_debug_overlay: visual-only debug rendering adapter
  processor_boundary_rule: Stateless processors may accept Node inputs for duck-typed queries, but should prefer Resources and Vector3 where possible.
  portability_backlog:
    - Define stable node-role names in docs before introducing new systems.
    - Avoid storing gameplay rules in specific scene-node classes.
    - If a node type changes, keep Resource schemas and processor APIs stable first.

backlog_taxonomy:
  bug_or_regression:
    description: Incorrect current behavior or behavior that used to work and broke.
    priority: highest
    examples: [movement request rejected unexpectedly, generated wall fails to carve door gap, editor snap not matching committed geometry]
  architecture_misstep:
    description: Design drift that creates future technical debt.
    priority: highest_when_it_blocks_features
    examples: [rules migrating into controllers, grid math reintroduced, everything routed through EventBus]
  foundation:
    description: Implementation infrastructure that improves feature velocity without directly changing player-facing behavior.
    priority: high_when_it_enables_multiple_feature_funnels
    examples: [fixture driven headless scenario runner, editor state container pattern, typed boundary cleanup, deterministic test fixtures]
  regression_refactor:
    description: Refactor or cleanup needed to keep existing contracts testable.
    priority: high
    examples: [split large overlay responsibilities, tighten editor tool APIs, improve generated-data persistence boundaries]
  feature_funnel:
    description: Player-facing or authoring capability not yet implemented.
    priority: ordered_by_current_gameplay_goal
    examples: [invalid movement feedback, occupancy reservations, action points, combat, dialogue, inventory]
  preferred_organization:
    description: Documentation, naming, layout, portability, and context improvements.
    priority: lower_unless_enabling_pre_coding
    examples: [node-role glossary, DSL expansion, subsystem templates, backlog decoration]

directory_map:
  core: res://src/core/
  data: res://data/
  maps: res://src/maps/
  objects: res://src/objects/
  movement: res://src/movement/
  interaction: res://src/interaction/
  ui: res://src/ui/
  editor: res://src/editor/
  debug: res://src/debug/
  tests: res://tests/
```

## Backlog Funnel Defaults

When adding or triaging work, decorate items with one of these prefixes:

- `BUG`: Broken user-visible behavior or broken architecture contract.
- `ARCH-DEBT`: Architecture drift likely to create compounding maintenance cost.
- `FOUNDATION`: Implementation infrastructure that increases feature velocity or reproducibility.
- `REGRESSION-GUARD`: Test, invariant, or refactor that protects an existing behavior.
- `FEATURE`: New gameplay/editor capability.
- `ORG`: Documentation, naming, project structure, or portability cleanup.

Prefer writing backlog items as:

```text
TAG: subsystem - outcome-oriented short title
```

Example:

```text
ARCH-DEBT: editor - formalize portable node-role names for editor/debug adapters
FOUNDATION: tests - add fixture-driven headless scenario runner
FOUNDATION: editor - define mutable editor state container pattern
REGRESSION-GUARD: movement - cover invalid destination feedback when UI marker is added
FEATURE: movement - add occupancy/reservation resolver before combat movement costs
```
