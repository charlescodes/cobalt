# COBALT Project Overview

Last reviewed: 2026-05-24

COBALT is a Godot 4.4 3D isometric RPG prototype focused on core tactical interaction and free-form navigation systems. It was migrated from the earlier Blightroot hex-grid prototype, but active gameplay code now uses continuous `Vector3` positions and Godot native navigation.

The current build is a playable systems blockout, not a content-complete RPG. It shows primitive actors, supports hover/context-menu/examine interactions, lets the player select a movement destination on the ground, validates that destination through `NavigationServer3D`, and steers the actor with a `NavigationAgent3D`.

## Current Runtime Snapshot

The main scene is `res://scenes/main.tscn`.

At startup, it contains:

- `NavigationRegion3D`: owns the native navigation mesh for the blockout space.
- `MapLoader`: loads `res://data/maps/main_blockout_map.tres`, builds `GeneratedMap`, and rebakes navigation.
- `GeneratedMap/StaticGrounds`: visual grounds, static collision, and non-highlighted ground move targets.
- `GeneratedMap/StaticWalls`: primitive static wall visuals and `StaticBody3D` collision from `WallSegmentData`.
- `GeneratedMap/WorldObjects`: primitive actors and interactables instantiated from `WorldObjectData`.
- `InteractionController`: handles camera raycasts, hover state, context menu requests, examine actions, and movement targeting.
- `MovementController`: listens for movement requests and drives active nav-agent movement.
- `InteractionUI`: contains the context menu and examine output panel.
- `BspDebugMapController`: starts the scene in generated BSP debug-map mode and can restore the authored map.
- `LevelEditorController`: generic runtime editor input coordinator for ground-plane mouse projection and active tool dispatch.
- `BspLevelEditorToolProvider`: registers BSP Select/Door/Resize editor tools for the current debug editor UI.
- `NavigationDebugOverlay`: draws movement debug paths plus BSP room/wall/socket/exit-route overlays while debug mode is visible.
- `CameraRig`: provides an angled isometric-style camera with pan, orbit, and zoom controls.
- `SunLight`: simple directional lighting for the blockout scene.

Scale is aligned with the project rules: 1 Godot unit equals 1 meter.

## Architecture

### Event Bus

`EventBus` is configured as an autoload in `project.godot`:

- `res://src/core/event_bus.gd`

It defines the main gameplay signals for hover changes, interaction menus, UI cancellation, movement requests, movement lifecycle events, and examine output. Scene systems communicate through these signals instead of direct cross-node references.

### Data Resources

Current data resources:

- `WorldObjectData`: object id, object kind, `Vector3` position, primitive size, color, and hoverability.
- `MoveTargetData`: exact `Vector3` movement destination, usually written from a ground raycast hit.
- `WallSegmentData`: start/end `Vector3` endpoints, wall height, thickness, and color.
- `GroundData`: static ground id, center position, dimensions, and color.
- `MapData`: map id plus ground, static wall, and world-object resource arrays.

The main blockout content is authored as `res://data/maps/main_blockout_map.tres`.

### Stateless Processors

Current stateless resolver classes:

- `InteractionActionResolver`: decides which actions a target exposes and builds examine output.
- `MoveTargetResolver`: validates move sources/destinations and asks `NavigationServer3D.map_get_path()` for native paths.
- `WallVisualResolver`: converts wall segment resources into visual endpoints, center, length, and rotation.
- `MapBuilder`: builds a generated scene subtree from `MapData` without storing game state.
- `BspRoomProcessor`: generates BSP debug buildings, compiles walls/grounds/actors, and owns stateless edit helpers for room picking, manual doors, and split resizing.

Keep gameplay rules in this style: resources and nodes provide inputs, processors return answers, and major outcomes move through `EventBus`.

### Scene Components

Important node scripts:

- `BlockoutObjectView`: renders a world object as a primitive box, creates its `InteractionTarget`, creates hover highlighting, and composes a `NavigationAgent3D`.
- `MapLoader`: scene adapter that calls `MapBuilder`, then rebakes the configured `NavigationRegion3D`.
- `InteractionTarget`: reusable `Area3D` wrapper for hover/click targeting.
- `HoverHighlighter`: creates transparent shell meshes around hovered targets.
- `InteractionController`: raycasts from the camera and coordinates hover, context menus, examine actions, and move targeting.
- `MovementController`: receives `move_requested`, validates the request, tracks transient busy actors, drives smooth movement, and synchronizes `WorldObjectData.position`.
- `WallLayoutView`: older reusable wall-only layout view retained for focused wall tests/tools.
- `InteractionMenu`: shows available actions near the cursor.
- `InteractionLogPanel`: displays the latest examine output and toggles with `toggle_interaction_log`.
- `CameraRig`: handles mouse-driven camera control.
- `BspDebugMapController`: swaps the generated BSP debug map into `MapLoader`, restores the authored map, and commits runtime BSP edits.
- `LevelEditorController`: handles editor activation, ground-plane camera projection, panel mode sync, and dispatch to the active `EditorTool`.
- `BspLevelEditorToolProvider`: wires BSP editor context plus `BspRoomSelectTool`, `BspDoorTool`, and `BspResizeTool` into the generic editor controller.
- `BspDebugPanel`: exposes BSP generation parameters, overlay toggles, and edit mode controls.
- `NavigationDebugOverlay`: renders movement markers plus BSP room bounds, wall highlights, sockets, selected-room fill, and exit-route debug geometry.

