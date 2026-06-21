# Changelog

All notable project changes are recorded here as user- or contributor-relevant outcomes. Current design belongs in `ARCHITECTURE.md`; future intent belongs in `ROADMAP.md`.

## Unreleased

### Added

- Added runtime local-map editor V1 behind an Escape dev menu, including game/editor mode switching, a draggable collapsed tool dock, local map save/load, selection and read-only inspection, ground resizing, NPC and PC painting, line/rectangle wall painting, and snapped door openings.
- Added a deterministic BSP building generator and `Bldg.` brush with configurable seed, dimensions, room targets, translucent preview, explicit Submit, connected partition doors, and an exterior door.
- Added runtime World editor mode with separate world-map persistence, macro ground sizing, geology controls, deterministic terrain and climate generation, rain-shadow moisture, biome coloring, macro camera behavior, and a non-colliding visible terrain layer over a hidden pick surface.
- Added typed `WorldMapData` and `WorldMapBuilder` paths so durable world maps no longer reuse local `MapData` arrays or persist a fake `grounds[0]`.
- Added focused regression coverage for runtime editor tools, mode switching, save/load routing, generated metadata, world generation, camera scaling, map building, interaction, movement, and navigation.

### Changed

- Runtime startup now enters local editor mode while preserving the configured main blockout map; game mode remains available through the Escape dev menu.
- Local and world maps now use separate typed save/load routes under `data/editor_maps` and `data/world_maps`, with mode-aware file actions and local-state restoration after World mode.
- Replaced legacy wall resources with continuous `WallData` lines while retaining box-based visual and static-collision generation.
- Consolidated repository guidance into `AGENTS.md`, `ARCHITECTURE.md`, `ROADMAP.md`, and `CHANGELOG.md`; architecture now owns durable decisions and directory boundaries, while roadmap and changelog exclusively own future and completed work.

### Fixed

- Fixed World mode rendering as a blank or grey view by using macro camera clipping, unshaded two-sided vertex colors, explicit render bounds, normals, and a hidden pick-only surface.
- Fixed returning from World mode leaving the local editor camera at a macro-scale position.
- Fixed local editor load actions accepting world maps and fixed local/world ground-state collisions during save, load, and mode switching.
- Fixed gameplay interaction input remaining active in World editor mode.
- Fixed the editor inspector collapsing to a one-character wrapping width and normalized tool-panel layout.

## 2026-05-30

### Changed

- Consolidated static environment scripts under `src/environment/` and updated map resources, tests, and ownership documentation.

## 2026-05-21

### Added

- Added F12-controlled navigation and movement debug overlays and logs.

### Changed

- Renamed floor concepts to ground and refreshed documentation after navigation and map updates.

### Fixed

- Fixed debug navigation overlay and repeated movement behavior.

## 2026-05-18

### Added

- Implemented the map resource loading pipeline.

## 2026-05-16

### Changed

- Modularized the Godot headless test runner into focused suites.

## 2026-05-15

### Changed

- Refreshed project documentation for the native-navigation refactor, renamed the project through Godot configuration, and normalized `main.tscn` after an editor save/import.
