class_name WorldGeologyGenerator
extends RefCounted

const WorldGeologyDataScript := preload("res://src/environment/world_geology_data.gd")

const DEFAULT_GRID_RESOLUTION: int = 65
const MAX_ELEVATION_M: float = 9000.0
const OROGRAPHIC_LIFT_SCALE: float = 3.0

static func generate(
	geology_data: WorldGeologyDataScript,
	grid_resolution: int = DEFAULT_GRID_RESOLUTION
) -> Dictionary:
	if geology_data == null:
		return {}

	var resolution := clampi(grid_resolution, 9, 129)
	var size_m := Vector2(
		maxf(geology_data.size_m.x, 1.0),
		maxf(geology_data.size_m.y, 1.0)
	)
	var seed := _seed_from_text(geology_data.seed_text)
	var base_noise := _new_noise(seed, 0.85 / maxf(geology_data.map_scale_km, 1.0), FastNoiseLite.FRACTAL_FBM)
	var ridge_noise := _new_noise(seed + 1009, 2.15 / maxf(geology_data.map_scale_km, 1.0), FastNoiseLite.FRACTAL_RIDGED)
	var moisture_noise := _new_noise(seed + 2039, 1.45 / maxf(geology_data.map_scale_km, 1.0), FastNoiseLite.FRACTAL_FBM)
	var toxicity_noise := _new_noise(seed + 4093, 2.75 / maxf(geology_data.map_scale_km, 1.0), FastNoiseLite.FRACTAL_FBM)

	var elevation := _build_elevation(
		resolution,
		size_m,
		base_noise,
		ridge_noise,
		geology_data
	)
	elevation = _erode_elevation(elevation, resolution, geology_data.erosion_strength)

	var moisture := _build_moisture(resolution, size_m, elevation, moisture_noise, geology_data)
	var temperature := _build_temperature(resolution, elevation, geology_data)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	vertices.resize(resolution * resolution)
	colors.resize(resolution * resolution)

	for z in range(resolution):
		for x in range(resolution):
			var index := _index(x, z, resolution)
			var normalized_x := float(x) / float(resolution - 1)
			var normalized_z := float(z) / float(resolution - 1)
			var centered_x := (normalized_x - 0.5) * size_m.x
			var centered_z := (normalized_z - 0.5) * size_m.y
			var elevation_value := elevation[index]
			var is_water := elevation_value <= geology_data.sea_level
			var height_m := 0.0
			if not is_water:
				height_m = pow(
					clampf((elevation_value - geology_data.sea_level) / maxf(1.0 - geology_data.sea_level, 0.001), 0.0, 1.0),
					1.35
				) * MAX_ELEVATION_M

			vertices[index] = Vector3(centered_x, height_m, centered_z)
			colors[index] = _biome_color(
				elevation_value,
				moisture[index],
				temperature[index],
				_sample_noise_01(toxicity_noise, normalized_x * geology_data.map_scale_km, normalized_z * geology_data.map_scale_km),
				geology_data
			)

	for z in range(resolution - 1):
		for x in range(resolution - 1):
			var a := _index(x, z, resolution)
			var b := _index(x + 1, z, resolution)
			var c := _index(x, z + 1, resolution)
			var d := _index(x + 1, z + 1, resolution)
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	return {
		"resolution": resolution,
		"size_m": size_m,
		"vertices": vertices,
		"colors": colors,
		"indices": indices,
		"elevation": elevation,
		"moisture": moisture,
		"temperature": temperature,
	}

