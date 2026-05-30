# Changelog

All notable project changes should be recorded here. Keep entries factual and chronological. Use `DECISIONS.md` for rationale and active design notes.

## Unreleased

### Added

- Added `AGENTS.md` as the short entrypoint to the repository documentation set.
- Added `ROADMAP.md` as the forward-looking planning template.
- Added `CHANGELOG.md` as the formal running history.

### Changed

- Sharpened `ARCHITECTURE.md`, `DECISIONS.md`, and `PROJECT_STRUCTURE.md` into distinct source-of-truth documents.
- Expanded `ROADMAP.md` with procedural world generation, editor tooling, faction/population, agent, quest-seed, and world-history milestones.
- Planned the first editor direction as an Escape-driven runtime editor mode with separate editor tools, module libraries, placement descriptors, and generator presets.
- Expanded future roadmap coverage for map components, procedural structures, sockets, city-block composition, world-map editor tooling, sparse region-scale generation, points of interest, and spawn placement.

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
