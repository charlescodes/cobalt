# COBALT Architecture

Last updated: 2026-06-21

Purpose: the authoritative description of COBALT's current architecture, subsystem ownership, accepted implementation decisions, and durable constraints. Future intent belongs in `ROADMAP.md`; completed outcomes belong in `CHANGELOG.md`.

## Project Snapshot

COBALT is a Godot 4.4 3D isometric RPG prototype using free-form movement on a continuous plane and Godot-native navigation. Scale is `1 Godot unit = 1 meter`. The removed Blightroot hex/grid movement layer is not part of the active architecture.

Current runtime entrypoints:

- `res://project.godot` owns project configuration, input mappings, the main scene, and the `EventBus` autoload.
- `res://scenes/main.tscn` is the playable blockout scene and starts in local runtime editor mode.
- `res://data/maps/main_blockout_map.tres` is the current authored sample local map.
- Local editor saves live under `res://data/editor_maps/`; world editor saves live under `res://data/world_maps/`.

`EventBus` is the only autoload. Cross-system coordination should use focused signals or resolvers instead of new broad global managers.

## Core Principles

- **Data-driven:** authored game state lives in custom `Resource` scripts. Do not hardcode durable gameplay values into scene nodes.
- **Composition over inheritance:** use Godot node composition, small focused scripts, duck typing, signals, and groups instead of deep inheritance trees.
- **Event-based coordination:** major cross-system events flow through `EventBus`. Avoid direct references between unrelated systems.
- **Capability-based interaction:** interaction is a reusable capability. Actors, props, doors, containers, harvestables, and environment pieces need not share one data type.
- **Deterministic generation:** the same seed and authored inputs should produce the same generated result whenever practical.

## Data and Logic Boundaries

- Resource scripts own authored identity, position, dimensions, colors, static geometry, generator inputs, and future content definitions.
- Stateless `RefCounted` processors and resolvers own durable gameplay and generation rules. They may inspect resources, nodes, and values but should not store active tactical state.
- Scene nodes coordinate runtime input, raycasts, UI, movement execution, generated visuals, and transient busy state.
- Prefer a stateless processor when a rule should be testable without loading the main scene.
- Editor tools mutate resource data and request a rebuild; generated scene nodes are not authoritative authored state.

## World and Resource Model

- **Environment** is static map geometry that may contribute baked navigation collision: ground, walls, static obstacles, and future static blocking props.
- **Objects and props** are authored entities that may be examined, moved, opened, harvested, looted, or otherwise manipulated.
- **Actors** are moving entities such as player characters, NPCs, enemies, and companions.
- Keep these concepts distinct rather than forcing dissimilar authored data into one vague resource.

Local and world maps use separate typed resources:

- `MapData` aggregates local grounds, continuous walls, door sockets, and world objects.
- `WorldMapData` owns a world map id and durable `WorldGeologyData` generator inputs. It does not persist fake local-map arrays.
- `MapLoader` dispatches local `MapData` to `MapBuilder` and world `WorldMapData` to `WorldMapBuilder`.
- Callers that require one route use `get_local_map_data()`, `get_world_map_data()`, and `is_world_map_loaded()`.
- Local save/load accepts only `MapData`; world save/load accepts only `WorldMapData`.
- `MapLoader.replace_map_data()` is the public editor rebuild entrypoint. Local replacements rebuild and rebake navigation; world replacements rebuild without a navigation bake.

`WorldObjectData.position: Vector3` is the canonical location for current actor/object data. `MoveTargetData.position: Vector3` carries exact clicked movement destinations. Splitting actors and props into dedicated resources remains deferred until their behavior diverges enough to justify it.

## Runtime Scene and Build Pipeline

`main.tscn` contains the native `NavigationRegion3D`, map loading/building, gameplay interaction and movement controllers, runtime UI and debug overlays, camera rig, editor controllers, and lighting.

The build pipeline is:

```text
Local: MapData -> MapLoader -> MapBuilder -> GeneratedMap -> navigation rebake
World: WorldMapData -> MapLoader -> WorldMapBuilder -> GeneratedMap
```

`MapBuilder` builds only local maps and maintains this generated subtree:

```text
GeneratedMap/
  StaticGrounds
  StaticWalls
  DoorSockets
  WorldObjects
```

Generated grounds, walls, door sockets, and world objects carry editor metadata so editor raycasts can resolve them back to source resources. `BlockoutObjectView` composes primitive visuals, `InteractionTarget`, hover highlighting, and `NavigationAgent3D` from `WorldObjectData`.

