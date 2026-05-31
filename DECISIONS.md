# COBALT Decisions

Last updated: 2026-05-30

Purpose: living design ledger and agent handoff file. `ARCHITECTURE.md` is project law, `PROJECT_STRUCTURE.md` is the file index, `ROADMAP.md` is future planning, and `CHANGELOG.md` is the formal history.

## Current State Snapshot

COBALT is a Godot 4.4 3D isometric RPG prototype using free-form native navigation. The old Blightroot hex/grid movement layer has been removed from active code.

Runtime source of truth:

- `res://scenes/main.tscn` is the playable blockout scene.
- `res://data/maps/main_blockout_map.tres` is the current authored sample map.
- Runtime local-map editor V1 is available through an Escape dev menu in `main.tscn`.
- `EventBus` is the only autoload and is configured in `res://project.godot`.
- `WorldObjectData.position: Vector3` is the canonical location for current actor/object data.
- `MoveTargetData.position: Vector3` carries exact clicked movement destinations.

## Accepted Decisions

### World Organization

- `src/environment/` owns static map geometry resources and helpers: ground, continuous walls, door sockets, wall visualization, and future static obstacles or static blocking props.
- `src/maps/` owns map aggregation, map building, and map loading.
- `src/objects/` currently owns blockout object data and views. A later split into `actors/` and `props/` is expected when gameplay behavior requires it.
- Interactable behavior should be reusable as a capability, not treated as a directory category by itself.

### Runtime Scene Shape

- `main.tscn` contains `NavigationRegion3D`, `MapLoader`, `InteractionController`, `MovementController`, `InteractionUI`, `NavigationDebugOverlay`, `DebugOverlayController`, `CameraRig`, and lighting.
- `main.tscn` also contains runtime editor nodes: `InteractionUI/DevMenu`, `InteractionUI/EditorPanel`, `EditorSelectionController`, and `EditorModeController`.
- `MapLoader` builds generated map content under the configured `NavigationRegion3D`.
- `MapBuilder` creates a stable generated subtree: `GeneratedMap/StaticGrounds`, `GeneratedMap/StaticWalls`, `GeneratedMap/DoorSockets`, and `GeneratedMap/WorldObjects`.
- `MapBuilder` tags generated grounds, walls, door sockets, and world objects with editor metadata so editor raycasts can map scene nodes back to source resources.
- `BlockoutObjectView` composes primitive visuals, an `InteractionTarget`, hover highlighting, and a `NavigationAgent3D` from `WorldObjectData`.

### Environment and NavMesh Geometry

- Static walls are authored as `WallData` with one start/end floor-plane line, height, thickness, and color.
- `WallVisualResolver` derives a box size and local orientation from each wall line; authored walls do not store rotation.
- `MapBuilder` turns each wall into one `BoxMesh` visual plus `BoxShape3D` static collision on collision layer `1`.
- Door openings are authored as `DoorSocketData` markers after the editor splits wall lines around a gap. Door socket markers are non-blocking editor visuals and do not contribute static navigation collision.
- Grounds are generated as static collision bodies and include a child `GroundMoveTarget` `Area3D` for movement targeting.
- `MapLoader.rebake_navigation()` configures the `NavigationMesh` to parse static colliders and bakes the `NavigationRegion3D`.

### Movement

- `MoveTargetResolver` is the stateless movement rule resolver.
- Movement sources must be enabled world-object targets backed by `WorldObjectData` with `object_kind == &"player_character"`.
- Movement destinations must be enabled move-target nodes backed by `MoveTargetData`.
- Native path validation uses `NavigationServer3D.map_get_path()`.
- `MovementController` listens for `EventBus.move_requested`, validates again, and drives movement through the actor `NavigationAgent3D`.
- During movement, the actor node and `WorldObjectData.position` stay synchronized. Arrival snaps both to the requested `MoveTargetData.position`.

### Interaction and Debugging

- Interaction raycasts hit `InteractionTarget` `Area3D` nodes on collision layer `1`.
- World-object targets expose context actions through `InteractionActionResolver`.
- Only player-character world objects currently expose `Move`; other world objects expose `Examine`.
- Ground movement targets are intentionally non-highlightable to avoid a giant hover shell.
- `F12` toggles the debug log panel and navigation debug overlay.

## Planning Direction

### Runtime Editor Mode

