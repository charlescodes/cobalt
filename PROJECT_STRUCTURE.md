# COBALT Project Structure

Last updated: 2026-05-24

Purpose: quick-reference file map for future context windows. Keep this updated when scenes, controllers, processors, resources, or tests move.

## Source of Truth Docs

```text
res://ARCHITECTURE.md             Non-negotiable project architecture rules.
res://DECISIONS.md                Current architectural decisions, deferred behavior, and watch items.
res://PROJECT_STRUCTURE.md        This path map.
res://docs/PROJECT_OVERVIEW.md    Narrative runtime overview and current gameplay snapshot.
```

## Project Entry Points

```text
res://project.godot               Godot config, main scene path, input map, and EventBus autoload.
res://scenes/main.tscn            Main playable 3D blockout scene.
res://src/core/event_bus.gd       Global event bus autoload.
```

## Debug Map Generation

```text
res://src/debug/bsp_module_data.gd          Runtime-only BSP generation parameters and generated BSP state.
res://src/debug/bsp_room_processor.gd       Stateless BSP room, wall, door, ground, and debug MapData compiler.
res://src/debug/bsp_debug_map_controller.gd Starts main.tscn in generated BSP debug map mode; F12 restores authored map.
res://src/editor/level_editor_controller.gd Generic level-editor input coordinator and active EditorTool dispatcher.
res://src/editor/tools/editor_tool.gd       Base editor tool interface.
res://src/editor/tools/bsp_level_editor_tool_provider.gd
                                             Registers BSP Select/Door/Resize editor tools.
res://src/editor/tools/bsp_room_select_tool.gd
res://src/editor/tools/bsp_door_tool.gd
res://src/editor/tools/bsp_resize_tool.gd
                                             Runtime BSP room selection, manual doors, and split resizing tools.
```

## Main Scene Composition

`res://scenes/main.tscn` currently contains:

```text
Main
NavigationRegion3D                Native navmesh owner for generated map collision.
MapLoader                         Loads authored MapData and rebakes navigation.
InteractionController             Camera raycasts, hover, context menus, and movement targeting.
MovementController                EventBus movement listener and nav-agent movement coordinator.
BspDebugMapController             F12 runtime-only BSP debug map toggle.
LevelEditorController             Generic level-editor input coordinator.
LevelEditorController/BspLevelEditorToolProvider
                                  BSP editor tool registrar.
InteractionUI                     CanvasLayer containing interaction UI panels.
InteractionUI/InteractionMenu     Context action menu.
InteractionUI/InteractionLogPanel Examine output panel.
InteractionUI/CameraCompass       50px camera-orientation compass.
InteractionUI/BspDebugPanel       Right-side BSP generation, overlay, and edit-mode controls.
SunLight                          Directional blockout lighting.
CameraRig                         Isometric-style camera rig.
CameraRig/PitchPivot/Camera3D     Active camera.
```

## Authored Data

```text
res://data/maps/main_blockout_map.tres
```

Current sample map resource. Contains ground data, static wall segments, player-character data, and NPC data.

## Data Resource Scripts

```text
res://src/maps/map_data.gd             Map id plus ground, wall, and object arrays.
res://src/maps/ground_data.gd           Static ground id, position, size, and color.
res://src/walls/wall_segment_data.gd   Static wall endpoints, height, thickness, and color.
res://src/objects/world_object_data.gd World object id, kind, position, size, color, and hoverability.
res://src/movement/move_target_data.gd Exact Vector3 destination selected by ground raycasts.
```

## Stateless Processors and Resolvers

```text
res://src/maps/map_builder.gd                  Builds generated scene nodes from MapData.
res://src/walls/wall_visual_resolver.gd        Derives wall visual center, length, and rotation.
res://src/interaction/interaction_action_resolver.gd
                                                Resolves context actions and examine output.
res://src/movement/move_target_resolver.gd     Validates move sources, destinations, and native nav paths.
```

Rule logic belongs here or in new stateless processors. Do not move tactical rules into scene nodes.

## Scene Coordinators

