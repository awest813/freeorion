extends GutTest
## Shared by the golden-screenshot tests (test_visual_golden.gd, the 100%
## English goldens, and test_visual_variants.gd): rendering a scene,
## comparing it with its golden image, and filling scenes with fake data.
##
## Golden-screenshot tests need a real renderer, so they are pending in
## headless runs; CI runs them under Xvfb with the opengl3 driver:
##   xvfb-run godot --rendering-driver opengl3 --resolution 1280x800 -s --path godot4 \
##     addons/gut/gut_cmdln.gd -gdir=res://test/visual -gexit
## Set UPDATE_GOLDENS=1 to (re)write the golden images instead of comparing.
##
## Variants (UI_OVERHAUL_PLAN.md 7.1) run some screens again, one variant per
## run, with VISUAL_VARIANT set; the 100% English goldens are pending then:
##   VISUAL_VARIANT=scale150 ... --resolution 1920x1080  (1280x720 at 150%)
##   VISUAL_VARIANT=scale200 ... --resolution 2560x1600  (1280x800 at 200%)
##   VISUAL_VARIANT=de / ru  ... --resolution 1280x800
## Their goldens are in golden/<variant>/.
## Failing comparisons save the actual image and a diff to user://visual/.

const FAKE_OPTIONS := preload("res://test/unit/fake_options_source.gd")
const FAKE_PRODUCTION := preload("res://test/unit/fake_production_source.gd")
const FAKE_RESEARCH := preload("res://test/unit/fake_research_source.gd")
const FAKE_DESIGNER := preload("res://test/unit/fake_designer_source.gd")
const GALAXY_MAP_VIEW := preload("res://map/GalaxyMapView.tscn")
const GOLDEN_DIR := "res://test/visual/golden/"
const SIZE := Vector2i(1280, 800)
## A pixel differs if any channel differs by more than this (0-255).
const CHANNEL_TOLERANCE := 24
## The test fails if more than this fraction of pixels differ.
const MAX_DIFF_FRACTION := 0.005
## Variants: UI scale with the window size it runs at, or a language.
const VARIANTS := {
	"scale150": {"scale": 1.5, "size": Vector2i(1920, 1080)},
	"scale200": {"scale": 2.0, "size": Vector2i(2560, 1600)},
	"de": {"language": "de"},
	"ru": {"language": "ru"},
}

var _variant := OS.get_environment("VISUAL_VARIANT")


func before_all():
	FOUi.reduce_motion = true


func after_all():
	FOUi.reduce_motion = false


func _check_scene(scene: Control, golden_name: String, setup := Callable()) -> void:
	if DisplayServer.get_name() == "headless":
		pending("Needs a renderer (run under Xvfb with --rendering-driver opengl3)")
		scene.free()
		return
	if not _variant.is_empty():
		pending("100%% English golden; this run is the %s variant" % _variant)
		scene.free()
		return
	_compare_to_golden(await _render_offscreen(scene, setup), golden_name)


## The variant of golden \a golden_name for this run's VISUAL_VARIANT, with
## the scene \a make_scene builds (after the language is switched).
func _check_variant(make_scene: Callable, golden_name: String, setup := Callable()) -> void:
	if DisplayServer.get_name() == "headless" or _variant.is_empty():
		pending("Variant golden: run with VISUAL_VARIANT (%s)" % ", ".join(VARIANTS.keys()))
		return
	if not VARIANTS.has(_variant):
		fail_test("Unknown VISUAL_VARIANT %s" % _variant)
		return
	var config: Dictionary = VARIANTS[_variant]
	var options := Engine.get_singleton("FOOptions")
	var name := "%s/%s" % [_variant, golden_name]
	if config.has("language"):
		var previous: String = options.get_language()
		assert_true(options.set_language(config["language"]), "Stringtable %s" % config["language"])
		_compare_to_golden(await _render_offscreen(make_scene.call(), setup), name)
		options.set_language(previous)
		return
	if get_window().size != config["size"]:
		fail_test(
			(
				"Run the %s variant with --resolution %dx%d"
				% [_variant, config["size"].x, config["size"].y]
			)
		)
		return
	# The scene is made at the variant's scale: "auto" differs by window.
	var previous := FOUi.get_scale_setting()
	FOUi.set_scale_setting(str(config["scale"]))
	await wait_process_frames(2)
	var image := await _render_scaled(make_scene.call(), setup, config["scale"])
	FOUi.set_scale_setting(previous)
	_compare_to_golden(image, name)


