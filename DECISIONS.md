# COBALT Decisions

Last updated: 2026-05-25

Purpose: preserve durable project decisions and known follow-up work across long Codex sessions. Treat `ARCHITECTURE.md` as the project law; this file records current accepted architecture choices and regression guards. Treat `COBALT_DSL.md` as the compact planning/context DSL for backlog funneling, node-role portability, and pre-coding decomposition.

## Current State

COBALT is a Godot 4.4 3D isometric RPG prototype using free-form 3D navigation. The old Blightroot hex/grid movement layer has been removed from active code.

Runtime source of truth:

- `WorldObjectData.position: Vector3` is the canonical location for actors and world objects.
- `MoveTargetData.position: Vector3` carries exact clicked movement destinations.
- `res://scenes/main.tscn` is the playable blockout scene.
- `res://data/maps/main_blockout_map.tres` is the current authored sample map.
- `EventBus` is the only autoload and is configured in `res://project.godot`.

## Boundary Rules

- Prefer typed COBALT APIs for owned systems: `class_name` resources, stateless processors, and scene adapters. Use duck typing and node groups at composition/plugin/scene edges where a hard type would over-couple nodes.
- Use `EventBus` for domain-level gameplay events. Keep UI button flow, hover visuals, editor panel/tool wiring, and parent-child adapter coordination local through typed references, NodePaths, or local signal connections.
- Stateless processors may operate on explicit mutable state containers for workflows that need state, such as runtime editors, undo/redo history, staged generation, or active selections. The container owns the state; processors own the rules; controllers coordinate commits and redraws.

## Key Architectural Decisions

### Data and Positioning

- Actor and object placement is continuous `Vector3` data, not grid, hex, square-cell, or axial coordinates.
- `WorldObjectData` owns object identity, kind, primitive size, color, hoverability, and canonical `position`.
- `MoveTargetData` owns a single exact `position` for requested movement destinations. Interaction raycasts update this position from the real hit point; do not flatten or quantize it in interaction code.
- Authored map content lives in `MapData` resources, currently `res://data/maps/main_blockout_map.tres`, with arrays for grounds, static walls, and world objects.

### Runtime Scene Shape

- `res://scenes/main.tscn` contains `NavigationRegion3D`, `MapLoader`, `InteractionController`, `MovementController`, `InteractionUI`, `CameraRig`, and `SunLight`.
- `MapLoader` builds generated map content under the configured `NavigationRegion3D`.
- `MapBuilder` creates a stable generated subtree: `GeneratedMap/StaticGrounds`, `GeneratedMap/StaticWalls`, and `GeneratedMap/WorldObjects`.
- `BlockoutObjectView` composes primitive visuals, an `InteractionTarget`, hover highlighting, and a `NavigationAgent3D` from `WorldObjectData`.

### Walls and NavMesh Geometry

- Static walls are authored as `WallSegmentData` with `start_position` and `end_position` `Vector3` endpoints, height, thickness, and color.
- `WallVisualResolver` derives wall center, length, and rotation from the segment endpoints.
- `MapBuilder` turns walls into primitive `BoxMesh` visuals plus `StaticBody3D` collision on collision layer `1`.
- Grounds are also generated as static collision bodies and include a child `GroundMoveTarget` `Area3D` for movement targeting.
- `MapLoader.rebake_navigation()` configures the `NavigationMesh` to parse static colliders and bakes the `NavigationRegion3D`.
- Walls block movement because the native navmesh bakes around static collision. Do not reintroduce logical wall cells or grid blocking flags.
- BSP debug buildings must include at least one exterior exit carved into the perimeter wall so interior rooms can connect to buffered exterior ground.

### Generator Pipeline

- Procedural world layers are `MapGenerator` resources. A generator receives the current `MapData` and returns the next `MapData`.
- `MapPipelineCompiler` is the stateless pipeline runner. It copies the base map, runs enabled generators in order, then applies `ManualOverrideLayer`.
- `MapBuilder` remains the scene-instantiation boundary. It builds `GeneratedMap/StaticGrounds`, `GeneratedMap/StaticWalls`, and `GeneratedMap/WorldObjects` from the final compiled `MapData`.
- `MapLoader` may use either direct authored `map_data` or a generator pipeline. The compiled result is exposed as `compiled_map_data`/`get_compiled_map_data()` and is what gets built and baked.
- Manual generated-object curation is represented as a `ManualOverrideLayer` keyed by `WorldObjectData.object_id`. Regenerating procedural modules should apply this layer last so object moves are not lost.
- `BspBuildingGenerator` wraps BSP room/door partition generation for pipeline use. `LandscapeScatterGenerator` adds seeded tree and rock props with spacing rejection.

