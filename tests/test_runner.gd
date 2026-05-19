extends SceneTree

const TestContextScript := preload("res://tests/support/test_context.gd")
const ProjectConfigSuiteScript := preload("res://tests/suites/project_config_suite.gd")
const ObjectCompositionSuiteScript := preload("res://tests/suites/object_composition_suite.gd")
const NativeNavigationSuiteScript := preload("res://tests/suites/native_navigation_suite.gd")
const MovementControllerSuiteScript := preload("res://tests/suites/movement_controller_suite.gd")
const WallLayoutSuiteScript := preload("res://tests/suites/wall_layout_suite.gd")
const MapBuilderSuiteScript := preload("res://tests/suites/map_builder_suite.gd")
const InteractionUiSuiteScript := preload("res://tests/suites/interaction_ui_suite.gd")
const MainSceneSuiteScript := preload("res://tests/suites/main_scene_suite.gd")
const MainSceneRaycastSuiteScript := preload("res://tests/suites/main_scene_raycast_suite.gd")
const CameraSuiteScript := preload("res://tests/suites/camera_suite.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await physics_frame
	if not await _run_smoke_checks():
		quit(1)
		return

	print("Smoke Test Passed: Compilation successful")
	quit()

func _run_smoke_checks() -> bool:
	var ctx := TestContextScript.new(self)
	ctx.ensure_root_event_bus()

	for suite in _build_suites():
		if not await suite.run(ctx):
			return false

	return true

func _build_suites() -> Array[RefCounted]:
	return [
		ProjectConfigSuiteScript.new(),
		ObjectCompositionSuiteScript.new(),
		NativeNavigationSuiteScript.new(),
		MovementControllerSuiteScript.new(),
		WallLayoutSuiteScript.new(),
		MapBuilderSuiteScript.new(),
		InteractionUiSuiteScript.new(),
		MainSceneSuiteScript.new(),
		MainSceneRaycastSuiteScript.new(),
		CameraSuiteScript.new(),
	]