```text
res://src/maps/map_loader.gd              Scene adapter for MapBuilder and NavigationRegion3D rebaking.
res://src/interaction/interaction_controller.gd
                                           Camera raycasts, hover state, context menus, and targeting flow.
res://src/movement/movement_controller.gd EventBus movement handler and active nav-agent movement runner.
res://src/camera/camera_rig.gd            Camera pan, orbit, and zoom behavior.
res://src/editor/level_editor_controller.gd
                                           Generic level-editor input, ground projection, and active tool lifecycle.
```

These nodes may coordinate runtime behavior, but durable gameplay rules should remain in resources or stateless processors.

## World Object and Interaction Components

```text
res://src/objects/blockout_object_view.gd   Primitive object visual, InteractionTarget, HoverHighlighter, and NavigationAgent3D.
res://src/interaction/interaction_target.gd Reusable Area3D wrapper for hover/click targeting.
res://src/interaction/hover_highlighter.gd  Transparent hover shell for highlighted targets.
```

## UI Components

```text
res://src/ui/interaction_menu.gd      Context menu for target actions.
res://src/ui/interaction_log_panel.gd Examine output panel and interaction log toggle.
res://src/ui/camera_compass.gd        Small HUD compass that draws camera heading.
res://src/ui/bsp_debug_panel.gd       Runtime BSP width/depth/min-room/depth/seed controls plus Select/Door/Resize edit modes.
res://src/ui/navigation_debug_overlay.gd
                                      Movement path markers plus BSP rooms, walls, sockets, selected-room, and exit-route overlays.
```

## Walls and Navigation Geometry

```text
res://src/walls/wall_segment_data.gd    Wall data resource.
res://src/walls/wall_visual_resolver.gd Stateless wall geometry helper.
res://src/walls/wall_layout_view.gd     Focused wall layout view retained for tests/tools.
```

Wall collision generated from map data must remain static so `NavigationRegion3D` can bake native navigation around it.

## Tests

```text
res://tests/test_runner.gd                  Headless smoke/integration orchestrator.
res://tests/support/test_context.gd         Shared fixtures and helpers.
res://tests/suites/camera_suite.gd          Camera behavior coverage.
res://tests/suites/interaction_ui_suite.gd  Interaction UI coverage.
res://tests/suites/main_scene_raycast_suite.gd
                                             Main-scene raycast and targeting coverage.
res://tests/suites/main_scene_suite.gd      Main scene composition coverage.
res://tests/suites/map_builder_suite.gd     Map generation and collision coverage.
res://tests/suites/bsp_room_processor_suite.gd
                                             BSP generation, wall carving, edit helpers, buffered ground, and actor spawn coverage.
res://tests/suites/bsp_debug_editor_suite.gd
                                             BSP debug panel/editor/overlay integration coverage.
res://tests/suites/movement_controller_suite.gd
                                             Movement controller coverage.
res://tests/suites/native_navigation_suite.gd
                                             Native nav validation coverage.
res://tests/suites/object_composition_suite.gd
                                             Blockout object composition coverage.
res://tests/suites/project_config_suite.gd  Godot config and autoload coverage.
res://tests/suites/wall_layout_suite.gd     Wall layout coverage.
```

## Scripts

```text
res://scripts/godot-env.sh    Shared Godot executable discovery.
res://scripts/run-tests.sh    Headless smoke/integration tests.
res://scripts/check.sh        Current full validation wrapper.
res://scripts/open-editor.sh  Launches the Godot editor for this project.
```

## Future File Map Template

When new systems are added, extend the relevant section above and keep paths grouped by responsibility.

```text
res://src/combat/              Future combat resources, processors, and scene adapters.
res://src/inventory/           Future inventory resources, processors, and UI adapters.
res://src/dialogue/            Future dialogue resources, processors, and UI adapters.
res://src/quests/              Future quest data and stateless validation/progression helpers.
res://data/                    Authored resources only; no gameplay logic.
res://scenes/                  Playable scenes and reusable scene roots.
res://tests/suites/            One focused suite per subsystem.
```
