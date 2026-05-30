# COBALT Architecture

Last updated: 2026-05-30

Purpose: stable project rules for COBALT. This file defines what must stay true as systems grow. Use `DECISIONS.md` for current implementation state and `PROJECT_STRUCTURE.md` for file locations.

## Core Principles

- **Data-driven:** Authored game state lives in custom `Resource` scripts. Do not hardcode durable gameplay values into scene nodes.
- **Composition over inheritance:** Use Godot node composition, small focused scripts, duck typing, signals, and groups instead of deep inheritance trees.
- **Event-based coordination:** Major cross-system events flow through the `EventBus` autoload. Avoid direct node references between unrelated systems.
- **Capability-based interaction:** Interactable behavior is a capability. Actors, props, doors, containers, harvestables, and environment pieces may expose interaction profiles without all becoming the same data type.

## Data and Logic Boundaries

- Resource scripts own authored data: identity, position, sizes, colors, static geometry, and future content definitions.
- Stateless processors and resolvers own durable gameplay rules. They may inspect resources, nodes, and `Vector3` values, but should not store active tactical state.
- Scene nodes coordinate runtime behavior only: input, raycasts, UI updates, movement execution, generated visuals, and transient busy state.
- If a rule must be testable without loading the main scene, prefer a stateless `RefCounted` processor.

## World Model

- **Environment** is static map geometry that may contribute baked navigation collision: ground, walls, static obstacles, and future static blocking props.
- **Objects and props** are authored world entities that can be examined, interacted with, moved, opened, harvested, looted, or otherwise manipulated.
- **Actors** are moving entities such as the player character, NPCs, enemies, and companions.
- Keep these concepts distinct. Do not force ground, walls, actors, and containers into one vague resource if their authoring data differs.
- Scale is `1 Godot unit = 1 meter`.

## Movement and Navigation

- Movement is free-form 3D movement on a continuous plane using `Vector3`.
- Do not introduce grid, hex, square-cell, axial-coordinate, or cell-blocking movement logic.
- Pathfinding must rely on Godot native navigation, especially `NavigationServer3D`, `NavigationRegion3D`, and `NavigationAgent3D`.
- Static environment collision must be bakeable by `NavigationRegion3D`.
- Actors use `NavigationAgent3D` for path following and steering. Tactical movement validation belongs in resolvers, not actor nodes.

## Interaction

- Interaction raycasts hit `Area3D` wrappers such as `InteractionTarget`.
- Interaction should remain decoupled from navigation except when a movement action validates a clicked destination.
- Context actions should be resolved through focused resolvers, not hardcoded into visual nodes.
- Examine behavior should be reusable across actors, props, containers, doors, harvestables, and future interactables.

## Visuals and Prototype Scope

- Current visuals are primitive blockout geometry using Godot meshes and simple materials.
- Do not build complex models, animation pipelines, or asset-heavy systems until the gameplay architecture needs them.
- Debug visuals and overlays are acceptable when they clarify movement, targeting, or navigation behavior.

## Testing Expectations

- Add focused tests for new resources, resolvers, scene coordinators, and interaction or movement behavior.
- Keep regression coverage close to the subsystem being changed.
- Run `./scripts/check.sh` before finishing code changes.

## Forbidden Patterns

- No custom grid or hex pathfinding for movement.
- No durable tactical state in broad manager nodes.
- No direct coupling between unrelated scene systems when an event or resolver boundary fits.
- No hidden generated files or editor-local configuration committed as source.