# In the window itself at UI scale \a ui_scale, as players see it (a
# SubViewport would scale the glyphs as bitmaps), over GUT's runner panel.
func _render_scaled(scene: Control, setup: Callable, ui_scale: float) -> Image:
	var previous := FOUi.get_scale_setting()
	FOUi.set_scale_setting(str(ui_scale))
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child_autofree(layer)
	var backdrop := ColorRect.new()
	backdrop.color = FOUi.tokens.surface
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	scene.theme = FOUi.theme
	layer.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_process_frames(3)
	if setup.is_valid():
		setup.call(scene)
	await wait_process_frames(10)
	# GUT's own panel is laid out for the scale the run started at, and can
	# show at the edges: hide it for the shot.
	var hidden: Array[CanvasLayer] = []
	for other: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if other != layer and other.visible and not layer.is_ancestor_of(other):
			other.visible = false
			hidden.push_back(other)
	await wait_process_frames(2)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	for other in hidden:
		other.visible = true
	FOUi.set_scale_setting(previous)
	return image


func _render_offscreen(scene: Control, setup: Callable) -> Image:
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
	return actual


func _compare_to_golden(actual: Image, golden_name: String) -> void:
	var golden_path := ProjectSettings.globalize_path(GOLDEN_DIR + golden_name + ".png")
	if OS.get_environment("UPDATE_GOLDENS") == "1":
		DirAccess.make_dir_recursive_absolute(golden_path.get_base_dir())
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
	# Variants' goldens are in subfolders ("ru/...").
	DirAccess.make_dir_recursive_absolute((dir + golden_name).get_base_dir())
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
		# Supply around system 10 and a nebula near system 50.
		"supply_systems": PackedInt32Array([10, 13, 16, 22, 85]),
		"supply_system_colors":
		PackedColorArray(
			[
				Color("#3d9bff"),
				Color("#3d9bff"),
				Color("#3d9bff"),
				Color("#3d9bff"),
				Color("#3d9bff")
			]
		),
		"supply_lanes": PackedInt32Array([lanes[20], lanes[21], lanes[26], lanes[27]]),
		"supply_lane_colors": PackedColorArray([Color("#3d9bff"), Color("#3d9bff")]),
		"field_ids": PackedInt32Array([900]),
		"field_positions": PackedVector2Array([positions[50] + Vector2(60, 0)]),
		"field_radii": PackedFloat32Array([90.0]),
		"field_graphics": PackedStringArray(["fields/star_forming_nebula_1.png"]),
	}
	var colors := PackedColorArray(
		[Color("#3d9bff"), Color("#3d9bff"), Color("#ff5a4f"), Color("#ffd23d")]
	)
	view.map.set_snapshot(snapshot, names, colors)
	view.map.select_system(10)


func _fill_designer(screen: DesignerScreen) -> void:
	screen.refresh()
	screen.place_part("SR_WEAPON_1_1")
	screen.place_part("AR_STD_PLATE")
	screen._on_slot_pressed(2)
	screen._name.text = "Raider"
	screen._name.text_changed.emit("Raider")


func _fill_shell(shell: GameShell) -> void:
	_fill_galaxy(shell.map_view)
	shell.top_bar.set_state("Empire Blue", Color("#3d9bff"), 12, false)
	(
		shell
		. top_bar
		. set_resources(
			{
				"industry": 15.0,
				"industry_spent": 12.0,
				"research": 9.4,
				"research_spent": 9.4,
				"influence": 23.0,
				"influence_change": 1.5,
				"pp_stockpile": 4.0,
				"population": 34.5,
				"ships": 6,
				"detection": 30.0,
			}
		)
	)
	shell.system_panel.show_data(preload("res://test/unit/test_system_panel.gd").SAMPLE)
	shell.system_panel.select_fleet(7)
	shell.fleet_panel.show_data(preload("res://test/unit/test_fleet_panel.gd").SAMPLE)
	var map := shell.map_view.map
	map.set_route(map.system_position(10), PackedInt32Array([85, 22]), GameShell.eta_text(3))
	shell.feed.show_entries(preload("res://test/unit/test_notification_feed.gd").ENTRIES, 12)
	map.hover_system(50)