- Runtime editor V1 is implemented under `src/editor/` as a development surface inside the playable project, not as a Godot `EditorPlugin`.
- Escape toggles the centered dev menu. The menu switches between `game` and `editor` modes and saves/loads named maps under `res://data/editor_maps/`.
- Entering editor mode loads an in-memory blank editor map the first time no editor map is active.
- Editor mode disables gameplay mouse targeting and context-menu input through `InteractionController` while `EditorSelectionController` owns editor tool raycasts.
- The editor panel is a draggable, collapsed-by-default tool dock. Right mouse drag moves the dock when the pointer is over the dock; right mouse elsewhere remains camera pan.
- The editor currently exposes `Select/Inspect`, `NPC Brush`, `PC Brush`, `Wall Brush`, and `Door Brush` tools. Active tool changes flow through `EventBus.editor_tool_changed`.
- `Select/Inspect` raycasts generated grounds, walls, door sockets, and world objects and renders a read-only inspector.
- `NPC Brush` places `WorldObjectData` entries with `object_kind == &"non_player_character"` on generated ground clicks, rebuilds/rebakes through `MapLoader.replace_map_data()`, and clears selection so repeated painting stays uninterrupted.
- `PC Brush` places `WorldObjectData` entries with `object_kind == &"player_character"` on generated ground clicks. Multiple player-character objects are valid and each can be used as a movement source.
- `Wall Brush` defaults to line mode when selected. Line mode uses two ground-plane clicks to append one `WallData`; rectangle mode uses two opposite corner clicks to append four enclosing `WallData` edges. Wall brush mode changes flow through `EventBus.editor_wall_brush_mode_changed`.
- `Door Brush` snaps a click to the nearest wall line, clamps the opening to leave 0.5m edge clearance, replaces the original wall with two shorter wall lines around a 1m gap, appends a `DoorSocketData`, and rebuilds/rebakes the map.
- The first editor surface should be an in-game development mode reached through an Escape dev menu.
- This is a runtime tool surface inside the playable project, not a Godot `EditorPlugin` yet.
- Game view should keep the current movement, context-menu, hover, and examine behavior.
- Editor view should own its own pointer capture, raycasts, tool palette, inspector, and save/load actions.
- Entering editor view should disable gameplay targeting and context-menu input instead of adding editor behavior to `InteractionController`.
- Editor tools should mutate resource data and ask `MapLoader` to rebuild and rebake, preserving the current `MapData` -> `MapBuilder` -> generated scene flow.
- Use "editor tool" for pluggable runtime tools. Reserve "plugin" for future Godot editor plugins or external extension points.

### Module and Generation Planning

- Reusable map pieces should be modeled as resource-backed modules and placement descriptors before building large procedural systems.
- A placement descriptor should carry local position, rotation, bounds or footprint, seed, selected module or generator preset, and tool-authored parameters.
- Generator presets should be deterministic and resource-backed. Candidate presets include BSP buildings, roads, utilities, tree clusters, and rock outcrops.
- World-map coordinate, cellular, quadrant, brush, or noise language applies to generation and authoring only. It must not become custom grid or hex movement.

## Deferred Behavior

These are intentional gaps, not regressions:

- No action points, movement cost, movement range, terrain cost, or turn budget.
- No actor occupancy or collision-aware reservation for start/end positions.
- No combat, dialogue, quests, inventory, party management, saves, or AI behavior.
- No dedicated `ActorData`, `PropData`, door, container, harvestable, or static obstacle resources yet.
- No complex models or animation pipeline.
- No `CharacterBody3D` movement, avoidance, acceleration, rotation, footstep animation, or path preview.
- No zones, camera culling, streaming, multi-region navigation, or large-map loading design.
- Failed movement reasons are emitted, but there is no player-facing invalid-destination feedback yet.
- No three-point ground creation yet; richer environment brush semantics are deferred until static authoring needs are clearer.

## Watch Items

- Keep all movement rules in stateless processors or data resources.
- Do not reintroduce grid, hex, square-cell, axial-coordinate, or discrete-cell math.
- `MovementController` may keep transient busy records, but tactical rule state should not migrate into it.
- Move target confirmation depends on a valid native navigation map.
- If movement fails in a scene, check navmesh baking, actor `NavigationAgent3D` map assignment, and snap tolerance.
- If interaction raycasts miss after scene changes, check `Area3D.input_ray_pickable`, collision layer `1`, and `InteractionController.collision_mask`.

## Agent Handoff Notes

Update this section when a work session ends with meaningful unfinished context.

Current focus:

- Roadmap planning now centers on an Escape-driven runtime editor mode, editor tools, module libraries, procedural world-map zones, generated local maps, factions, populations, agents, and one-year world history outcomes.
- Future roadmap scope now explicitly includes map components, procedural structures, sockets, city-block composition, world-map editor tooling, sparse region-scale generation, points of interest, and spawn placement. These are future features, not part of the first local-map editor implementation.

Known state:

- Static environment scripts live under `src/environment/`.
- `src/maps/` remains responsible for map data aggregation, generation, loading, and navmesh rebaking.
- Runtime editor scripts live under `src/editor/`.
- `MapLoader.replace_map_data()` is the public rebuild/rebake entrypoint for editor map swaps.
- Current object/actor data still uses `WorldObjectData`; splitting actors and props is deferred.

Next likely work:

- Build on the implemented runtime editor V1 with richer placement options, environment editing tools, and map-component authoring after the first brush workflows have had use.
- Define resource schemas for module libraries, placement descriptors, and generator presets.
- Keep the first editor pass scoped to local map mode switching, save/load, selection, highlighting, and read-only inspection before adding composition, sockets, or generation tools.
- Introduce richer interactable data once doors, containers, harvestables, or examine profiles need distinct behavior.
- Add static obstacle data under `src/environment/` when authored blockers are needed beyond continuous walls.

## Verification

Expected validation commands:

```bash
./scripts/run-tests.sh
./scripts/check.sh
```
