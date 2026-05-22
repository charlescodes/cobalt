This is a fantastic and highly structured progression for **COBALT**. Stepping back to build a robust, dedicated **Debug/Map-Generation Workspace** is exactly how you mature a data-driven engine. Because your architecture strictly dictates that gameplay logic must live in stateless processors and data lives in `Resource` scripts, we can build this entire tool without polluting your core game nodes.

Godot 4.4 has exceptional built-in layout controls (`HSlider`, `SpinBox`, `OptionButton`, `Button`) perfect for creating the control panels you are describing.

To satisfy your architecture, we will break this feature down into three distinct layers:

1. **Data Structures:** New `BspModuleData` to hold parameters and tracking configurations.
2. **Stateless Processor:** A deterministic `BspRoomProcessor` that executes the space partitioning and handles the dynamic CRUD operations (splitting, merging, carving door gaps).
3. **Debug UI & Interaction Controller:** A separate scene (`res://scenes/debug/bsp_workspace.tscn`) featuring a custom UI panel and mouse-raycast interaction for clicking rooms and drawing/deleting 1-meter doors.

---

## 1. Updated Project File Map

To keep your `PROJECT_STRUCTURE.md` clean, we are going to introduce these new files under dedicated debug and tool folders:

```text
res://src/debug/bsp_module_data.gd          # Holds building dimensions, tree nodes, and dynamic door lists.
res://src/debug/bsp_room_processor.gd       # Stateless BSP generation, split calculations, and door culling.
res://src/debug/bsp_workspace_controller.gd # Raycasts for hover, right-click add door, left-click remove door.
res://scenes/debug/bsp_workspace.tscn       # Main debug workspace root with 3D viewport, ground, and UI sliders.

```

---

## 2. The Data Layer (`bsp_module_data.gd`)

This custom resource tracks the structural data of your building module. It represents the rooms as a tree structure resulting from the binary space partitioning, allowing us to dynamically track individual leaf nodes (rooms) for selection and hover queries.

```gdscript
# res://src/debug/bsp_module_data.gd
class_name BspModuleData
extends Resource

## Structural representation of a partitioned room leaf
class BspNode:
	var id: String
	var bounds: Rect2 # X and Z bounds using Rect2 (Position, Size)
	var left_child: BspNode = null
	var right_child: BspNode = null
	var is_leaf: bool = true
	var door_positions: Array[Vector3] = [] # Center points of 1-meter door gaps

@export var building_size: Vector2 = Vector2(20.0, 18.0) # X and Z dimensions
@export var min_room_size: float = 4.0
@export var max_split_depth: int = 3

# Non-serialized runtime tracking tree root
var root_node: BspNode
# Flattened array of active rooms (leaf nodes) for quick hover/click calculation
var active_rooms: Array[BspNode] = []

```

---

## 3. The Stateless Processor (`bsp_room_processor.gd`)

Following your project law, this class remains completely isolated and stateless. It accepts the raw configuration parameters, performs the geometric splits recursively, handles a deterministic door setup connecting adjacent rooms, and translates those bounds into your core `WallSegmentData` structures.

