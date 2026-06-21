# COBALT Roadmap

Last updated: 2026-06-21

Purpose: the authoritative source for product direction, active priorities, deferred scope, and unresolved questions. Current implementation belongs in `ARCHITECTURE.md`; completed outcomes belong in `CHANGELOG.md`.

## Product Direction

COBALT is a procedural 3D isometric RPG where players explore local zones generated from a larger world. Sparse terrain connects towns, communities, roads, outposts, hazards, and other points of interest. Factions, populations, ideology, resources, conflicts, agents, and player choices shape the world. A campaign covers roughly one in-world year and ends with a historical outcome describing how the player and major powers changed it.

## Working Terms

- **Game mode:** the playable experience: movement, exploration, interaction, quests, and world consequences.
- **Gameplay control mode:** a control scheme nested inside Game mode rather than a peer of the local or world editors.
- **Real-time control mode:** the implemented gameplay control scheme with active-character cycling, player-follow camera, and direct held-mouse movement.
- **Turn-based control mode:** an implemented selectable placeholder that disables real-time controls; explicit actor selection, actions, targeting, and turn progression remain future work.
- **Local editor mode:** runtime development tooling for authoring playable local maps and reusable content.
- **World editor mode:** runtime macro tooling for world terrain, zones, routes, settlements, and points of interest.
- **Editor tool:** a pluggable in-project tool mode. Reserve "plugin" for future Godot `EditorPlugin` or external extension work.
- **World map:** the strategic world layer from which local content is selected or generated.
- **Local map:** a playable 3D area generated or authored from world context.
- **Zone:** a world unit with terrain, environment, factions, populations, resources, risks, and generation tags.
- **Map component:** a reusable authored or generated collection of local-map data, such as a building, road section, utility run, environmental cluster, encounter, or city-block piece.
- **Environment module:** static geometry or layout content that can contribute baked navigation collision.
- **Module library:** reusable authored modules and generator presets saved as resources.
- **Placement descriptor:** module or preset selection plus local position, rotation, bounds, seed, and parameters.
- **Generator preset:** deterministic resource-backed configuration for a generator family.
- **Socket:** a semantic attachment point for doors, furniture, items, actors, encounters, roads, or buildings.
- **Point of interest:** a world feature that can seed a local map, such as a settlement, clinic, school, utility site, ruin, camp, route junction, or hazard.
- **Faction:** a social, political, religious, military, economic, or ideological organization with goals and methods.
- **Population:** a broad biological or cultural group independent of faction allegiance.
- **Archetype profile:** weighted axes that influence generation and behavior.
- **Agent:** a motivated actor with allegiance, goals, resources, and local influence; agents can seed future quests.

## Now

- Add the first static obstacle/environment resource beyond walls and ground.
- Consolidate map, environment, object, module, and component terminology before larger generation systems depend on it.
- Exercise the implemented local and world editor workflows before broadening their tool contracts.

## Next

### World Zones

- Define zone identifiers, coordinates or geometry, seeds, neighbor relationships, and tags.
- Define zone terrain, environment, faction influence, population mix, resources, and danger.
- Ensure a selected zone contains enough deterministic input to generate a local map.

### Modules and Local Generation

- Define resource schemas for module libraries, placement descriptors, and generator presets.
- Generate at least two distinct playable local maps from different zone profiles and authored modules.
- Preserve native navigation compatibility and rebake after static environment placement.
- Add editor support for inspecting, placing, saving, and reloading reusable modules.

### Interaction Model

- Introduce reusable interaction and examine profiles for actors, props, doors, containers, and harvestables.
- Use the first richer interactable to validate capability composition before splitting broad object data.

## Later

### Procedural Structures and Sockets

- Save generated buildings as reusable components instead of only flattening them into `MapData`.
- Add room metadata plus door, furniture, item, actor, encounter, road, and building-connection sockets.
- Compose buildings, environment clusters, roads, utilities, prop sets, and spawn sets into settlement or city-block layouts.

### World-Scale Editing and Points of Interest

- Author or generate large sparse regions containing routes, empty terrain, towns, communities, hazards, and points of interest.
- Decide which areas need bespoke local maps and which remain procedural travel space.
- Place reusable local components into settlement, route, and point-of-interest contexts.

### Archetype Profiles

- Define setting-specific weighted axes such as order/disorder, altruism/exploitation, isolation/expansion, tradition/technology, diplomacy/aggression, and scarcity/abundance.
- Make zone and faction profiles visibly influence generated environments, actors, and props.

### Factions, Populations, and Settlements

- Model faction ideology, governance, goals, aesthetics, resources, methods, and preferred structures.
- Model population tendencies and content constraints independently from faction allegiance.
- Combine zones, faction influence, population mix, points of interest, and local components into believable occupied locations.

### Agents and Quest Seeds

- Give agents allegiance, motivation, local roles, resources, and short-term goals.
- Generate quest seeds from conflicts such as sabotage, recruitment, exploitation, protection, theft, and diplomacy.
- Allow agents to operate inside, between, or against factions and settlements.

### One-Year World History

- Progress time across roughly one in-world year.
- Track faction gains, losses, alliances, collapses, and territorial shifts.
- Record important player-caused changes and summarize them in campaign outcomes.

### Broader Gameplay and Production

- Add the turn-based gameplay control mode after the real-time control boundary and combat action model are proven.
- Split `WorldObjectData` into actor and prop resources when their behavior requires distinct models.
- Add combat, inventory, dialogue, quests, party management, saves, and AI behavior incrementally.
- Add richer movement presentation, invalid-destination feedback, art, models, and animation when core gameplay requires them.
- Design zones, streaming, multi-region navigation, and large-map loading only after the first zone-to-local-map workflow is proven.

## Open Questions

- When, if ever, should runtime editor tooling graduate into a separate development scene or Godot `EditorPlugin`?
- What final term should describe broad biological or cultural groups: population, lineage, people, species, culture, or another term?
- What archetype axes best communicate COBALT's setting without copying tabletop alignment?
- How large is a world zone, and how much local terrain should generate at once?
- Should local maps initially load one zone at a time or stream continuously between zones?
- Should world regions use coordinate graphs, authored polygons, generated noise regions, or a hybrid?
- What final term should represent reusable local pieces: map component, module, fragment, prefab, scene, or kit?
- Should composed maps retain child component references, flatten into `MapData`, or support both?
- Which socket types are required for the first reusable component?
- How much world terrain should be authored around points of interest versus generated as sparse travel space?
- Which first richer interactable should prove the capability model: door, container, harvestable, or examine-only prop?
- What is the minimum useful faction simulation before procedural quests become worthwhile?
- What does it mean for a faction, population, settlement, or player to "win" the year?

## Planning Constraints

- Keep reference inspirations conceptual and setting-neutral; do not copy named factions, groups, or lore.
- Keep procedural systems deterministic where possible.
- Prefer small resources and stateless processors over broad managers.
- Generation may use cellular, quadrant, brush, coordinate, or noise concepts; movement must remain free-form and Godot-native.
- Keep first-pass work narrow and validate each layer before expanding into generalized systems.
