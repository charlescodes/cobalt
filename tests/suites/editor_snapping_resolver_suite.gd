extends RefCounted

const EditorSnappingResolverScript := preload("res://src/editor/editor_snapping_resolver.gd")
const WallSegmentDataScript := preload("res://src/walls/wall_segment_data.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var snapped := EditorSnappingResolverScript.snap_vector3(Vector3(1.04, 0.06, -2.04))
	if snapped.distance_to(Vector3(1.0, 0.1, -2.0)) > 0.001:
		return ctx.fail("EditorSnappingResolver did not snap Vector3 components to 10cm.")

	var raw := Vector3(1.037, 0.044, -2.019)
	if EditorSnappingResolverScript.snap_vector3(raw, 0.0) != raw:
		return ctx.fail("EditorSnappingResolver should leave positions unchanged for non-positive steps.")

	var wall := WallSegmentDataScript.new()
	wall.start_position = Vector3(0.0, 0.0, 0.0)
	wall.end_position = Vector3(3.0, 0.0, 0.0)
	var wall_snapped := EditorSnappingResolverScript.snap_with_context(
		Vector3(1.24, 0.0, 0.31),
		{
			&"wall_segments": [wall],
			&"wall_snap_distance_m": 0.5,
		}
	)
	if wall_snapped.distance_to(Vector3(1.2, 0.0, 0.0)) > 0.001:
		return ctx.fail("EditorSnappingResolver did not context-snap to the nearest wall segment.")

	var slope_snapped := EditorSnappingResolverScript.snap_with_context(
		Vector3(2.04, 0.0, 0.0),
		{
			&"slope_origin": Vector3.ZERO,
			&"slope_normal": Vector3(-0.5, 1.0, 0.0),
		}
	)
	if slope_snapped.distance_to(Vector3(2.0, 1.0, 0.0)) > 0.001:
		return ctx.fail("EditorSnappingResolver did not apply contextual slope elevation.")

	return true