```gdscript
# res://src/debug/bsp_room_processor.gd
class_name BspRoomProcessor
extends RefCounted

## Generates the initial BSP tree structure based on module parameters
static func generate_bsp_tree(data: BspModuleData) -> BspModuleData:
	data.active_rooms.clear()
	
	var root = BspModuleData.BspNode.new()
	root.id = "root"
	root.bounds = Rect2(Vector2.ZERO, data.building_size)
	
	_split_node(root, 0, data)
	data.root_node = root
	_gather_leaves(root, data.active_rooms)
	
	# Generate default door per room to guarantee connectivity
	_generate_default_connectivity(data)
	
	return data

static func _split_node(node: BspModuleData.BspNode, current_depth: int, data: BspModuleData) -> void:
	if current_depth >= data.max_split_depth:
		return

	var b: Rect2 = node.bounds
	var split_horizontal: bool = randf() > 0.5
	
	# Force split direction if dimensions are heavily lopsided
	if b.size.x > b.size.y * 1.5:
		split_horizontal = false
	elif b.size.y > b.size.x * 1.5:
		split_horizontal = true

	var max_split = (b.size.y if split_horizontal else b.size.x) - data.min_room_size
	if max_split <= data.min_room_size:
		return # Room cannot be split any further within sizing rules

	node.is_leaf = false
	var split_point: float = randf_range(data.min_room_size, max_split)

	var left = BspModuleData.BspNode.new()
	var right = BspModuleData.BspNode.new()
	
	if split_horizontal:
		left.bounds = Rect2(b.position, Vector2(b.size.x, split_point))
		right.bounds = Rect2(Vector2(b.position.x, b.position.y + split_point), Vector2(b.size.x, b.size.y - split_point))
	else:
		left.bounds = Rect2(b.position, Vector2(split_point, b.size.y))
		right.bounds = Rect2(Vector2(b.position.x + split_point, b.position.y), Vector2(b.size.x - split_point, b.size.y))

	left.id = node.id + "_L"
	right.id = node.id + "_R"
	
	node.left_child = left
	node.right_child = right
	
	_split_node(left, current_depth + 1, data)
	_split_node(right, current_depth + 1, data)

static func _gather_leaves(node: BspModuleData.BspNode, leaves: Array[BspModuleData.BspNode]) -> void:
	if node == null:
		return
	if node.is_leaf:
		leaves.append(node)
		return
	_gather_leaves(node.left_child, leaves)
	_gather_leaves(node.right_child, leaves)

## Guarantees each room has at least one structural connection path
static func _generate_default_connectivity(data: BspModuleData) -> void:
	# Iterate rooms and find shared wall boundaries to snap a 1m door position
	for i in range(data.active_rooms.size() - 1):
		var r1 = data.active_rooms[i]
		var r2 = data.active_rooms[i+1]
		var door_pos = _find_shared_wall_center(r1.bounds, r2.bounds)
		if door_pos != Vector3.ZERO:
			r1.door_positions.append(door_pos)
			r2.door_positions.append(door_pos)

## Converts the geometric rooms and custom dynamic doors into Core WallSegmentData arrays
static func compile_to_walls(data: BspModuleData) -> Array[WallSegmentData]:
	var segments: Array[WallSegmentData] = []
	var raw_walls: Array[Dictionary] = []

	# Outer perimeter walls
	var b = Rect2(Vector2.ZERO, data.building_size)
	raw_walls.append({"start": Vector3(b.position.x, 0, b.position.y), "end": Vector3(b.position.x + b.size.x, 0, b.position.y)})
	raw_walls.append({"start": Vector3(b.position.x + b.size.x, 0, b.position.y), "end": Vector3(b.position.x + b.size.x, 0, b.position.y + b.size.y)})
	raw_walls.append({"start": Vector3(b.position.x + b.size.x, 0, b.position.y + b.size.y), "end": Vector3(b.position.x, 0, b.position.y + b.size.y)})
	raw_walls.append({"start": Vector3(b.position.x, 0, b.position.y + b.size.y), "end": Vector3(b.position.x, 0, b.position.y)})

	# Internal partition walls extracted from intermediate tree non-leaves
	_extract_internal_walls(data.root_node, raw_walls)

	# For each raw wall segment, calculate door punctures and generate final segments
	for rw in raw_walls:
		var start: Vector3 = rw.start
		var end: Vector3 = rw.end
		
		# Gather all custom doors that fall directly along this specific segment line
		var doors_on_wall: Array[Vector3] = []
		for room in data.active_rooms:
			for door in room.door_positions:
				if _is_point_on_segment(door, start, end) and not doors_on_wall.has(door):
					doors_on_wall.append(door)
		
		if doors_on_wall.is_empty():
			segments.append(_create_wall_resource(start, end))
		else:
			# Sort doors sequentially along the line path from start to end to carve safely
			doors_on_wall.sort_custom(func(a, b_pos): return start.distance_to(a) < start.distance_to(b_pos))
			var current_start = start
			
			for door in doors_on_wall:
				var direction = (end - start).normalized()
				var door_start = door - (direction * 0.5) # 1-meter total width carve out
				var door_end = door + (direction * 0.5)
				
				# Append sub-segment before the door gap
				if current_start.distance_to(door_start) > 0.1:
					segments.append(_create_wall_resource(current_start, door_start))
				
				current_start = door_end
			
			# Append remaining tail wall segment
			if current_start.distance_to(end) > 0.1:
				segments.append(_create_wall_resource(current_start, end))

	return segments

static func _extract_internal_walls(node: BspModuleData.BspNode, walls: Array[Dictionary]) -> void:
	if node == null or node.is_leaf:
		return
		
	var b = node.left_child.bounds
	if node.bounds.size.x == node.left_child.bounds.size.x: # Split was horizontal
		walls.append({
			"start": Vector3(b.position.x, 0, b.position.y + b.size.y),
			"end": Vector3(b.position.x + b.size.x, 0, b.position.y + b.size.y)
		})
	else: # Split was vertical
		walls.append({
			"start": Vector3(b.position.x + b.size.x, 0, b.position.y),
			"end": Vector3(b.position.x + b.size.x, 0, b.position.y + b.size.y)
		})
		
	_extract_internal_walls(node.left_child, walls)
	_extract_internal_walls(node.right_child, walls)

static func _create_wall_resource(start: Vector3, end: Vector3) -> WallSegmentData:
	var wall = WallSegmentData.new()
	wall.start_position = start
	wall.end_position = end
	wall.height = 3.0
	wall.thickness = 0.2
	wall.color = Color(0.4, 0.4, 0.45)
	return wall

static func _find_shared_wall_center(r1: Rect2, r2: Rect2) -> Vector3:
	var intersection = r1.intersection(r2)
	# Check if they share an edge line
	if intersection.size.x <= 0.05 and intersection.size.y > 1.0:
		return Vector3(r1.intersection(r2).position.x, 0, r1.intersection(r2).position.y + (r1.intersection(r2).size.y / 2.0))
	if intersection.size.y <= 0.05 and intersection.size.x > 1.0:
		return Vector3(r1.intersection(r2).position.x + (r1.intersection(r2).size.x / 2.0), 0, r1.intersection(r2).position.y)
	return Vector3.ZERO

static func _is_point_on_segment(p: Vector3, start: Vector3, end: Vector3) -> bool:
	var d_total = start.distance_to(end)
	var d_split = start.distance_to(p) + p.distance_to(end)
	return abs(d_total - d_split) < 0.05

```