### BSP Debug Editing

- BSP debug mode is runtime-only. `BspDebugMapController` generates `_generated_bsp_data` from parameter inputs, swaps it into `MapLoader`, and restores the authored map when debug mode is disabled.
- Manual BSP edits mutate only the current generated BSP data. Changing seed/parameters or regenerating the debug map discards manual room and door edits.
- `BspRoomProcessor` remains the stateless rule surface for BSP edit geometry: room lookup, nearest side selection, 10cm editor snapping for doors/splits, generated-door protection, and shared split resizing.
- `LevelEditorController` is the generic scene coordinator for editor input. It uses ground-plane camera projection, syncs panel edit-mode ids, and dispatches continuous `Vector3` hits to the active `EditorTool`.
- BSP editor behavior is registered through `BspLevelEditorToolProvider`. `BspRoomSelectTool`, `BspDoorTool`, and `BspResizeTool` own Select/Door/Resize behavior; BSP structural rules must not live in `LevelEditorController`.
- `BspDebugPanel` owns the edit mode controls. Select mode chooses a room, Door mode toggles manual doors for the locked room context, and Resize mode drags shared BSP split walls in 10cm increments.
- Door and Resize modes enforce a modal active room context. Clicking outside the locked room context or pressing cancel clears the context before a different room can be selected.
- `BspResizeTool` publishes hovered resizable split/wall targets to `NavigationDebugOverlay`, which renders a visual-only hover primitive.
- Generated default doors and the generated exterior exit are protected from Door-mode removal. Manual doors are marked with `BspDoor.is_manual` and can be removed by clicking them again.
- Resizing moves a shared BSP split, not an isolated room rectangle. Resize attempts that would violate `min_room_size_m` are rejected.
- After accepted edits, BSP editor tools commit through `BspDebugMapController`, which recompiles to `MapData`, reloads the generated map, rebakes navigation, and refreshes `NavigationDebugOverlay`.

### Editor Snapping

- Editor placement previews use `EditorSnappingResolver.snap_vector3()` for a 10cm default subgrid. This is editor behavior only; authored/runtime data remains freeform `Vector3`.
- Context-sensitive snapping, such as nearest wall-segment projection or slope/elevation adjustment, belongs in `EditorSnappingResolver.snap_with_context()` or related stateless helpers.
- `EditorTool` implementations opt into snap-grid visualization with `uses_snapping_grid()`, `get_snapping_step()`, and `get_snapping_context()`. `LevelEditorController` may render the visual preview, but it still dispatches raw continuous hit positions to tools.
- `NavigationDebugOverlay` may draw the subtle editor snap point cloud around the snapped cursor for active placement tools. It must remain visual-only and must not become a placement rule surface.
- BSP resize hover highlights are also visual-only. They preview which split/wall target the active tool will use, but the rule decision remains in `BspRoomProcessor` and the active editor tool.

### Movement Validation

- `MoveTargetResolver` is the stateless movement rule resolver.
- Movement sources must be enabled world-object targets backed by `WorldObjectData` with `object_kind == &"player_character"`.
- Movement destinations must be enabled move-target nodes backed by `MoveTargetData`.
- Navigation map resolution prefers the actor's `NavigationAgent3D` map, then falls back to scene/world maps.
- Validation rejects missing maps, unbaked maps, starts or targets outside snap tolerance, empty paths, and paths whose endpoint does not reach the snapped target.
- Native path validation uses `NavigationServer3D.map_get_path()`. Do not add custom A*, hex pathing, or cell-based movement checks.

### Movement Execution

- `MovementController` listens for `EventBus.move_requested`, validates the request again, and drives active movement through the actor's `NavigationAgent3D`.
- `MovementController` may store transient busy movement records keyed by actor instance id. This is runtime coordination state, not tactical rule state.
- Movement is rejected for invalid requests, busy actors, same-position destinations, missing agents, and missing native paths.
- During movement, the actor node and `WorldObjectData.position` stay synchronized.
- Arrival snaps both actor position and `WorldObjectData.position` to the requested `MoveTargetData.position` to avoid drift.
- Movement outcomes are emitted through `EventBus.movement_started`, `EventBus.movement_completed`, and `EventBus.movement_failed`.

### Interaction

- Interaction raycasts hit `Area3D` `InteractionTarget` nodes on collision layer `1`.
- World-object targets expose context actions through `InteractionActionResolver`.
- Only player-character world objects expose `Move`; other world objects expose `Examine` only.
- Ground movement targets are intentionally non-highlightable so the entire ground does not create a giant hover shell.
- Interaction targeting emits `move_requested` only after `MoveTargetResolver.can_move()` accepts the selected ground target.
- The interaction layer remains decoupled from navigation except for handing a `MoveTargetData` destination to the movement flow.

