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


## Register the options (if the GG client hasn't) on \a options (FOOptions).
static func add_options(options: Object) -> void:
	options.add_option(OPTION_FULLSCREEN, "OPTIONS_DB_FULLSCREEN", false)
	for key in GEOMETRY:
		options.add_option(
			"video.windowed." + key, "OPTIONS_DB_APP_" + key.to_upper() + "_WINDOWED", GEOMETRY[key]
		)


## Whether there is a real window to manage (not headless runs).
static func has_window() -> bool:
	return DisplayServer.get_name() != "headless"


## Restore the window as \a options remember it.
static func restore(options: Object) -> void:
	add_options(options)
	if not has_window():
		return
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
