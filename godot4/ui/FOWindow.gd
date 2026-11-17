class_name FOWindow
extends RefCounted
## The game window, as the GG client keeps it: fullscreen or not, and the
## windowed size and position, in the video.* options (shared with the GG
## client's config). Shell restores it at start and remembers it on exit;
## Alt+Enter (hotkey "fullscreen") and the options screen toggle fullscreen.

const OPTION_FULLSCREEN := "video.fullscreen.enabled"
## Windowed geometry: option suffix -> default.
const GEOMETRY := {"width": 1280, "height": 800, "left": -1, "top": -1}
const MIN_SIZE := Vector2i(1024, 640)
## Frame rate: vsync, a cap (GG's video.fps.max), a lower one while the window
## is in the background (video.fps.unfocused), and the FPS counter.
const OPTION_VSYNC := "video.vsync.enabled"
const OPTION_FPS_LIMITED := "video.fps.max.enabled"
const OPTION_FPS_MAX := "video.fps.max"
const OPTION_FPS_BACKGROUND := "video.fps.unfocused.enabled"
const OPTION_FPS_BACKGROUND_MAX := "video.fps.unfocused"
const OPTION_FPS_SHOWN := "video.fps.shown"
const OPTION_MONITOR := "video.monitor.id"
## Frame rate caps offered; 0 is none.
const FPS_STEPS := [30, 60, 120, 144, 0]
## Window sizes offered (those that fit the screen).
const SIZES := [
	Vector2i(1024, 640),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]


## Register the options (if the GG client hasn't) on \a options (FOOptions).
static func add_options(options: Object) -> void:
	options.add_option(OPTION_FULLSCREEN, "OPTIONS_DB_FULLSCREEN", false)
	for key in GEOMETRY:
		options.add_option(
			"video.windowed." + key, "OPTIONS_DB_APP_" + key.to_upper() + "_WINDOWED", GEOMETRY[key]
		)
	options.add_option(OPTION_VSYNC, "OPTIONS_DB_VSYNC", true)
	options.add_option(OPTION_FPS_LIMITED, "OPTIONS_DB_LIMIT_FPS", false)
	options.add_option(OPTION_FPS_MAX, "OPTIONS_DB_MAX_FPS", 60)
	options.add_option(OPTION_FPS_BACKGROUND, "OPTIONS_DB_LIMIT_FPS_NO_FOCUS", true)
	options.add_option(OPTION_FPS_BACKGROUND_MAX, "OPTIONS_DB_MAX_FPS_NO_FOCUS", 10)
	options.add_option(OPTION_FPS_SHOWN, "OPTIONS_DB_SHOW_FPS", false)
	options.add_option(OPTION_MONITOR, "OPTIONS_DB_FULLSCREEN_MONITOR_ID", 0)


## Whether there is a real window to manage (not headless runs).
static func has_window() -> bool:
	return DisplayServer.get_name() != "headless"


## Restore the window as \a options remember it.
static func restore(options: Object) -> void:
	add_options(options)
	if not has_window():
		return
	# Never smaller than the layouts are made for.
	DisplayServer.window_set_min_size(MIN_SIZE)
	# Started with -f / --fullscreen (the engine takes the flag): remember
	# it, as the GG client's -f sets this option.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		options.set_value(OPTION_FULLSCREEN, true)
		options.commit()
	if bool(options.get_value(OPTION_FULLSCREEN)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var size := Vector2i(
		int(options.get_value("video.windowed.width")),
		int(options.get_value("video.windowed.height"))
	)
	if size.x >= MIN_SIZE.x and size.y >= MIN_SIZE.y:
		DisplayServer.window_set_size(size)
	var at := Vector2i(
		int(options.get_value("video.windowed.left")), int(options.get_value("video.windowed.top"))
	)
	if at.x >= 0 and at.y >= 0:
		DisplayServer.window_set_position(at)


## Remember the windowed size and position in \a options (when windowed).
static func remember(options: Object) -> void:
	add_options(options)
	if not has_window() or is_fullscreen():
		return
	var size := DisplayServer.window_get_size()
	var at := DisplayServer.window_get_position()
	options.set_value("video.windowed.width", size.x)
	options.set_value("video.windowed.height", size.y)
	options.set_value("video.windowed.left", at.x)
	options.set_value("video.windowed.top", at.y)
	options.commit()


static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)


## Switch fullscreen on or off, and remember it in \a options.
static func set_fullscreen(on: bool, options: Object) -> void:
	add_options(options)
	if has_window():
		if on and not is_fullscreen():
			remember(options)
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
		)
	options.set_value(OPTION_FULLSCREEN, on)
	options.commit()


static func toggle_fullscreen(options: Object) -> void:
	set_fullscreen(not bool(options.get_value(OPTION_FULLSCREEN)), options)


## The SIZES that fit in \a screen (the usable area of the window's screen).
static func window_sizes(screen: Vector2i) -> Array:
	return SIZES.filter(func(size: Vector2i): return size.x <= screen.x and size.y <= screen.y)


## Resize the window to \a size, centred on its screen, and remember it.
static func set_window_size(size: Vector2i, options: Object) -> void:
	if has_window() and not is_fullscreen():
		var screen := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(screen)
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(area.position + (area.size - size) / 2)
	remember(options)


## Move the window to screen \a index, and remember it.
static func set_monitor(index: int, options: Object) -> void:
	add_options(options)
	if has_window() and index < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(index)
	options.set_value(OPTION_MONITOR, index)
	options.commit()


## Apply vsync and the frame rate cap from \a options; \a focused false
## when the window is in the background (the lower cap then, if on).
static func apply_frame_rate(options: Object, focused := true) -> void:
	add_options(options)
	var cap := (
		int(options.get_value(OPTION_FPS_MAX)) if options.get_value(OPTION_FPS_LIMITED) else 0
	)
	if not focused and options.get_value(OPTION_FPS_BACKGROUND):
		cap = int(options.get_value(OPTION_FPS_BACKGROUND_MAX))
	Engine.max_fps = cap
	if has_window():
		var vsync: bool = options.get_value(OPTION_VSYNC)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		)
