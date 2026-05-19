# COBALT Notes

Last updated: 2026-05-19

Purpose: preserve project decisions and known follow-up work across long Codex sessions. Treat `AGENTS.md` as the architectural rule source; this file is the migration/handoff log.

## Current State

COBALT is a Godot 4.4 3D isometric RPG prototype using free-form 3D navigation. The old Blightroot hex/grid movement layer has been removed from active code.

Key runtime shape:

- `WorldObjectData.position: Vector3` is the canonical location for actors and world objects.
- `MoveTargetData.position: Vector3` carries exact clicked movement destinations.
- `scenes/main.tscn` contains a `NavigationRegion3D`, `MapLoader`, movement/interaction controllers, UI, camera, and light.
- `res://data/maps/main_blockout_map.tres` stores the sample floor, static walls, player, and NPC as `MapData`.
- `BlockoutObjectView` composes primitive visuals, an `InteractionTarget`, hover highlighting, and a `NavigationAgent3D`.
- `MoveTargetResolver` remains stateless and validates movement through `NavigationServer3D.map_get_path()`.
- `MovementController` listens for `EventBus.move_requested`, validates the request, drives the actor through its `NavigationAgent3D`, updates `WorldObjectData.position`, and emits movement lifecycle events.
- The interaction layer still uses camera raycasts against `Area3D` `InteractionTarget` nodes and is intentionally decoupled from navigation.

## Phase Record

Phase commits in `main`:

- `fd75613` - Phase 1, grid data layer excised.
- `14d77d8` - Phase 2, custom pathfinding swapped for native navmesh validation.
- `916d9fe` - Phase 3, continuous `NavigationAgent3D` steering added.
- `f486806` - Phase 4, interaction/UI survivors verified and test coverage expanded.
- `4fa80b5` - Godot editor normalization of `main.tscn`.
- `bdfe595` - project renamed to `Cobalt` in `project.godot`.

Phase 1 decisions:

- Deleted `src/grid/hex_data.gd`, `src/grid/hex_grid_manager.gd`, and `src/grid/hex_view.gd`.
- Replaced cube/axial object placement with `WorldObjectData.position`.
- Removed the `HexGridManager` scene dependency.
- Kept movement signals stable while payloads migrated away from hex data.

Phase 2 decisions:

- Deleted `src/movement/hex_pathfinder.gd` and `src/walls/wall_cell_resolver.gd`.
- Added `MoveTargetData` as the movement destination resource.
- Added a static floor and `NavigationRegion3D` to the main scene.
- Converted wall data to `start_position`/`end_position` `Vector3` endpoints.
- Made walls generate primitive `BoxMesh` visuals plus `StaticBody3D` collision so navmesh baking handles blocking naturally.
- Movement validation now rejects off-nav clicks using native nav path checks and a snap tolerance.

Phase 3 decisions:

- Deleted `src/movement/grid_movement_animator.gd`.
- Added `NavigationAgent3D` composition to `BlockoutObjectView`.
- `MovementController` now stores only active movement records, keyed by actor instance id. This is controller runtime state, not game-rule state.
- Movement starts only for player-character data and only when a valid native nav path exists.
- Arrival snaps actor position and `WorldObjectData.position` to the requested target to avoid drift.

Phase 4 decisions:

- Verified that hover, context menus, examine output, movement targeting, pointer capture, and UI cancellation survive the navigation refactor.
- Added raycast-oriented tests around `CameraRig`, `InteractionController`, world-object targets, and the floor move target.
- Preserved exact raycast hit positions in `MoveTargetData`; do not flatten `y` in interaction code.
- Updated `MoveTargetResolver.get_navigation_map()` to prefer the actor's `NavigationAgent3D` map before generic scene/world maps.
- Simplified `scripts/check.sh` to run the smoke/integration tests directly.

## Known Deferred Behavior

These are intentional gaps, not regressions from the refactor:

- No action points, movement cost, movement range, terrain cost, or turn budget.
- No actor occupancy or collision-aware reservation for start/end positions.
- No combat, dialogue, quests, inventory, party management, saves, or AI behavior.
- No complex models or animations; primitive blockout visuals remain the standard.
- No `CharacterBody3D` movement, avoidance, acceleration, rotation, footstep animation, or path preview.
- Zones, camera culling, streaming, and multi-region map loading are intentionally out of scope.
- The floor `move_target` is non-highlightable by design to avoid a giant floor hover shell.
- `EventBus.movement_step_reached` still exists but is not currently emitted by the continuous nav movement flow.
- Failed movement reasons are emitted, but there is no player-facing invalid-destination feedback yet.
- Native navigation baking is local/simple; broader map streaming or multi-region navigation is not designed yet.

## Watch Items

- Keep all new movement rules in stateless processors or data resources. Do not reintroduce grid, hex, square-cell, or discrete-cell math.
- `MovementController` may keep transient busy-move records, but tactical rule state should not migrate into it.
- Move target confirmation depends on a valid native navigation map. Tests often inject a deterministic square nav map into the actor agent.
- If movement appears to fail in a scene, check whether the `NavigationRegion3D` has baked and whether the actor's `NavigationAgent3D` is on the expected map.
- If interaction raycasts miss after scene changes, check `Area3D.input_ray_pickable`, collision layer `1`, and `InteractionController.collision_mask`.

## Verification

Current expected validation commands:

```bash
./scripts/run-tests.sh
./scripts/check.sh
```

Both commands should run the same headless smoke/integration coverage as of Phase 4.

The test harness is modular: `tests/test_runner.gd` is a small headless
orchestrator, `tests/support/test_context.gd` owns shared fixtures/helpers, and
subsystem suites live under `tests/suites/`.

Covered by tests:

- deleted grid/pathfinder/animator scripts stay deleted;
- `WorldObjectData` and `MoveTargetData` preserve `Vector3` positions;
- world objects create interaction targets, hover highlighters, and nav agents;
- player targets expose `Move`; NPC targets do not;
- native navigation accepts reachable destinations and rejects off-nav destinations;
- movement starts, rejects busy actors, updates actor data, completes, and reports failures;
- wall layout creates primitive visuals and static collision;
- map builder creates typed map content, floor targets, static collision, and object views;
- main scene loads with nav region, generated map content, controllers, UI, camera, and light;
- interaction raycasts still support hover, menu, examine, target filtering, exact floor-hit destination capture, and `move_requested` payloads.