## Current Player Flow

1. Move the camera with mouse controls.
2. Hover a world object to apply a visual shell highlight.
3. Left-click a world object to open its context menu.
4. Choose `Examine` to send object details to the interaction log.
5. Choose `Move` on the player character to enter movement targeting.
6. Left-click a reachable point on the ground.
7. `InteractionController` writes the exact raycast hit to `MoveTargetData.position` and emits `move_requested`.
8. `MovementController` validates a native nav path and steers the actor through its `NavigationAgent3D`.
9. During movement, the actor node and its `WorldObjectData.position` stay synchronized.

Only the player character exposes `Move`. NPCs expose `Examine` but are not valid movement sources.

## Movement and Walls

Movement is free-form on a 3D plane. There is no active grid, hex math, discrete cell movement, or custom A* pathfinder.

Movement validation:

- requires a player-character `WorldObjectData` source;
- requires a `MoveTargetData` destination;
- resolves a native navigation map, preferring the actor's `NavigationAgent3D`;
- snaps start/target positions to the native navigation map within a small tolerance;
- calls `NavigationServer3D.map_get_path()`;
- rejects missing maps, unbaked maps, off-nav destinations, and incomplete paths.

Movement execution:

- `BlockoutObjectView` composes a `NavigationAgent3D`;
- `MovementController` sets the agent `target_position`;
- `_physics_process()` steers toward `agent.get_next_path_position()`;
- arrival snaps actor and data positions to the requested destination to avoid drift;
- movement emits `movement_started`, `movement_completed`, or `movement_failed`.

Maps are represented as `MapData` resources. `MapBuilder` creates ground and wall primitives with static collision under the `NavigationRegion3D`; `MapLoader` then configures the `NavigationMesh` to parse static colliders and calls `bake_navigation_mesh(false)`. The navmesh bakes around those static colliders, so walls block movement through native navigation geometry rather than logical cell flags.

## Repository Layout

```text
ARCHITECTURE.md            Project-specific Codex and architecture rules
DECISIONS.md               Current architecture decisions, deferred work, and handoff notes
project.godot              Godot project config and autoloads
scenes/main.tscn           Current playable blockout scene
data/maps/                 Authored map resources
scripts/                   Local Godot launch/test helpers
tests/test_runner.gd       Headless smoke/integration test runner
src/core/                  Event bus
src/objects/               World object data and primitive object view
src/interaction/           Hover, targeting, and action resolution
src/movement/              Move target data, nav validation, and movement controller
src/ui/                    Context menu and examine log panel
src/camera/                Isometric camera rig
src/maps/                  Map resources, builder, and scene loader
src/walls/                 Wall data, collision generation, and visual helpers
src/debug/                 Runtime BSP debug map generation and editing
```

Removed during the navigation migration:

- `src/grid/`
- `src/movement/hex_pathfinder.gd`
- `src/movement/grid_movement_animator.gd`
- `src/walls/wall_cell_resolver.gd`

## Validation Status

The expected validation commands are:

```bash
./scripts/run-tests.sh
./scripts/check.sh
```

Both currently run the headless smoke/integration test suite. A successful run prints:

```text
Smoke Test Passed: Compilation successful
```

Current test coverage includes:

- deleted grid/pathfinder/animator scripts stay deleted;
- data resources preserve `Vector3` positions;
- world objects create interaction targets, hover highlighters, and nav agents;
- player targets expose `Move`; NPC targets do not;
- native navigation accepts reachable destinations and rejects off-nav destinations;
- movement starts, rejects busy actors, updates actor data, completes, and reports failures;
- wall layout creates primitive visuals and static collision;
- map builder creates typed map content, ground targets, static collision, and object views;
- BSP debug generation creates connected buildings, exterior exits, editable room-side metadata, manual doors, and split-resize helpers;
- BSP debug editor selects rooms, adds/removes manual doors, protects generated doors, resizes shared splits, and redraws overlays;
- main scene loads with nav region, generated map content, controllers, UI, camera, and light;
- interaction raycasts support hover, menu, examine, target filtering, exact ground-hit destination capture, and `move_requested` payloads.

## Known Gaps

- No combat, inventory, dialogue, quests, saves, party management, or AI behavior yet.
- No zones, camera culling, streaming, or multi-region map loading yet.
- No complex models or animations yet, by design.
- No action points, movement cost, terrain cost, range limits, or turn budget.
- No actor occupancy or collision-aware reservation for occupied destinations.
- No path preview, invalid-destination marker, or player-facing movement failure message.
- No `CharacterBody3D` movement, avoidance, acceleration, actor rotation, or animation work.
- `EventBus.movement_step_reached` still exists but is not emitted by the continuous nav movement flow.
- Tests are a custom headless smoke/integration runner rather than a full unit test framework.

## Sensible Next Steps

1. Add visible feedback for move targeting, invalid destinations, and failed movement reasons.
2. Add an occupancy/reservation resolver so actors cannot stop on occupied destinations.
3. Extend movement rules with costs, range limits, or action points before adding combat.
4. Add a lightweight authoring workflow for additional `.tres` map resources.
5. Decide whether `movement_step_reached` should be removed or repurposed for continuous movement milestones.
6. Keep new gameplay rules in stateless processors and keep scene nodes focused on presentation and coordination.