---

## 4. The Workspace Workspace Scene & UI Composition

Create a new standalone debug scene at `res://scenes/debug/bsp_workspace.tscn`. The UI panels map directly to Godot's built-in control elements.

### Scene Hierarchy

```text
BspWorkspace (Node3D)  <-- Attached to bsp_workspace_controller.gd
├── DirectionalLight3D (SunLight)
├── Camera3D (Top-down oblique projection)
├── MeshInstance3D (Ground Plane Mesh)
├── StaticBody3D (Ground Collider for mouse Raycasts)
│   └── CollisionShape3D (BoxShape3D)
├── Node3D (GeneratedWallsContainer)
├── Node3D (GeneratedDoorsContainer)
└── CanvasLayer (DebugUI)
    └── Control
        └── PanelContainer (RightSidebarControl)
            └── VBoxContainer
                ├── Label ("BUILDING PARAMETERS")
                ├── Label ("Width (X)")
                ├── HSlider (WidthSlider - Range 10 to 50)
                ├── Label ("Depth (Z)")
                ├── HSlider (DepthSlider - Range 10 to 50)
                ├── Label ("Min Room Dimension")
                ├── SpinBox (MinRoomSizeBox)
                ├── Label ("Max Split Hierarchy Depth")
                ├── HSlider (MaxDepthSlider - Range 1 to 5)
                ├── Button (GenerateButton - "⚡ GERCHUNK!")
                └── Label (HelpTextPanel - "Hover room: Highlights\nRight-Click Wall: Add 1m Door\nLeft-Click Door: Delete Door")

```

