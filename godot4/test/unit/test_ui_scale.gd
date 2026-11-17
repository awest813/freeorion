extends GutTest
## UI scale resolution.


func test_parse_setting():
	assert_eq(FOUiScale.parse_setting("auto"), -1.0)
	assert_eq(FOUiScale.parse_setting(""), -1.0)
	assert_eq(FOUiScale.parse_setting("big"), -1.0)
	assert_almost_eq(FOUiScale.parse_setting("1.25"), 1.25, 0.001)
	assert_almost_eq(FOUiScale.parse_setting(" 1.33 "), 1.35, 0.001, "Snapped to 5% steps")
	assert_almost_eq(FOUiScale.parse_setting("0.1"), FOUiScale.MIN_SCALE, 0.001)
	assert_almost_eq(FOUiScale.parse_setting("9"), FOUiScale.MAX_SCALE, 0.001)


func test_display_scale():
	assert_almost_eq(FOUiScale.display_scale(1.0, 96), 1.0, 0.001)
	assert_almost_eq(FOUiScale.display_scale(1.0, 144), 1.5, 0.001)
	assert_almost_eq(FOUiScale.display_scale(2.0, 96), 2.0, 0.001, "OS scale wins")
	assert_almost_eq(FOUiScale.display_scale(1.0, 72), 1.0, 0.001, "Never below 100%")
	assert_almost_eq(FOUiScale.display_scale(1.0, 400), FOUiScale.MAX_SCALE, 0.001)


func test_auto_scale_keeps_minimum_logical_size():
	# 4K at 192 DPI: 200% leaves 1920x1080 logical, fine.
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 192, Vector2i(3840, 2160)), 2.0, 0.001)
	# 1080p laptop at 144 DPI: 150% would leave 1280x720, exactly the minimum.
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 144, Vector2i(1920, 1080)), 1.5, 0.001)
	# 1366x768 at 120 DPI: 125% would go below 1280x720; 105% is the largest that fits.
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 120, Vector2i(1366, 768)), 1.05, 0.001)
	# 1280x720 window: no room to scale up at all.
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 144, Vector2i(1280, 720)), 1.0, 0.001)


func test_manual_setting_overrides_auto():
	assert_almost_eq(FOUiScale.resolve("1.75", 1.0, 96, Vector2i(3840, 2160)), 1.75, 0.001)
	assert_almost_eq(FOUiScale.resolve("0.75", 1.0, 192, Vector2i(3840, 2160)), 0.75, 0.001)
	# Too large for the window: the largest that fits instead.
	assert_almost_eq(FOUiScale.resolve("1.75", 1.0, 96, Vector2i(1366, 768)), 1.05, 0.001)


func test_auto_follows_the_resolution_when_the_dpi_says_nothing():
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 96, Vector2i(1920, 1080)), 1.0, 0.001)
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 96, Vector2i(2560, 1440)), 1.35, 0.001)
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 96, Vector2i(3840, 2160)), 2.0, 0.001)
	assert_almost_eq(FOUiScale.resolve("auto", 1.0, 96, Vector2i(1280, 800)), 1.0, 0.001)


func test_an_exact_fit_is_not_rounded_down():
	assert_almost_eq(FOUiScale.max_scale_for_window(Vector2i(2560, 1600)), 2.0, 0.001)
	assert_almost_eq(FOUiScale.resolve("2.0", 1.0, 96, Vector2i(2560, 1600)), 2.0, 0.001)
