class_name WorldGeologyData
extends Resource

const COAST_NORTH := "north"
const COAST_SOUTH := "south"
const COAST_EAST := "east"
const COAST_WEST := "west"

@export var seed_text: String = "cobalt"
@export var size_m: Vector2 = Vector2(500000.0, 500000.0)
@export var map_scale_km: float = 500.0
@export var coast_enabled: bool = false
@export_enum("north", "south", "east", "west") var coast_edge: String = COAST_WEST
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.55
@export_range(0.0, 1.0, 0.01) var sea_level: float = 0.42
@export_range(0.0, 1.0, 0.01) var global_temperature: float = 0.55
@export_range(0.0, 1.0, 0.01) var base_rainfall: float = 0.55
@export_range(0.0, 360.0, 1.0, "degrees") var wind_direction_degrees: float = 270.0
@export_range(0.0, 1.0, 0.01) var erosion_strength: float = 0.25
@export_range(0.0, 1.0, 0.01) var vegetation_spread: float = 0.55
@export_range(0.0, 1.0, 0.01) var tree_canopy_density: float = 0.45
@export_range(0.0, 360.0, 1.0, "degrees") var tectonic_alignment_degrees: float = 25.0
@export_range(0.0, 1.0, 0.01) var toxicity: float = 0.12

func _init(
	p_seed_text: String = "cobalt",
	p_size_m: Vector2 = Vector2(500000.0, 500000.0)
) -> void:
	seed_text = p_seed_text
	size_m = p_size_m

func to_parameters() -> Dictionary:
	return {
		"seed_text": seed_text,
		"size_m": size_m,
		"map_scale_km": map_scale_km,
		"coast_enabled": coast_enabled,
		"coast_edge": coast_edge,
		"roughness": roughness,
		"sea_level": sea_level,
		"global_temperature": global_temperature,
		"base_rainfall": base_rainfall,
		"wind_direction_degrees": wind_direction_degrees,
		"erosion_strength": erosion_strength,
		"vegetation_spread": vegetation_spread,
		"tree_canopy_density": tree_canopy_density,
		"tectonic_alignment_degrees": tectonic_alignment_degrees,
		"toxicity": toxicity,
	}

func apply_parameters(parameters: Dictionary) -> void:
	seed_text = str(parameters.get("seed_text", seed_text))
	size_m = _clean_size(parameters.get("size_m", size_m))
	map_scale_km = clampf(float(parameters.get("map_scale_km", map_scale_km)), 500.0, 1000.0)
	coast_enabled = bool(parameters.get("coast_enabled", coast_enabled))
	coast_edge = _clean_coast_edge(str(parameters.get("coast_edge", coast_edge)))
	roughness = clampf(float(parameters.get("roughness", roughness)), 0.0, 1.0)
	sea_level = clampf(float(parameters.get("sea_level", sea_level)), 0.0, 1.0)
	global_temperature = clampf(float(parameters.get("global_temperature", global_temperature)), 0.0, 1.0)
	base_rainfall = clampf(float(parameters.get("base_rainfall", base_rainfall)), 0.0, 1.0)
	wind_direction_degrees = wrapf(float(parameters.get("wind_direction_degrees", wind_direction_degrees)), 0.0, 360.0)
	erosion_strength = clampf(float(parameters.get("erosion_strength", erosion_strength)), 0.0, 1.0)
	vegetation_spread = clampf(float(parameters.get("vegetation_spread", vegetation_spread)), 0.0, 1.0)
	tree_canopy_density = clampf(float(parameters.get("tree_canopy_density", tree_canopy_density)), 0.0, 1.0)
	tectonic_alignment_degrees = wrapf(float(parameters.get("tectonic_alignment_degrees", tectonic_alignment_degrees)), 0.0, 360.0)
	toxicity = clampf(float(parameters.get("toxicity", toxicity)), 0.0, 1.0)

func _clean_size(value: Variant) -> Vector2:
	if not (value is Vector2):
		return size_m

	var next_size: Vector2 = value
	return Vector2(
		clampf(next_size.x, 250000.0, 1000000.0),
		clampf(next_size.y, 250000.0, 1000000.0)
	)

func _clean_coast_edge(value: String) -> String:
	if value == COAST_NORTH or value == COAST_SOUTH or value == COAST_EAST or value == COAST_WEST:
		return value

	return COAST_WEST
