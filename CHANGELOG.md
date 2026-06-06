# Changelog

All notable project changes should be recorded here. Keep entries factual and chronological. Use `DECISIONS.md` for rationale and active design notes.

## Unreleased

### Added

- Added `AGENTS.md` as the short entrypoint to the repository documentation set.
- Added `ROADMAP.md` as the forward-looking planning template.
- Added `CHANGELOG.md` as the formal running history.
- Added runtime local-map editor V1 behind an Escape dev menu, with game/editor mode switching, map save/load, select/inspect tooling, editor selection highlighting, and a read-only inspector.
- Added editor-focused test coverage for mode switching, generated-node metadata, selection, inspector display, and MapData save/load.
- Added a draggable, collapsed-by-default editor tool dock with Select/Inspect and NPC Brush tools.
- Added NPC Brush placement for non-player-character blockout objects, including rebuild/rebake while keeping selection clear for repeated painting.
- Added editor test coverage for tool switching, dock dragging, and NPC brush placement.
- Added a Wall Brush editor tool with line and rectangle modes for two-click static wall placement and map rebuild/rebake.
- Added a Door Brush editor tool that snaps to walls, splits a 1m opening with 0.5m edge clearance, and draws a light grey-green door socket marker.
- Added a PC Brush editor tool for placing multiple controllable player-character blockout objects.
- Added a deterministic BSP building generator and `Bldg.` editor brush with seed/size/room sliders, translucent preview, Submit commit flow, partition door sockets, and an exterior door socket.
- Added a `Ground` editor tool with whole-meter X/Z sliders that resize the primary ground plane and rebuild/rebake the map.
- Added Escape-driven World editor mode with macro-scale ground sizing, a Geology tool, deterministic terrain/climate generation, rain-shadow moisture, biome coloring, and a non-colliding 3D world map layer.
- Added world editor regression coverage for mode switching, tool visibility, macro ground ranges, geology controls, camera scale, and deterministic/coastal generation.

### Changed

- Camera controls now switch to macro-scale pan and zoom settings while World editor mode is active.
- World map loading now routes saved world resources back into World editor mode instead of reusing local editor state.
- World maps now hide the macro ground box, render the generated terrain layer as the visible world surface, and keep world selection data-only without macro highlight shells.
- Runtime startup now enters editor mode by default and keeps the configured main blockout map as the editable map instead of replacing it with a blank editor map.
- Sharpened `ARCHITECTURE.md`, `DECISIONS.md`, and `PROJECT_STRUCTURE.md` into distinct source-of-truth documents.
- Expanded `ROADMAP.md` with procedural world generation, editor tooling, faction/population, agent, quest-seed, and world-history milestones.
- Planned the first editor direction as an Escape-driven runtime editor mode with separate editor tools, module libraries, placement descriptors, and generator presets.
- Expanded future roadmap coverage for map components, procedural structures, sockets, city-block composition, world-map editor tooling, sparse region-scale generation, points of interest, and spawn placement.
- Replaced legacy wall resources with continuous `WallData` resources while keeping solid `BoxMesh`/`BoxShape3D` generation per wall.

### Fixed

- Fixed World editor mode rendering as a grey/blank view by using macro camera clip distances, unshaded two-sided biome vertex colors, explicit macro render bounds, and a hidden pick-only ground surface.
- Fixed returning from World mode leaving the local editor camera at a macro-scale pan position.
- Fixed local/world ground state collision that could shrink saved world maps to local editor dimensions after save/load or mode switching.
- Fixed gameplay interaction input remaining enabled in World editor mode.
- Fixed the editor inspector label collapsing to a one-character wrapping width inside the scroll panel and normalized tool panel content layout.

## 2026-05-30

### Changed

- Consolidated static environment scripts under `src/environment/`.
- Updated map resources, tests, and structure documentation for the environment directory.

## 2026-05-21

### Added

- Added debug overlay and debug log support for navigation and movement events.
- Added F12 debug visibility toggling.

### Changed

- Renamed floor concepts to ground.
- Refreshed documentation after navigation and map updates.

### Fixed

- Fixed debug navigation overlay behavior.
- Fixed repeated movement behavior.

## 2026-05-18

### Added

- Implemented the map resource loading pipeline.

## 2026-05-16

### Changed

- Modularized the Godot headless test runner into focused suites.

## 2026-05-15

### Changed

- Refreshed project overview documentation for the COBALT navigation refactor.
- Renamed the project appropriately through Godot project configuration.
- Normalized `main.tscn` after Godot editor save/import.
