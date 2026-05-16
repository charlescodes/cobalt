# Blightroot Project Overview

Last reviewed: 2026-05-15

Blightroot is currently a Godot 4.4 3D isometric RPG prototype focused on core tactical interaction systems. The project has a small, data-driven foundation: grid cells, world objects, and walls are represented as `Resource` data, while reusable logic lives in focused scripts and stateless resolver classes.

The current build is best understood as a playable systems blockout, not a content-complete RPG. It can generate a hex grid, show primitive actors, highlight and inspect objects, select player movement, animate movement over walkable hexes, and apply sample wall segments that block movement.

## Current Runtime Snapshot

The main scene is `res://scenes/main.tscn`.

At startup, it creates:

- `HexGridManager`: builds a default 6 by 6 axial hex grid.
- `WallLayout`: applies two sample wall segments and marks their occupied hexes unwalkable.
- `PlayerCharacter`: a blue primitive box at cube coordinate `(0, 0, 0)`.
- `NPC`: a gray primitive box at cube coordinate `(1, 0, -1)`.
- `InteractionController`: handles mouse hover, context menu requests, and movement targeting.
- `MovementController`: listens for movement requests and drives path-based movement.
- `InteractionUI`: contains the context menu and examine output panel.
- `CameraRig`: provides an angled isometric-style camera with pan, orbit, and zoom controls.
- `SunLight`: simple directional lighting for the blockout scene.

Scale is already aligned with the project rules: 1 Godot unit equals 1 meter, and adjacent hex centers are spaced at 1 meter side-to-side.

## Architecture

### Event Bus

`EventBus` is configured as an autoload in `project.godot`:

- `res://src/core/event_bus.gd`

It defines the main gameplay signals for hover changes, interaction menus, UI cancellation, movement requests, movement progress, and examine output. Most gameplay systems communicate through these signals instead of direct node references.

### Data Resources

Current data resources:

- `HexData`: cube/axial hex coordinates, terrain id, and walkability.
- `WorldObjectData`: object id, object kind, cube coordinate, primitive size, color, and hoverability.
- `WallSegmentData`: wall start/end axial coordinates, span mode, height, thickness, and color.

These resources are used directly by scene nodes and processors. The main scene currently stores sample resources inline as sub-resources.

### Stateless Processors

Current stateless or near-stateless resolver classes:

- `InteractionActionResolver`: decides which actions a target exposes and builds examine output.
- `MoveTargetResolver`: validates move source and destination targets.
- `HexPathfinder`: A* pathfinding over walkable `HexData`.
- `WallCellResolver`: converts wall segments into blocked hex keys.
- `WallVisualResolver`: converts wall segment data into visual endpoints.

This matches the intended architecture well: decision logic is isolated from scene nodes and mostly operates on resources or duck-typed targets.

### Scene Components

Important node scripts:

- `HexGridManager`: owns generated hex data for the current scene and instantiates `HexView` children.
- `HexView`: renders a hex as a low cylinder and creates its interaction target.
- `BlockoutObjectView`: renders a world object as a box, creates its interaction target, and composes a movement animator.
- `InteractionTarget`: reusable `Area3D` wrapper for hover/click targeting.
- `HoverHighlighter`: creates transparent shell meshes around hovered targets.
- `InteractionController`: raycasts from the camera and coordinates hover, context menus, and move targeting.
- `MovementController`: receives `move_requested`, finds paths, and tracks busy actors.
- `GridMovementAnimator`: moves an actor along a hex path and updates its `WorldObjectData`.
- `WallLayoutView`: applies wall resources to the grid and creates primitive wall visuals.
- `InteractionMenu`: shows available actions near the cursor.
- `InteractionLogPanel`: displays the latest examine output and toggles with `toggle_interaction_log`.
- `CameraRig`: handles mouse-driven camera control.

## Current Player Flow

1. Move the camera with mouse controls.
2. Hover hexes or world objects to get a visual shell highlight.
3. Left-click a world object to open its context menu.
4. Choose `Examine` to send object details to the interaction log.
5. Choose `Move` on the player character to enter move targeting.
6. Left-click a walkable hex to request movement.
7. `MovementController` finds a path and asks the actor to animate along it.
8. `GridMovementAnimator` updates both actor position and the actor's `WorldObjectData` coordinate.

Only the player character exposes `Move`. NPCs expose `Examine` but are not valid movement sources.

## Movement and Walls

Movement currently depends on `HexData.is_walkable`.

The pathfinder:

- Uses cube-coordinate neighbor directions.
- Uses cube distance as the A* heuristic.
- Rejects missing or non-walkable start and destination cells.
- Does not yet account for actor occupancy, movement cost, terrain cost, faction rules, or action points.

Walls are currently represented as `WallSegmentData` resources. `WallLayoutView` converts each wall segment into blocked hex keys, marks matching `HexData` as unwalkable, refreshes the affected hex visuals, and builds simple `BoxMesh` wall visuals. Wall visuals are display-only right now; movement blocking is handled through grid data.

## Repository Layout

```text
AGENTS.md                  Project-specific Codex and architecture rules
project.godot              Godot project config and autoloads
scenes/main.tscn           Current playable blockout scene
scripts/                   Local Godot launch/test helpers
tests/test_runner.gd       Headless smoke/integration test runner
src/core/                  Event bus
src/grid/                  Hex data, grid manager, and hex visuals
src/objects/               World object data and primitive object view
src/interaction/           Hover, targeting, and action resolution
src/movement/              Pathfinding, movement validation, and animation
src/ui/                    Context menu and examine log panel
src/camera/                Isometric camera rig
src/walls/                 Wall data, blocked-cell resolution, and visuals
```

## Validation Status

The dedicated test command currently passes:

```bash
./scripts/run-tests.sh
```

Observed result:

```text
Smoke Test Passed: Compilation successful
```

The broader check command currently fails before reaching the tests:

```bash
./scripts/check.sh
```

Reason:

```text
scripts/generate-src-map.py is missing
```

That script is referenced by `scripts/check.sh`, but it is not present in the current repository snapshot.

## Git Working Tree Notes

Before this overview document was added, the working tree already had:

- Modified `scenes/main.tscn`
- Modified `tests/test_runner.gd`
- Untracked `src/walls/`

Those changes appear to be the current wall-system work and are reflected in this overview.

## Known Gaps

- No combat, inventory, dialogue, quests, saves, party management, or AI behavior yet.
- No external map/encounter data files yet; the main scene uses inline sample resources.
- No complex models or animations yet, by design.
- Movement only checks walkability, not occupancy, terrain cost, turn budget, or tactical rules.
- Wall visuals do not have their own collision or interaction targets.
- `scripts/check.sh` needs either `scripts/generate-src-map.py` restored or the stale check removed.
- Tests are a custom headless smoke/integration runner rather than a full unit test framework.

## Sensible Next Steps

1. Fix `scripts/check.sh` so the one-command validation path works again.
2. Move sample grid/object/wall setup toward reusable `.tres` resources or map definitions.
3. Add an occupancy resolver so actors cannot path through or stop on occupied cells.
4. Add visible feedback for move targeting, invalid destinations, and failed movement reasons.
5. Extend movement rules with costs, range limits, or action points before adding combat.
6. Keep new gameplay rules in stateless processors and keep scene nodes focused on presentation and coordination.
