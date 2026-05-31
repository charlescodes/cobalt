# COBALT Project Structure

Last updated: 2026-05-30

Purpose: filesystem index and ownership map. This file tells contributors and agents where code lives and where new files should go. Use `ARCHITECTURE.md` for rules and `DECISIONS.md` for current reasoning and handoff notes.

## Source of Truth Docs

```text
res://AGENTS.md                  Short entrypoint for agents and contributors.
res://ARCHITECTURE.md        Stable architecture rules and forbidden patterns.
res://DECISIONS.md           Current design ledger, deferred behavior, and handoff notes.
res://PROJECT_STRUCTURE.md   File ownership index.
res://ROADMAP.md             Forward-looking planning template.
res://CHANGELOG.md           Formal running history of notable changes.
```

## Directory Ownership

```text
res://src/core/          Global infrastructure, currently EventBus.
res://src/camera/        Camera rig behavior.
res://src/environment/   Static map geometry: ground, walls, door sockets, baked obstacles, and future static blocking props.
res://src/maps/          MapData aggregation, generated map building, map loading, and navmesh rebaking.
res://src/objects/       Current blockout world-object data and views; future split point for props/actors.
res://src/interaction/   Interaction targets, hover highlighting, context action resolution, and input targeting.
res://src/movement/      Move target data, movement validation, and movement execution.
res://src/ui/            Runtime UI panels, debug log, and debug navigation overlay.
res://src/editor/        Runtime editor mode, editor tools, inspectors, save/load, and editor-only input.
res://src/generation/    Future deterministic procedural generators and generation resolvers.
res://data/              Authored resources only; no gameplay logic.
res://scenes/            Playable scenes and reusable scene roots.
res://tests/             Headless smoke and integration coverage.
res://scripts/           Local development and validation scripts.
```

## Project Entry Points

```text
res://project.godot          Godot config, main scene path, input map, and EventBus autoload.
res://scenes/main.tscn       Main playable 3D blockout scene.
res://src/core/event_bus.gd  Global event bus autoload.
```

## Main Scene Composition

`res://scenes/main.tscn` currently contains:

```text
Main
NavigationRegion3D                Native navmesh owner for generated static collision.
MapLoader                         Loads authored MapData and rebakes navigation.
InteractionController             Camera raycasts, hover, context menus, and movement targeting.
MovementController                EventBus movement listener and nav-agent movement coordinator.
InteractionUI                     CanvasLayer containing interaction UI panels.
InteractionUI/InteractionMenu     Context action menu.
InteractionUI/InteractionLogPanel Examine output panel.
InteractionUI/DebugLogPanel       F12 debug event log panel.
InteractionUI/DevMenu             Escape dev menu for mode and map save/load actions.
InteractionUI/EditorPanel         Runtime editor tool and read-only inspector panel.
NavigationDebugOverlay            3D movement/path/failure markers.
DebugOverlayController            F12 debug visibility toggle.
EditorSelectionController         Editor-mode raycast selection and highlight owner.
EditorModeController              Game/editor mode owner and editor map save/load coordinator.
SunLight                          Directional blockout lighting.
CameraRig                         Isometric-style camera rig.
CameraRig/PitchPivot/Camera3D     Active camera.
```

## Authored Data

```text
res://data/maps/main_blockout_map.tres
res://data/editor_maps/<name>.tres
```

Current sample map resource plus runtime editor save targets. Map resources can contain ground data, continuous static walls, door socket data, player-character data, and NPC data.

## Core Data Resources

```text
res://src/maps/map_data.gd                 Map id plus ground, wall, door socket, and world-object arrays.
res://src/environment/ground_data.gd       Static ground id, position, size, and color.
res://src/environment/wall_data.gd         Static wall line endpoints, height, thickness, and color.
res://src/environment/door_socket_data.gd  Static door opening socket id, position, width, orientation, and marker color.
res://src/objects/world_object_data.gd     Current actor/object id, kind, position, size, color, and hoverability.
res://src/movement/move_target_data.gd     Exact Vector3 destination selected by ground raycasts.
```

Future authored data locations:

```text
res://data/modules/            Future reusable environment module resources.
res://data/generator_presets/  Future deterministic generator preset resources.
res://data/world/              Future world-map, zone, faction, population, and campaign resources.
```

## Processors, Resolvers, and Coordinators

