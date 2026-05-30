# COBALT Roadmap

Last updated: 2026-05-30

Purpose: forward-looking planning for major systems, milestones, and unresolved design questions. Use `DECISIONS.md` for accepted design state and `CHANGELOG.md` for completed work.

## Product Direction

COBALT is a procedural 3D isometric RPG where the player moves through local zones generated from a larger world map. The world should feel shaped by factions, populations, ideology, resources, conflicts, agents, and player choices. A campaign covers roughly one in-world year, ending with a historical outcome: the player leaves a mark, and one or more powers meaningfully change the world.

## Working Terms

- **Game view:** The playable experience: exploration, interaction, movement, quests, and world consequences.
- **Editor view:** Development tooling for authoring map modules, components, zone rules, faction profiles, and generation constraints.
- **Dev menu:** Escape-driven runtime overlay for switching between game view and editor view, and later for save/load or debug actions.
- **Editor tool:** A pluggable in-project tool mode selected inside the editor view, such as selection, placement, module inspection, or building generation. This is not a Godot `EditorPlugin` unless the project later needs Godot editor integration.
- **World map:** A 2D strategic layer made of regions or zones.
- **Local map:** The playable 3D area generated from the current zone and nearby context.
- **Zone:** A world-map unit with terrain, environment modules, factions, populations, resources, risks, and generation tags.
- **Environment module:** Static geometry or layout content that can contribute baked navigation collision, such as tree clusters, rock outcrops, roads, utility runs, or building shells.
- **Module library:** Authored reusable environment modules and generator presets saved as resources under `res://data/`.
- **Placement descriptor:** Data that says which module or generator preset appears at a local-map position, with rotation, bounds, seed, and parameters.
- **Generator preset:** A deterministic resource-backed configuration for creating module content, such as a BSP building generator preset.
- **Faction:** A social, political, religious, military, economic, or ideological organization with goals and methods.
- **Population:** A broad biological or cultural group such as humans, mutants, ghouls, isolated vault communities, or future setting-specific groups.
- **Archetype profile:** A weighted set of sliders, usually `0.0` to `1.0`, that influences generation and behavior.
- **Agent:** An actor with allegiance, motivation, goals, and local influence. Agents are future quest seeds.

## Now

- [x] Choose the first editor surface: an in-game development editor mode reached through an Escape dev menu.
- [ ] Define the mode-switching contract between game view and editor view.
- [ ] Define the editor tool contract for selection, placement, generation, save/load, and map reload.
- [ ] Add the first static obstacle/environment resource beyond walls and ground.
- [ ] Keep consolidating map/environment/object language before adding larger systems.

## Next

- [ ] Create a world-map data model with zones, coordinates, seeds, and neighbor relationships.
- [ ] Create a zone component schema for terrain, environment, faction influence, population mix, resources, and danger.
- [ ] Create a module library schema for reusable environment modules, placement descriptors, and generator presets.
- [ ] Build a local-map generation prototype from zone data and authored environment modules.
- [ ] Add basic editor tooling for selecting tools, inspecting resources, placing modules, and reloading maps.
- [ ] Introduce a reusable interaction/examine profile for future props, actors, doors, containers, and harvestables.

## Later

- [ ] Split current `WorldObjectData` into dedicated actor and prop resources.
- [ ] Add faction profiles with goals, governance style, ideology, aesthetics, and preferred structures.
- [ ] Add population profiles with attribute tendencies and content constraints.
- [ ] Add agents with motivations, allegiances, infiltration, exploitation, and conflict hooks.
- [ ] Generate procedural quest seeds from agent goals and faction conflicts.
- [ ] Add campaign time progression across one in-world year.
- [ ] Track world history and ending outcomes.
- [ ] Add combat, inventory, dialogue, saves, and art/animation pipeline.

## Milestones

### 1. Editor and Game View Separation

Status: Planned

Goal: Establish a clear workflow for development tooling without polluting the playable game loop.

Scope:

- Define game view versus editor view responsibilities.
- Add an Escape dev menu that can switch between game view and editor view.
- Add a runtime editor panel with a tool palette, inspector area, and save/load actions.
- Keep gameplay interaction raycasts separate from editor raycasts.
- Let editor tools mutate resource data, then ask `MapLoader` to rebuild and rebake.
- Keep debug/editor controls separate from normal player controls.
- Defer true Godot `EditorPlugin` work until runtime editor workflows prove what needs deeper Godot integration.

Exit criteria:

- A contributor can press Escape, enter editor view, select a tool, and inspect generated map data.
- Gameplay movement/context-menu input is disabled while editor view owns the pointer.
- The playable scene remains clean and player-focused.

### 2. World Map and Zone Model

Status: Planned

Goal: Represent the larger 2D world as connected zones that can seed local maps.

Scope:

- Zone ids, coordinates, neighbors, generation seed, and tags.
- Zone-level resources, faction influence, population mix, and danger level.
- Deterministic regeneration from the same seed and inputs.

Exit criteria:

- A small world map can be generated or authored.
- Selecting a zone exposes all data needed to generate a local map.

### 3. Environment Module Generation

Status: Planned

Goal: Generate playable local maps from authored components instead of one hand-built blockout.