`WorldMapBuilder` builds:

```text
GeneratedMap/
  WorldPickSurface
  WorldMap3DLayer
```

The pick surface is hidden collision derived at runtime from `WorldMapData.geology.size_m`. The visible world layer is non-colliding terrain generated from geology data. World selection is data-only and must not create a macro-scale highlight shell.

## Static Environment and Navigation

- Grounds generate static collision and a child `GroundMoveTarget` `Area3D` for movement targeting.
- Walls are authored as `WallData` start/end floor-plane lines with height, thickness, and color; authored walls do not store rotation.
- `WallVisualResolver` derives each wall's center, box dimensions, and local orientation.
- `MapBuilder` creates one `BoxMesh` and `BoxShape3D` static collider on collision layer `1` per wall.
- Door openings are represented by non-blocking `DoorSocketData` markers after wall lines are split around a gap. Door sockets do not contribute navigation collision.
- `MapLoader.rebake_navigation()` configures the `NavigationMesh` to parse static colliders and bakes the `NavigationRegion3D`.

Static props or obstacles that affect baked navigation belong under `src/environment/`. Dynamic or interactable props remain under `src/objects/` until a dedicated `src/props/` split is justified.

## Movement and Gameplay Input

- Movement is free-form 3D movement using `Vector3`; do not add custom grid, hex, square-cell, axial-coordinate, or discrete-cell movement logic.
- Pathfinding uses `NavigationServer3D`, `NavigationRegion3D`, and `NavigationAgent3D`.
- `MoveTargetResolver` owns stateless movement validation, including native path checks through `NavigationServer3D.map_get_path()`.
- Valid movement sources are enabled `WorldObjectData` targets with `object_kind == &"player_character"`.
- Valid destinations are enabled move-target nodes backed by `MoveTargetData`.
- `MovementController` listens for `EventBus.move_requested`, validates again, and drives the actor's `NavigationAgent3D`.
- Actor nodes and `WorldObjectData.position` remain synchronized during movement; arrival snaps both to the exact requested destination.
- Gameplay-only input must be gated to game mode so editor pointer ownership, raycasts, context menus, and camera behavior remain isolated.

Movement action points, terrain costs, movement ranges, turn budgets, actor occupancy, and collision-aware endpoint reservations are not implemented.

## Interaction and Debugging

- Gameplay raycasts hit `InteractionTarget` `Area3D` wrappers on collision layer `1`.
- `InteractionActionResolver` owns context-action and examine resolution; visual nodes must not hardcode those rules.
- Player-character objects expose `Move`; other current world objects expose `Examine`.
- Ground movement targets are intentionally non-highlightable to avoid a map-sized hover shell.
- Interaction remains independent from navigation except when movement validates a clicked destination.
- `F12` toggles the debug log panel and navigation debug overlay.

## Runtime Editor Contract

The first development surface is an in-game runtime editor under `src/editor/`, not a Godot `EditorPlugin`.

- Escape opens the centered dev menu and switches among `game`, local `editor`, and `world_editor` modes.
- Game mode owns movement, hover, context-menu, and examine input. Editor modes disable gameplay targeting and own their pointer capture, raycasts, tools, inspection, and save/load actions.
- Startup local editor mode keeps the `MapLoader` map configured in `main.tscn`; it creates an in-memory blank map only when no current local map exists.
- The editor panel is a draggable, collapsed-by-default dock. Right-drag over the dock moves it; right-drag elsewhere remains camera pan.
- `EditorPanel` emits UI intent. `EditorSelectionController` owns selection, previews, and resource mutations. `EditorModeController` owns mode transitions and local/world state restoration.
- Active tool changes flow through `EventBus.editor_tool_changed`.

Local tools:

- **Select/Inspect:** resolves generated metadata and presents a read-only inspector for grounds, walls, door sockets, and world objects.
- **Ground:** whole-meter X/Z sliders resize the primary `GroundData`, creating a default ground only when none exists.
- **NPC Brush / PC Brush:** append the corresponding `WorldObjectData` on ground clicks, rebuild/rebake, and clear selection so repeated painting is uninterrupted. Multiple player-character objects are valid movement sources.
- **Wall Brush:** line mode appends one wall from two clicks; rectangle mode appends four enclosing walls from opposite corners.
- **Door Brush:** snaps to the nearest wall, leaves 0.5m edge clearance, splits a 1m opening, and appends a `DoorSocketData` marker.
- **Bldg. Brush:** previews a deterministic BSP shell at 50% opacity. Width, depth, minimum room size, target room count, and seed are adjustable; explicit Submit flattens walls and door sockets into `MapData`.