```text
res://src/maps/map_builder.gd                         Builds generated scene nodes from MapData.
res://src/maps/map_loader.gd                          Scene adapter for MapBuilder and NavigationRegion3D rebaking.
res://src/environment/wall_visual_resolver.gd          Derives wall visual center, length, and rotation.
res://src/interaction/interaction_action_resolver.gd   Resolves context actions and examine output.
res://src/interaction/interaction_controller.gd        Camera raycasts, hover state, context menus, and targeting flow.
res://src/movement/move_target_resolver.gd            Validates move sources, destinations, and native nav paths.
res://src/movement/movement_controller.gd             EventBus movement handler and active nav-agent movement runner.
res://src/camera/camera_rig.gd                        Camera pan, orbit, and zoom behavior.
res://src/editor/editor_mode_controller.gd             Escape dev menu mode and map save/load coordinator.
res://src/editor/editor_selection_controller.gd        Editor-only select/inspect, NPC brush, PC brush, wall brush, and door brush input for generated map content.
res://src/editor/map_file_store.gd                     Sanitized MapData save/load under data/editor_maps.
```

## Components and UI

```text
res://src/objects/blockout_object_view.gd      Primitive object visual, InteractionTarget, HoverHighlighter, and NavigationAgent3D.
res://src/interaction/interaction_target.gd    Reusable Area3D wrapper for hover/click targeting.
res://src/interaction/hover_highlighter.gd     Transparent hover shell for highlighted targets.
res://src/ui/interaction_menu.gd               Context menu for target actions.
res://src/ui/interaction_log_panel.gd          Examine output panel and interaction log toggle.
res://src/ui/debug_log_panel.gd                F12 debug log panel.
res://src/ui/navigation_debug_overlay.gd       3D movement/path/failure debug markers.
res://src/ui/debug_overlay_controller.gd       F12 debug visibility controller.
res://src/editor/dev_menu.gd                   Centered Escape dev menu UI.
res://src/editor/editor_panel.gd               Draggable editor tool dock, tool panels, and read-only inspector.
res://src/editor/editor_selection_highlighter.gd Editor selection highlight shells.
```

## Tests

```text
res://tests/test_runner.gd                         Headless smoke/integration orchestrator.
res://tests/support/test_context.gd                Shared fixtures and helpers.
res://tests/suites/camera_suite.gd                 Camera behavior coverage.
res://tests/suites/editor_suite.gd                 Runtime editor mode, tool dock, selection, NPC brush, PC brush, wall brush, door brush, inspector, and save/load coverage.
res://tests/suites/interaction_ui_suite.gd         Interaction UI coverage.
res://tests/suites/main_scene_raycast_suite.gd     Main-scene raycast and targeting coverage.
res://tests/suites/main_scene_suite.gd             Main scene composition coverage.
res://tests/suites/map_builder_suite.gd            Map generation and collision coverage.
res://tests/suites/movement_controller_suite.gd    Movement controller coverage.
res://tests/suites/native_navigation_suite.gd      Native nav validation coverage.
res://tests/suites/navigation_debug_overlay_suite.gd Debug overlay coverage.
res://tests/suites/object_composition_suite.gd     Blockout object composition coverage.
res://tests/suites/project_config_suite.gd         Godot config and autoload coverage.
res://tests/suites/wall_layout_suite.gd            Wall layout coverage.
```

## Scripts

```text
res://scripts/godot-env.sh    Shared Godot executable discovery.
res://scripts/run-tests.sh    Headless smoke/integration tests.
res://scripts/check.sh        Current full validation wrapper.
res://scripts/open-editor.sh  Launches the Godot editor for this project.
```

## Future File Placement

```text
res://src/environment/static_obstacle_data.gd  Future baked blockers that are not continuous walls.
res://src/editor/                              Future runtime editor mode controllers, editor tools, inspectors, and panels.
res://src/generation/                          Future deterministic procedural generators and resolvers.
res://src/actors/                              Future actor resources, views, and actor-specific coordinators.
res://src/props/                               Future doors, shelves, lockers, harvestables, and containers.
res://src/combat/                              Future combat resources, processors, and scene adapters.
res://src/inventory/                           Future inventory resources, processors, and UI adapters.
res://src/dialogue/                            Future dialogue resources, processors, and UI adapters.
res://src/quests/                              Future quest data and stateless progression helpers.
```

Static props or obstacles that affect baked navigation should start in `src/environment/`. Runtime editor tooling should start in `src/editor/`, while deterministic content-generation logic should start in `src/generation/`. Dynamic or interactable props should stay in `src/objects/` until a dedicated `src/props/` split is justified.