Scope:

- Static environment modules for ground, walls, obstacles, and structure shells.
- Placement descriptors for module position, rotation, bounds, seed, and tool-authored parameters.
- Generator presets for module families such as buildings, roads, utilities, tree clusters, and rock outcrops.
- Rules for selecting modules based on zone tags and archetype profiles.
- Navmesh rebake after generated environment placement.

Exit criteria:

- At least two different local maps can generate from different zone profiles.
- Generated static collision remains compatible with native navigation.

### 4. Archetype Profiles

Status: Proposed

Goal: Use weighted profiles to constrain procedural content without hardcoding one-off cases.

Example axes:

- Order to disorder.
- Altruism to exploitation.
- Isolation to expansion.
- Tradition to technology.
- Diplomacy to aggression.
- Scarcity to abundance.

Exit criteria:

- Zone and faction generation can read profile values.
- Profile values visibly influence generated environments, actors, and props.

### 5. Factions, Populations, and Settlements

Status: Proposed

Goal: Separate social organization from biological or cultural population traits.

Scope:

- Factions define ideology, governance, goals, aesthetics, resources, and preferred structures.
- Populations define actor tendencies, physical/social constraints, and likely roles.
- Settlements or camps combine zone data, faction influence, population mix, and environment modules.

Exit criteria:

- A zone can generate a believable occupied location from faction plus population profiles.
- The same population can appear under different factions with different behavior and presentation.

### 6. Agents and Procedural Quest Seeds

Status: Proposed

Goal: Let motivated actors create conflicts, opportunities, and quest hooks.

Scope:

- Agents have allegiance, motivation, local role, resources, and short-term goals.
- Agents may operate inside other factions or settlements.
- Quest seeds emerge from conflicts such as sabotage, recruitment, exploitation, protection, theft, and diplomacy.

Exit criteria:

- A generated zone can produce at least one meaningful quest premise from its agents and faction state.

### 7. One-Year World History

Status: Proposed

Goal: Make the campaign resolve into a remembered world outcome.

Scope:

- Time progression across roughly one in-world year.
- Faction gains, losses, alliances, collapses, and territorial shifts.
- Player actions influence the final historical state.

Exit criteria:

- The game can summarize which factions or settlements changed and why.

## Feature Backlog

| Area | Idea | Status | Notes |
| --- | --- | --- | --- |
| Tooling | Escape dev menu | Planned | Switch between game view and editor view without starting a separate app. |
| Tooling | Editor tool contract | Planned | Selection, placement, generation, save/load, map reload, and input ownership. |
| Tooling | Editor/dev view | Planned | Inspect zones, generated maps, modules, and profiles. |
| World Map | Zone graph | Planned | 2D region layout with deterministic seeds and neighbors. |
| Environment | Static obstacle resource | Planned | Use for baked navmesh blockers that are not wall segments. |
| Generation | Environment modules | Planned | Authored components selected by zone and faction profiles. |
| Generation | Generator presets | Planned | Resource-backed deterministic presets such as BSP buildings, roads, utilities, tree clusters, and rock outcrops. |
| Generation | Placement descriptors | Planned | Local-map coordinates, rotation, bounds, seed, and parameters for placed modules. |
| Interaction | Shared examine profile | Planned | Reusable by props, actors, doors, harvestables, and containers. |
| World Data | Split actors and props | Deferred | Wait until behavior differs enough from current `WorldObjectData`. |
| Factions | Faction profile resource | Proposed | Goals, ideology, government, aesthetics, resources, and preferred structures. |
| Populations | Population profile resource | Proposed | Attribute tendencies and actor-generation constraints. |
| Agents | Motivation model | Proposed | Allegiance, objective, role, and conflict hooks. |
| Quests | Procedural quest seeds | Proposed | Generated from agents, factions, needs, and conflicts. |
| Campaign | World history log | Proposed | Records important changes and supports ending summaries. |

## Open Questions

- When should the runtime editor mode graduate into a separate dev scene or Godot `EditorPlugin`, if ever?
- What term should the project use for broad groups like humans, mutants, ghouls, and vault communities: population, lineage, people, species, culture, or something else?
- What are the final archetype axes? Avoid borrowing tabletop alignment directly if custom sliders communicate the setting better.
- How large is a world-map zone, and how much local map should generate at once?
- Should local maps stream continuously between zones or load one generated zone at a time first?
- Are world-map regions best represented as a coordinate graph, authored polygons, generated noise regions, or a hybrid?
- What is the smallest useful first editor tool: select/inspect, place module, or generate building?
- Which first interactable should prove the interaction model: door, container, harvestable, or examine-only prop?
- What is the minimum viable faction simulation before quests are worthwhile?
- What does it mean for a faction or population to "win" the year?

## Notes

- Reference inspirations should stay conceptual. Do not copy named factions, setting-specific groups, or lore directly into COBALT.
- Keep procedural systems deterministic where possible: the same seed plus the same authored inputs should produce the same result.
- Prefer small resources and stateless resolvers over broad manager classes as these systems grow.
- Any cellular, quadrant, brush, or coordinate language for generation is about authoring and placement only. Do not turn it into custom grid movement or pathfinding.