### Verification

Expected validation commands:

```bash
./scripts/run-tests.sh
./scripts/check.sh
```

Both commands should run the same headless smoke/integration coverage.

## Known Deferred Behavior

These are intentional gaps, not regressions from the refactor:

- No action points, movement cost, movement range, terrain cost, or turn budget.
- No actor occupancy or collision-aware reservation for start/end positions.
- No combat, dialogue, quests, inventory, party management, saves, or AI behavior.
- No complex models or animations; primitive blockout visuals remain the standard.
- No `CharacterBody3D` movement, avoidance, acceleration, rotation, footstep animation, or path preview.
- Zones, camera culling, streaming, and multi-region map loading are intentionally out of scope.
- The ground `move_target` is non-highlightable by design to avoid a giant ground hover shell.
- `EventBus.movement_step_reached` still exists but is not currently emitted by the continuous nav movement flow.
- Failed movement reasons are emitted, but there is no player-facing invalid-destination feedback yet.
- Native navigation baking is local/simple; broader map streaming or multi-region navigation is not designed yet.

## Backlog Funnels

Use these buckets to decorate future backlog items so later context windows can move into pre-coding faster.

### BUG / Regression

Current or likely broken behavior that should be fixed before adding new surface area:

- Movement failure reasons are emitted but not visible to the player.
- Invalid destination targeting has debug markers but no player-facing feedback contract yet.
- `EventBus.movement_step_reached` exists but is unused by the continuous movement flow.

### ARCH-DEBT / Architecture Misstep

Design drift that can create compounding debt if left unbounded:

- Do not let BSP/debug editor rules migrate from `BspRoomProcessor` into `LevelEditorController` or UI panels.
- Keep editor snap overlays visual-only; committed geometry must keep using stateless snapping/rule helpers.
- Runtime BSP edits are intentionally volatile. Before treating the BSP editor as production authoring, define persistence through resources or a manual override layer instead of controller state.
- `NavigationDebugOverlay` is accumulating path, BSP, route, snap, and editor-hover rendering responsibilities; split only when responsibilities start blocking changes or tests.

### FOUNDATION / Implementation Infrastructure

Infrastructure that improves feature velocity or reproducibility without directly changing player-facing behavior:

- Add a fixture-driven headless scenario runner before broadening movement, editor, or combat scenario coverage.
- Define a mutable editor state-container pattern before implementing undo/redo or persistent BSP editing.
- Tighten typed boundaries for owned COBALT systems while keeping duck-typed fallbacks at scene/composition edges.
- Keep deterministic file/resource fixtures as the default test corpus before considering a portable database for generated cases or telemetry.

### REGRESSION-GUARD / Refactor

Tests or refactors that protect existing contracts:

- Keep coverage that deleted grid/pathfinder/animator code stays deleted.
- Keep coverage for 10cm editor snapping matching committed BSP door and split geometry.
- Add focused coverage when invalid movement feedback becomes player-facing.
- Add a small node-role glossary before changing main scene node types or replacing major scene adapters.

### FEATURE / Gameplay Or Authoring

Player-facing or authoring work that is not yet implemented:

- Visible move-target preview, invalid destination marker, and movement failure messaging.
- Occupancy/reservation resolver so actors cannot stop on occupied destinations.
- Movement range/action-point rules before combat movement costs.
- Combat, dialogue, quests, inventory, party management, saves, AI behavior, and content authoring workflows.

### ORG / Preferred Organization

Lower-risk organization that improves portability and future context quality:

- Keep `COBALT_DSL.md` updated with canonical node roles, backlog tags, and subsystem funnels.
- Introduce stable node-role names before new systems depend on concrete Godot node classes.
- Keep `PROJECT_STRUCTURE.md` in sync whenever scripts, scenes, tests, or resources move.
- Prefer one focused test suite per subsystem or feature funnel.

## Watch Items

- Keep all new movement rules in stateless processors or data resources. Do not reintroduce grid, hex, square-cell, or discrete-cell math.
- `MovementController` may keep transient busy-move records, but tactical rule state should not migrate into it.
- Move target confirmation depends on a valid native navigation map. Tests often inject a deterministic square nav map into the actor agent.
- If movement appears to fail in a scene, check whether the `NavigationRegion3D` has baked and whether the actor's `NavigationAgent3D` is on the expected map.
- If interaction raycasts miss after scene changes, check `Area3D.input_ray_pickable`, collision layer `1`, and `InteractionController.collision_mask`.