static func _build_elevation(
	resolution: int,
	size_m: Vector2,
	base_noise: FastNoiseLite,
	ridge_noise: FastNoiseLite,
	geology_data: WorldGeologyDataScript
) -> PackedFloat32Array:
	var elevation := PackedFloat32Array()
	elevation.resize(resolution * resolution)
	var alignment := deg_to_rad(geology_data.tectonic_alignment_degrees)
	var aligned_basis := Basis(Vector3.UP, alignment)

	for z in range(resolution):
		for x in range(resolution):
			var normalized_x := float(x) / float(resolution - 1)
			var normalized_z := float(z) / float(resolution - 1)
			var km_x := (normalized_x - 0.5) * size_m.x * 0.001
			var km_z := (normalized_z - 0.5) * size_m.y * 0.001
			var aligned := aligned_basis * Vector3(km_x, 0.0, km_z)
			var base := _sample_noise_01(base_noise, km_x, km_z)
			var ridge := _sample_noise_01(ridge_noise, aligned.x * 0.7, aligned.z * 1.8)
			var value := (base * 0.54) + (ridge * geology_data.roughness * 0.46)
			if geology_data.coast_enabled:
				value -= _coast_influence(normalized_x, normalized_z, geology_data.coast_edge) * 0.48
			elevation[_index(x, z, resolution)] = clampf(value, 0.0, 1.0)

	return elevation

static func _erode_elevation(
	elevation: PackedFloat32Array,
	resolution: int,
	erosion_strength: float
) -> PackedFloat32Array:
	var iterations := int(roundf(clampf(erosion_strength, 0.0, 1.0) * 8.0))
	var current := elevation
	for _iteration in range(iterations):
		var next := current.duplicate()
		for z in range(1, resolution - 1):
			for x in range(1, resolution - 1):
				var index := _index(x, z, resolution)
				var neighbor_average := (
					current[_index(x - 1, z, resolution)]
					+ current[_index(x + 1, z, resolution)]
					+ current[_index(x, z - 1, resolution)]
					+ current[_index(x, z + 1, resolution)]
				) * 0.25
				var slope := absf(current[index] - neighbor_average)
				next[index] = lerpf(current[index], neighbor_average, clampf(erosion_strength * (0.2 + slope), 0.0, 0.65))
		current = next

	return current

static func _build_moisture(
	resolution: int,
	size_m: Vector2,
	elevation: PackedFloat32Array,
	moisture_noise: FastNoiseLite,
	geology_data: WorldGeologyDataScript
) -> PackedFloat32Array:
	var moisture := PackedFloat32Array()
	moisture.resize(resolution * resolution)
	var wind_rad := deg_to_rad(geology_data.wind_direction_degrees)
	var wind := Vector2(sin(wind_rad), -cos(wind_rad)).normalized()
	var cell_x_m := size_m.x / float(resolution - 1)
	var cell_z_m := size_m.y / float(resolution - 1)

	for z in range(resolution):
		for x in range(resolution):
			var normalized_x := float(x) / float(resolution - 1)
			var normalized_z := float(z) / float(resolution - 1)
			var x_prev: int = clampi(x - 1, 0, resolution - 1)
			var x_next: int = clampi(x + 1, 0, resolution - 1)
			var z_prev: int = clampi(z - 1, 0, resolution - 1)
			var z_next: int = clampi(z + 1, 0, resolution - 1)
			var gradient := Vector2(
				(elevation[_index(x_next, z, resolution)] - elevation[_index(x_prev, z, resolution)]) / maxf(cell_x_m, 1.0),
				(elevation[_index(x, z_next, resolution)] - elevation[_index(x, z_prev, resolution)]) / maxf(cell_z_m, 1.0)
			) * minf(size_m.x, size_m.y)
			var lift := wind.dot(gradient)
			var base := _sample_noise_01(
				moisture_noise,
				(normalized_x - 0.5) * geology_data.map_scale_km,
				(normalized_z - 0.5) * geology_data.map_scale_km
			)
			var coast_bonus := 0.0
			if geology_data.coast_enabled:
				coast_bonus = _coast_influence(normalized_x, normalized_z, geology_data.coast_edge) * 0.22
			moisture[_index(x, z, resolution)] = clampf(
				(base * 0.28)
				+ (geology_data.base_rainfall * 0.54)
				+ (lift * OROGRAPHIC_LIFT_SCALE)
				+ coast_bonus,
				0.0,
				1.0
			)

	return moisture

