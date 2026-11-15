extends GutTest
## Golden-screenshot tests. They need a real renderer, so they are pending in
## headless runs; CI runs them under Xvfb with the opengl3 driver:
##   xvfb-run godot --rendering-driver opengl3 --resolution 1280x800 -s --path godot4 \
##     addons/gut/gut_cmdln.gd -gdir=res://test/visual -gexit
## Set UPDATE_GOLDENS=1 to (re)write the golden images instead of comparing.
## Failing comparisons save the actual image and a diff to user://visual/.

const GALLERY := preload("res://ui/ComponentGallery.tscn")
const FAKE_OPTIONS := preload("res://test/unit/fake_options_source.gd")
const GALAXY_MAP_VIEW := preload("res://map/GalaxyMapView.tscn")
const GOLDEN_DIR := "res://test/visual/golden/"
const SIZE := Vector2i(1280, 800)
## A pixel differs if any channel differs by more than this (0-255).
const CHANNEL_TOLERANCE := 24
## The test fails if more than this fraction of pixels differ.
const MAX_DIFF_FRACTION := 0.005


func before_all():
	FOUi.reduce_motion = true


func after_all():
	FOUi.reduce_motion = false


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


func test_production_screen():
	var screen := ProductionScreen.new()
	screen.source = preload("res://test/unit/fake_production_source.gd").new()
	await _check_scene(screen, "production_screen", func(s): s.refresh())


func test_research_screen():
	var screen := ResearchScreen.new()
	screen.source = preload("res://test/unit/fake_research_source.gd").new()
	await _check_scene(screen, "research_screen", func(s): s.refresh())


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


func _fill_shell(shell: GameShell) -> void:
	_fill_galaxy(shell.map_view)
	shell.top_bar.set_state("Empire Blue", Color("#3d9bff"), 12, false)
	shell.system_panel.show_data(preload("res://test/unit/test_system_panel.gd").SAMPLE)
	shell.system_panel.select_fleet(7)
	shell.fleet_panel.show_data(preload("res://test/unit/test_fleet_panel.gd").SAMPLE)
	var map := shell.map_view.map
	map.set_route(map.system_position(10), PackedInt32Array([85, 22]), GameShell.eta_text(3))
	shell.feed.show_entries(preload("res://test/unit/test_notification_feed.gd").ENTRIES, 12)
	map.hover_system(50)


func _check_scene(scene: Control, golden_name: String, setup := Callable()) -> void:
	if DisplayServer.get_name() == "headless":
		pending("Needs a renderer (run under Xvfb with --rendering-driver opengl3)")
		scene.free()
		return
	# Render into an own viewport so GUT's runner panel is not in the shot.
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)
	# Theme inheritance stops at a viewport: set the FOUi theme explicitly.
	scene.theme = FOUi.theme
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_process_frames(3)
	if setup.is_valid():
		setup.call(scene)
	await wait_process_frames(10)
	await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image()
	actual.convert(Image.FORMAT_RGB8)
	_compare_to_golden(actual, golden_name)


func _compare_to_golden(actual: Image, golden_name: String) -> void:
	var golden_path := ProjectSettings.globalize_path(GOLDEN_DIR + golden_name + ".png")
	if OS.get_environment("UPDATE_GOLDENS") == "1":
		actual.save_png(golden_path)
		pass_test("Golden written: %s" % golden_path)
		return
	if not FileAccess.file_exists(golden_path):
		fail_test("Missing golden %s; run with UPDATE_GOLDENS=1" % golden_path)
		return
	var golden := Image.load_from_file(golden_path)
	golden.convert(Image.FORMAT_RGB8)
	if golden.get_size() != actual.get_size():
		fail_test("Size %s differs from golden %s" % [actual.get_size(), golden.get_size()])
		_save_failure(actual, null, golden_name)
		return
	var diff := Image.create(actual.get_width(), actual.get_height(), false, Image.FORMAT_RGB8)
	var differing := 0
	for y in actual.get_height():
		for x in actual.get_width():
			var a := actual.get_pixel(x, y)
			var g := golden.get_pixel(x, y)
			var delta := maxf(absf(a.r - g.r), maxf(absf(a.g - g.g), absf(a.b - g.b))) * 255.0
			if delta > CHANNEL_TOLERANCE:
				differing += 1
				diff.set_pixel(x, y, Color.RED)
	var fraction := float(differing) / (actual.get_width() * actual.get_height())
	assert_lte(
		fraction, MAX_DIFF_FRACTION, "%s: %.3f%% pixels differ" % [golden_name, fraction * 100.0]
	)
	if fraction > MAX_DIFF_FRACTION:
		_save_failure(actual, diff, golden_name)


func _save_failure(actual: Image, diff: Image, golden_name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://visual/")
	DirAccess.make_dir_recursive_absolute(dir)
	actual.save_png(dir + golden_name + "_actual.png")
	if diff:
		diff.save_png(dir + golden_name + "_diff.png")
	gut.p("Saved failure images to %s" % dir)


func _fill_galaxy(view: GalaxyMapView) -> void:
	# Deterministic spiral galaxy of 300 systems with nearest-neighbour lanes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ids := PackedInt32Array()
	var positions := PackedVector2Array()
	var star_types := PackedInt32Array()
	var names := PackedStringArray()
	for i in 300:
		var arm := i % 3
		var t := rng.randf_range(0.15, 1.0)
		var angle := t * 5.0 + arm * TAU / 3.0 + rng.randf_range(-0.25, 0.25)
		var radius := t * 900.0 + rng.randf_range(-40.0, 40.0)
		ids.push_back(i)
		positions.push_back(Vector2(cos(angle), sin(angle)) * radius)
		star_types.push_back(-1 if i % 7 == 0 else rng.randi_range(0, 7))
		names.push_back("System %d" % i)
	var lanes := PackedInt32Array()
	for i in positions.size():
		var nearest := -1
		var best := INF
		for j in positions.size():
			var d := positions[i].distance_squared_to(positions[j])
			if j != i and d < best:
				best = d
				nearest = j
		lanes.append_array([mini(i, nearest), maxi(i, nearest)])
	var fleets := PackedVector2Array([positions[10], positions[10], positions[50], positions[120]])
	var snapshot := {
		"system_ids": ids,
		"system_positions": positions,
		"system_star_types": star_types,
		"lanes": lanes,
		"fleet_ids": PackedInt32Array([1, 2, 3, 4]),
		"fleet_positions": fleets,
		"fleet_owner_ids": PackedInt32Array([1, 1, 2, 3]),
	}
	var colors := PackedColorArray(
		[Color("#3d9bff"), Color("#3d9bff"), Color("#ff5a4f"), Color("#ffd23d")]
	)
	view.map.set_snapshot(snapshot, names, colors)
	view.map.select_system(10)
