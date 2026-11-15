extends "res://test/visual/visual_base.gd"
## The 100% English golden screenshots; see visual_base.gd for how to run
## and update them.

const GALLERY := preload("res://ui/ComponentGallery.tscn")


func test_component_gallery_default_theme():
	await _check_scene(GALLERY.instantiate(), "gallery_default")


func test_component_gallery_high_contrast_theme():
	FOUi.apply_theme("high_contrast")
	await _check_scene(GALLERY.instantiate(), "gallery_high_contrast")
	FOUi.apply_theme("default")


func test_galaxy_map_synthetic():
	var view: GalaxyMapView = GALAXY_MAP_VIEW.instantiate()
	view.follow_game = false
	await _check_scene(view, "galaxy_map_synthetic", _fill_galaxy)


func test_game_shell_with_system_panel():
	var shell := GameShell.new()
	shell.follow_game = false
	await _check_scene(shell, "game_shell_system_panel", _fill_shell)


func test_game_menu_over_shell():
	var shell := GameShell.new()
	shell.follow_game = false
	await _check_scene(shell, "game_menu", _open_menu)


func _open_menu(shell: GameShell) -> void:
	_fill_shell(shell)
	shell.game_menu.open("Empire Blue  ·  " + tr("MAP_BTN_TURN_UPDATE").replace("%1%", "12"))


func test_planet_panel():
	# In a row, as in the game's side column: the panel's own width.
	var host := HBoxContainer.new()
	var panel := PlanetPanel.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	host.add_child(panel)
	await _check_scene(
		host,
		"planet_panel",
		func(_h): panel.show_data(preload("res://test/unit/test_planet_panel.gd").SAMPLE)
	)


func test_empires_screen():
	var screen := EmpiresScreen.new()
	screen.source = preload("res://test/unit/fake_diplomacy_source.gd").new()
	await _check_scene(screen, "empires_screen", func(s): s.refresh())


func test_production_screen():
	var screen := ProductionScreen.new()
	screen.source = FAKE_PRODUCTION.new()
	await _check_scene(screen, "production_screen", func(s): s.refresh())


func test_research_screen():
	var screen := ResearchScreen.new()
	screen.source = FAKE_RESEARCH.new()
	await _check_scene(screen, "research_screen", func(s): s.refresh())


func test_research_tree():
	var screen := ResearchScreen.new()
	screen.source = FAKE_RESEARCH.new()
	await _check_scene(
		screen,
		"research_tree",
		func(s):
			s.refresh()
			# Selected first, so the tree doesn't centre itself on the frontier.
			s._tree.selected = "LRN_ALGO_ELEGANCE"
			s.show_tree(true)
			s._tree.zoom = 1.0
			s._tree.offset = Vector2(24, 24)
			s._show_tech_detail("LRN_ALGO_ELEGANCE")
	)


func test_pedia_screen():
	var screen := PediaScreen.new()
	screen.source = preload("res://test/unit/fake_pedia_source.gd").new()
	await _check_scene(screen, "pedia_screen", _fill_pedia)


func _fill_pedia(screen: PediaScreen) -> void:
	screen.open("tech", "LRN_ALGO_ELEGANCE")
	screen.search("Brain")


func test_options_screen():
	var screen := OptionsScreen.new()
	screen.source = FAKE_OPTIONS.new()
	await _check_scene(screen, "options_screen", func(s): s.refresh())


func test_options_hotkeys():
	var screen := OptionsScreen.new()
	screen.source = FAKE_OPTIONS.new()
	await _check_scene(
		screen,
		"options_hotkeys",
		func(s):
			s.refresh()
			s._right_tabs.current_tab = 1
			s._capturing = "home"
			s._refresh_hotkeys()
	)


func test_government_screen():
	var screen := GovernmentScreen.new()
	screen.source = preload("res://test/unit/fake_government_source.gd").new()
	await _check_scene(screen, "government_screen", func(s): s.refresh())


func test_galaxy_setup_screen():
	var setup := GalaxySetupScreen.new()
	var fake: RefCounted = FAKE_OPTIONS.new()
	fake.options["setup.galaxy.shape"] = {"value": "SPIRAL_3", "default": "DISC", "description": ""}
	fake.options["setup.empire.name"] = {"value": "Terran Union", "default": "", "description": ""}
	fake.options["setup.player.name"] = {"value": "Admiral", "default": "", "description": ""}
	setup.source = fake
	await _check_scene(setup, "galaxy_setup_screen", func(s): s.refresh())


func test_load_screen():
	var screen := SaveLoadScreen.new()
	screen.source = preload("res://test/unit/fake_saves_source.gd").new()
	await _check_scene(screen, "load_screen", _select_first_save)


func _select_first_save(screen: SaveLoadScreen) -> void:
	screen.refresh()
	screen._list.get_child(0).pressed.emit()


func test_combat_screen():
	var screen := CombatScreen.new()
	screen.source = preload("res://test/unit/fake_combat_source.gd").new()
	await _check_scene(screen, "combat_screen", _fill_combat)


func _fill_combat(screen: CombatScreen) -> void:
	screen.refresh()
	var toggles: Array = screen._detail.find_children("*", "Button", true, false).filter(
		func(b): return b.toggle_mode
	)
	toggles[1].button_pressed = true


func test_objects_screen():
	var screen := ObjectsScreen.new()
	screen.source = preload("res://test/unit/fake_objects_source.gd").new()
	await _check_scene(screen, "objects_screen", _fill_objects)


func _fill_objects(screen: ObjectsScreen) -> void:
	screen._only_mine.button_pressed = false
	screen.sort_by("population")
	screen._tree.get_root().get_child(1).select(0)


func test_designer_screen():
	var screen := DesignerScreen.new()
	screen.source = FAKE_DESIGNER.new()
	await _check_scene(screen, "designer_screen", _fill_designer)