static func _build_temperature(
	resolution: int,
	elevation: PackedFloat32Array,
	geology_data: WorldGeologyDataScript
) -> PackedFloat32Array:
	var temperature := PackedFloat32Array()
	temperature.resize(resolution * resolution)
	for z in range(resolution):
		var latitude := float(z) / float(resolution - 1)
		var equator_warmth := 1.0 - absf((latitude * 2.0) - 1.0)
		for x in range(resolution):
			var index := _index(x, z, resolution)
			temperature[index] = clampf(
				(geology_data.global_temperature * 0.68)
				+ (equator_warmth * 0.38)
				- (elevation[index] * 0.34),
				0.0,
				1.0
			)

	return temperature

static func _biome_color(
	elevation: float,
	moisture: float,
	temperature: float,
	toxicity_noise: float,
	geology_data: WorldGeologyDataScript
) -> Color:
	if elevation <= geology_data.sea_level:
		var depth := clampf((geology_data.sea_level - elevation) / maxf(geology_data.sea_level, 0.001), 0.0, 1.0)
		return Color(0.04, 0.18 + (0.12 * (1.0 - depth)), 0.34 + (0.22 * (1.0 - depth)), 1.0)

	var alpine := clampf((elevation - 0.72) / 0.28, 0.0, 1.0)
	if alpine > 0.72:
		return Color(0.78, 0.78, 0.74, 1.0).lerp(Color(0.94, 0.94, 0.9, 1.0), clampf((alpine - 0.72) / 0.28, 0.0, 1.0))

	var plant_factor := clampf(
		((moisture * 0.55) + (geology_data.vegetation_spread * 0.25) + (geology_data.tree_canopy_density * 0.2))
		* (1.0 - (geology_data.toxicity * toxicity_noise)),
		0.0,
		1.0
	)
	if temperature < 0.24:
		return Color(0.48, 0.52, 0.48, 1.0).lerp(Color(0.84, 0.86, 0.82, 1.0), 1.0 - temperature)
	if moisture < 0.22:
		return Color(0.66, 0.58, 0.39, 1.0).lerp(Color(0.77, 0.69, 0.48, 1.0), temperature)
	if plant_factor > 0.68 and temperature > 0.38:
		return Color(0.09, 0.27, 0.14, 1.0).lerp(Color(0.13, 0.39, 0.2, 1.0), moisture)
	if plant_factor > 0.4:
		return Color(0.2, 0.38, 0.18, 1.0).lerp(Color(0.31, 0.48, 0.21, 1.0), plant_factor)

	return Color(0.38, 0.42, 0.25, 1.0).lerp(Color(0.52, 0.5, 0.33, 1.0), temperature)

static func _new_noise(seed: int, frequency: float, fractal_type: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = fractal_type
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.frequency = frequency
	return noise

static func _sample_noise_01(noise: FastNoiseLite, x: float, z: float) -> float:
	return clampf((noise.get_noise_2d(x, z) + 1.0) * 0.5, 0.0, 1.0)

static func _coast_influence(normalized_x: float, normalized_z: float, coast_edge: String) -> float:
	var distance_to_edge := normalized_x
	if coast_edge == WorldGeologyDataScript.COAST_EAST:
		distance_to_edge = 1.0 - normalized_x
	elif coast_edge == WorldGeologyDataScript.COAST_NORTH:
		distance_to_edge = normalized_z
	elif coast_edge == WorldGeologyDataScript.COAST_SOUTH:
		distance_to_edge = 1.0 - normalized_z

	return 1.0 - _smoothstep(0.0, 0.24, distance_to_edge)

static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))

static func _index(x: int, z: int, resolution: int) -> int:
	return z * resolution + x

static func _seed_from_text(text: String) -> int:
	var hash_value := 2166136261
	for character_index in range(text.length()):
		hash_value = int((hash_value ^ text.unicode_at(character_index)) * 16777619) & 0x7fffffff
	return max(hash_value, 1)
