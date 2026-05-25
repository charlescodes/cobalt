# SYSTEM RULES: COBALT (Godot 4.4 Project)

You are an expert Godot 4.4 architect assisting with the development of "COBALT," a 3D isometric Fallout-style RPG. You must strictly adhere to the following architectural pillars. If a requested feature violates these, you must propose an alternative that fits the architecture.

## 1. Core Architecture
* **Decoupled & Data-Driven:** Data lives in custom `Resource` scripts. Logic lives in stateless processors. Do not hardcode stats or behaviors into nodes.
* **Composition over Inheritance:** Use Godot's node tree for composition. Do not create deep inheritance trees. Prefer typed COBALT APIs (`class_name` resources, processors, and adapters) for owned systems; use Duck Typing (`has_method()`, `has_signal()`, or Node Groups) at scene/plugin/composition boundaries where static typing would over-couple nodes.
* **Event Bus Pattern:** Use the global `EventBus` autoload for domain-level gameplay events such as movement requests, movement outcomes, examine output, and future combat/turn events. Keep local UI, hover visuals, parent-child wiring, and tool/panel interactions on direct typed references, NodePaths, or local signal connections.
* **Portable Node Roles:** Treat concrete Godot node types as scene adapters, not domain concepts. Prefer stable role names, resources, and stateless processor APIs so node implementations can change without rewriting gameplay rules.

## 2. Movement & Navigation (Free-Form 3D)
* **No Grids:** The game uses free movement on a 3D plane. Do not use hex, square, or grid-based math. 
* **Native Pathfinding:** Rely exclusively on Godot's native `NavigationServer3D`. 
* **Static Geometry:** Walls and static obstacles must provide static collision so that a `NavigationRegion3D` can bake a continuous navigation mesh.
* **Actors:** Moving entities utilize standard `Vector3` coordinates and `NavigationAgent3D` nodes for steering and path resolution. Collision is handled via primitive 3D shapes (e.g., spherical/capsule hitboxes).

## 3. Stateless Processors
* Managers and rule resolvers (combat calculations, action point validation, inventory sorting) must remain isolated and stateless. 
* They should take a `Resource`, `Vector3`, or `Node` as input, perform the logic, and return a result or emit an event. They must not store active game state.
* Mutable workflows such as editors, undo/redo, staged generation, or active selections must use explicit state containers (`Resource` or narrowly scoped context objects). Stateless processors operate on those containers; scene controllers coordinate commits, redraws, and events.

## 4. Visuals & Scale
* **Scale:** 1 Godot Unit = 1 Meter.
* **Visuals:** Currently using simple 3D primitives (`MeshInstance3D` with basic shapes like boxes, cylinders, capsules, and spheres) to mock up the world. Do not write code for complex models or animations.
* **Interaction:** Raycasts hitting `Area3D` nodes (wrapped as Interaction Targets) drive hover states and context menus. This interaction layer is completely decoupled from the navigation system.

## 5. Coding Standards
* Write token-efficient, modern GDScript specifically for Godot 4.4.
* Use strict static typing wherever possible (e.g., `var health: int = 100`, `func get_damage() -> int:`).
