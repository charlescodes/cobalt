extends RefCounted

const CameraRigScript := preload("res://src/camera/camera_rig.gd")

func run(ctx) -> bool:
	await ctx.idle_frame()

	var camera_distance: float = CameraRigScript.camera_distance_for_height(7.0, deg_to_rad(-55.0))
	if not camera_distance > 7.0:
		return ctx.fail("Camera rig distance should exceed its vertical height at an angled pitch.")

	return true
