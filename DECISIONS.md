# COBALT Decisions

Last updated: 2026-05-24

Purpose: preserve durable project decisions and known follow-up work across long Codex sessions. Treat `ARCHITECTURE.md` as the project law; this file records current accepted architecture choices and regression guards.

## Current State

COBALT is a Godot 4.4 3D isometric RPG prototype using free-form 3D navigation. The old Blightroot hex/grid movement layer has been removed from active code.

Runtime source of truth:

- `WorldObjectData.position: Vector3` is the canonical location for actors and world objects.
- `MoveTargetData.position: Vector3` carries exact clicked movement destinations.
- `res://scenes/main.tscn` is the playable blockout scene.
- `res://data/maps/main_blockout_map.tres` is the current authored sample map.
- `EventBus` is the only autoload and is configured in `res://project.godot`.

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

### BSP Debug Editing

- BSP debug mode is runtime-only. `BspDebugMapController` generates `_generated_bsp_data` from parameter inputs, swaps it into `MapLoader`, and restores the authored map when debug mode is disabled.
- Manual BSP edits mutate only the current generated BSP data. Changing seed/parameters or regenerating the debug map discards manual room and door edits.
- `BspRoomProcessor` remains the stateless rule surface for BSP edit geometry: room lookup, nearest side selection, 1m door snapping, generated-door protection, and shared split resizing.
- `LevelEditorController` is the generic scene coordinator for editor input. It uses ground-plane camera projection, syncs panel edit-mode ids, and dispatches continuous `Vector3` hits to the active `EditorTool`.
- BSP editor behavior is registered through `BspLevelEditorToolProvider`. `BspRoomSelectTool`, `BspDoorTool`, and `BspResizeTool` own Select/Door/Resize behavior; BSP structural rules must not live in `LevelEditorController`.
- `BspDebugPanel` owns the edit mode controls. Select mode chooses a room, Door mode toggles manual doors for the selected room, and Resize mode drags shared BSP split walls in 1m increments.
- Generated default doors and the generated exterior exit are protected from Door-mode removal. Manual doors are marked with `BspDoor.is_manual` and can be removed by clicking them again.
- Resizing moves a shared BSP split, not an isolated room rectangle. Resize attempts that would violate `min_room_size_m` are rejected.
- After accepted edits, BSP editor tools commit through `BspDebugMapController`, which recompiles to `MapData`, reloads the generated map, rebakes navigation, and refreshes `NavigationDebugOverlay`.

### Editor Snapping

- Editor placement previews use `EditorSnappingResolver.snap_vector3()` for a 10cm default subgrid. This is editor behavior only; authored/runtime data remains freeform `Vector3`.
- Context-sensitive snapping, such as nearest wall-segment projection or slope/elevation adjustment, belongs in `EditorSnappingResolver.snap_with_context()` or related stateless helpers.
- `EditorTool` implementations opt into snap-grid visualization with `uses_snapping_grid()`, `get_snapping_step()`, and `get_snapping_context()`. `LevelEditorController` may render the visual preview, but it still dispatches raw continuous hit positions to tools.
- `NavigationDebugOverlay` may draw the subtle editor snap point cloud around the snapped cursor for active placement tools. It must remain visual-only and must not become a placement rule surface.

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

## Watch Items

- Keep all new movement rules in stateless processors or data resources. Do not reintroduce grid, hex, square-cell, or discrete-cell math.
- `MovementController` may keep transient busy-move records, but tactical rule state should not migrate into it.
- Move target confirmation depends on a valid native navigation map. Tests often inject a deterministic square nav map into the actor agent.
- If movement appears to fail in a scene, check whether the `NavigationRegion3D` has baked and whether the actor's `NavigationAgent3D` is on the expected map.
- If interaction raycasts miss after scene changes, check `Area3D.input_ray_pickable`, collision layer `1`, and `InteractionController.collision_mask`.