World editor behavior:

- Entering world mode caches the in-memory local map and swaps to a separate world map. Returning through either local editor or game mode restores that local map.
- World mode exposes only Select, Ground, and Geology tools.
- World Ground edits `WorldMapData.geology.size_m` with X/Z ranges from 250km to 1000km.
- Geology inputs include seed, optional directional coast, scale, roughness, sea level, temperature, rainfall, wind direction, erosion, vegetation, tree canopy, tectonic ridge alignment, and toxicity.
- `WorldGeologyGenerator` combines Simplex terrain, ridged tectonic noise, coast lowering, erosion smoothing, directional rain-shadow moisture, latitude/altitude temperature, and biome coloring into render buffers.
- The visible `WorldMap3DLayer` uses normals, unshaded vertex colors, disabled culling, and macro custom bounds.
- `CameraRig` retains its input bindings but uses separate macro height, zoom, pan, clipping, and ray-distance settings. Local and world camera positions are stored independently.

## Generation Model

- Deterministic generators belong under `src/generation/`; runtime editor orchestration does not belong there.
- Reusable map pieces should use resource-backed modules, placement descriptors, and generator presets when those systems are introduced.
- Placement descriptors should carry local position, rotation, footprint or bounds, seed, selected module or preset, and tool-authored parameters.
- The current BSP generator is a stateless processor that partitions a rectangular footprint, connects partitioned rooms with doors, and adds at least one exterior door.
- Cellular, quadrant, brush, noise, and coordinate language may describe generation or authoring, but must never become custom grid movement.

## Directory Ownership

```text
res://src/core/          Global infrastructure; currently EventBus.
res://src/camera/        Camera rig behavior.
res://src/environment/   Static map geometry, geology data, and baked blockers.
res://src/maps/          Local/world map aggregation, building, loading, and navmesh rebaking.
res://src/objects/       Current blockout object data and composed views.
res://src/interaction/   Targets, hover, action resolution, and gameplay targeting.
res://src/movement/      Move targets, movement validation, execution, and gameplay control.
res://src/ui/            Runtime interaction and debug UI.
res://src/editor/        Runtime editor modes, tools, inspection, persistence, and editor-only input.
res://src/generation/    Stateless deterministic generators and generation resolvers.
res://data/              Authored resources only; no gameplay logic.
res://scenes/            Playable scenes and reusable scene roots.
res://tests/             Headless smoke and integration coverage.
res://scripts/           Development and validation scripts.
```

Future domain directories such as `src/actors/`, `src/props/`, `src/combat/`, `src/inventory/`, `src/dialogue/`, and `src/quests/` should be created only when implemented behavior establishes a real ownership boundary. Future authored module, generator-preset, and world resources belong under corresponding subdirectories of `data/`.

## Visual and Prototype Scope

- Current visuals are primitive blockout geometry using Godot meshes and simple materials.
- Debug visuals are appropriate when they clarify movement, targeting, navigation, generation, or editor behavior.
- Do not build complex models, animation pipelines, or asset-heavy systems until gameplay architecture requires them.

## Testing and Diagnostics

- Add focused tests for new resources, processors, resolvers, scene coordinators, editor tools, and interaction or movement behavior.
- Keep regression coverage close to the subsystem being changed.
- Because the main scene starts in editor mode, gameplay tests must explicitly enter game mode before asserting game-only behavior.
- If movement fails, inspect navmesh baking, native map assignment, path validity, and snap tolerance.
- If interaction raycasts miss, inspect `Area3D.input_ray_pickable`, collision layer `1`, and the controller collision mask.
- If world selection works but terrain is invisible, inspect normals, material override, culling, custom bounds, and camera state before changing generation.
- Run `./scripts/run-tests.sh` and `./scripts/check.sh` before finishing code changes.

## Forbidden Patterns

- No custom grid or hex pathfinding for movement.
- No durable tactical state in broad manager nodes.
- No direct coupling between unrelated scene systems when an event, signal, or resolver boundary fits.
- No editor behavior added to gameplay controllers merely to share input handling.
- No hidden world-mode flags on local `MapData`; use typed local/world routing.
- No generated scene nodes treated as authoritative authored data.
- No hidden generated files or editor-local configuration committed as source.
