extends "res://test/visual/visual_base.gd"
## Variant goldens (UI_OVERHAUL_PLAN.md 7.1): a few screens at 150% and 200%
## UI scale and in German and Russian, one variant per run (VISUAL_VARIANT;
## see visual_base.gd). Pending when VISUAL_VARIANT isn't set.


func test_variant_options_screen():
	await _check_variant(
		func():
			var screen := OptionsScreen.new()
			screen.source = FAKE_OPTIONS.new()
			return screen,
		"options_screen",
		func(s): s.refresh()
	)


func test_variant_production_screen():
	await _check_variant(
		func():
			var screen := ProductionScreen.new()
			screen.source = FAKE_PRODUCTION.new()
			return screen,
		"production_screen",
		func(s): s.refresh()
	)


func test_variant_designer_screen():
	await _check_variant(
		func():
			var screen := DesignerScreen.new()
			screen.source = FAKE_DESIGNER.new()
			return screen,
		"designer_screen",
		_fill_designer
	)


func test_variant_game_shell():
	await _check_variant(
		func():
			var shell := GameShell.new()
			shell.follow_game = false
			return shell,
		"game_shell_system_panel",
		_fill_shell
	)