---

## 5. The Workspace Coordinator (`bsp_workspace_controller.gd`)

This orchestrator handles user input loops, updates the debug sliders, monitors room hovering, and coordinates dynamic mouse-click adjustments.

```gdscript
# res://src/debug/bsp_workspace_controller.gd
extends Node3D

@onready var width_slider: HSlider = $CanvasLayer/Control/PanelContainer/VBoxContainer/WidthSlider
@onready var depth_slider: HSlider = $CanvasLayer/Control/PanelContainer/VBoxContainer/DepthSlider
@onready var min_room_box: SpinBox = $CanvasLayer/Control/PanelContainer/VBoxContainer/MinRoomSizeBox
@onready var max_depth_slider: HSlider = $CanvasLayer/Control/PanelContainer/VBoxContainer/MaxDepthSlider
@onready var generate_button: Button = $CanvasLayer/Control/PanelContainer/VBoxContainer/GenerateButton
@onready var walls_container: Node3D = $GeneratedWallsContainer
@onready var doors_container: Node3D = $GeneratedDoorsContainer
@onready var camera: Camera3D = $Camera3D

var bsp_data: BspModuleData
var hovered_room: BspModuleData.BspNode = null

void _ready() -> void:
	bsp_data = BspModuleData.new()
	generate_button.pressed.connect(_on_gerchunk_pressed)
	_sync_parameters_from_ui()
	_on_gerchunk_pressed()

void _process(_delta: float) -> void:
	_handle_mouse_hover()

void _sync_parameters_from_ui() -> void:
	bsp_data.building_size = Vector2(width_slider.value, depth_slider.value)
	bsp_data.min_room_size = min_room_box.value
	bsp_data.max_split_depth = int(max_depth_slider.value)

void _on_gerchunk_pressed() -> void:
	# Make the classic "gerchunk" feedback sound!
	print("[BSP WORKSPACE] *GERCHUNK!* Generating layout...")
	_sync_parameters_from_ui()
	bsp_data = BspRoomProcessor.generate_bsp_tree(bsp_data)
	_rebuild_3d_view()

void _rebuild_3d_view() -> void:
	# Clear old primitive representations
	for child in walls_container.get_children():
		child.queue_free()
	for child in doors_container.get_children():
		child.queue_free()
		
	# Compile spatial resources through standard pipelines
	var core_wall_resources = BspRoomProcessor.compile_to_walls(bsp_data)
	
	for wall_data in core_wall_resources:
		# Mirror Core MapBuilder instantiation logic safely
		var center = (wall_data.start_position + wall_data.end_position) / 2.0
		var length = wall_data.start_position.distance_to(wall_data.end_position)
		
		var wall_mesh = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(length, wall_data.height, wall_data.thickness)
		wall_mesh.mesh = box_mesh
		
		# Color coding matching architecture specification
		var material = StandardMaterial3D.new()
		material.albedo_color = wall_data.color
		wall_mesh.material_override = material
		
		wall_mesh.position = center + Vector3(0, wall_data.height / 2.0, 0)
		# Face down segment orientation line
		var direction = (wall_data.end_position - wall_data.start_position).normalized()
		wall_mesh.look_at(wall_mesh.position + direction, Vector3.UP)
		
		walls_container.add_child(wall_mesh)
		
	# Spawn visual representations of doors to allow selection tracing
	for room in bsp_data.active_rooms:
		for door_pos in room.door_positions:
			_spawn_door_preview_node(door_pos)

void _spawn_door_preview_node(pos: Vector3) -> void:
	# Check duplicates
	for current_door in doors_container.get_children():
		if current_door.position.distance_to(pos) < 0.2:
			return
			
	var door_indicator = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 0.2 # Disc representation laying flat
	door_indicator.mesh = cylinder
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.3) # Bright distinct green markers
	door_indicator.material_override = mat
	door_indicator.position = pos + Vector3(0, 0.1, 0)
	
	doors_container.add_child(door_indicator)

void _handle_mouse_hover() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	# Calculate ground intercept plane (Y=0 standard ground floor)
	if ray_direction.y == 0: return
	var t = -ray_origin.y / ray_direction.y
	if t < 0: return
	var hit_point = ray_origin + ray_direction * t
	
	# Find room match matching continuous boundary vectors
	var current_hover: BspModuleData.BspNode = null
	for room in bsp_data.active_rooms:
		if room.bounds.has_point(Vector2(hit_point.x, hit_point.z)):
			current_hover = room
			break
			
	if current_hover != hovered_room:
		hovered_room = current_hover
		if hovered_room:
			# Debug trace to console window to check sizes dynamically
			print("Hovering Room: ", hovered_room.id, " | Dimensions: ", hovered_room.bounds.size)

void _unhandled_input(event: InputEvent) -> void:
	if not hovered_room: return
	
	var mouse_event = event as InputEventMouseButton
	if mouse_event and mouse_event.pressed:
		var mouse_pos = get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_direction = camera.project_ray_normal(mouse_pos)
		var t = -ray_origin.y / ray_direction.y
		var hit_point = ray_origin + ray_direction * t
		
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			# Right Click: Dynamic CRUD Insertion of door gap on the closest boundary wall point
			var door_snap = _calculate_wall_snap_point(hit_point, hovered_room)
			if door_snap != Vector3.ZERO:
				hovered_room.door_positions.append(door_snap)
				_rebuild_3d_view()
				
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Left Click: Dynamic CRUD Deletion of a door if selecting a green handle directly
			for room in bsp_data.active_rooms:
				for door in room.door_positions:
					if door.distance_to(hit_point) < 1.2: # Match range bubble
						room.door_positions.erase(door)
						_rebuild_3d_view()
						return

void _calculate_wall_snap_point(click_pt: Vector3, room: BspModuleData.BspNode) -> Vector3:
	var b = room.bounds
	var candidates = [
		Vector3(click_pt.x, 0, b.position.y),              # Top wall
		Vector3(click_pt.x, 0, b.position.y + b.size.y),   # Bottom wall
		Vector3(b.position.x, 0, click_pt.z),              # Left wall
		Vector3(b.position.x + b.size.x, 0, click_pt.z)    # Right wall
	]
	
	var closest_pt = Vector3.ZERO
	var min_dist = 99999.0
	for c in candidates:
		var d = c.distance_to(click_pt)
		if d < min_dist:
			min_dist = d
			closest_pt = c
	return closest_pt

```

---

## 6. Verification Steps

Add a headless execution pattern into your testing harness (`res://tests/suites/native_navigation_suite.gd` or a new standalone suite) to confirm parsing stability across variable inputs:

```gdscript
# Example logic block to insert into tests/suites/map_builder_suite.gd
func test_bsp_compilation_safety() -> void:
	var test_data = BspModuleData.new()
	test_data.building_size = Vector2(30.0, 30.0)
	test_data.min_room_size = 2.0
	test_data.max_split_depth = 4
	
	var processed = BspRoomProcessor.generate_bsp_tree(test_data)
	var generated_walls = BspRoomProcessor.compile_to_walls(processed)
	
	assert_true(generated_walls.size() > 4, "BSP compilation should yield partitioned internal wall fragments successfully.")

```

Run your global execution check command via your bash script pipeline to verify the build remains stable:

```bash
./scripts/check.sh

```