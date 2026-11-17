class_name OptionsScreen
extends PanelContainer
## Options, in pages: Display (window, UI scale, frame rate), Interface,
## Sound, Gameplay (what players change, in plain words), Keyboard shortcuts,
## and Advanced (every other option, searchable, with a typed editor,
## validation feedback and reset). Every change applies and is saved at once.

signal close_requested

## The pages on the right.
enum Page { DISPLAY, INTERFACE, SOUND, GAMEPLAY, HOTKEYS, ADVANCED }

const SCALE_STEPS := [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
const THEMES := ["default", "high_contrast"]
const MAX_LISTED := 120
## Internal or launch-only options that make no sense to edit in game, and
## those other screens edit. The interface options have their own controls on
## the left. Options only the GG client uses (its colours, fonts, window
## layouts) aren't registered by this client, so they never show.
const HIDDEN_PREFIXES := [
	"version",
	"misc.server-local-binary",
	"resource.path",
	"setup.seed",
	"ui.scale",
	"ui.theme",
	"ui.reduce-motion",
	"audio.",
	"ui.hotkey.godot.",
	"ui.hints.",
	"resource.stringtable.path",
	"video.",
	# Command-line flags for one launch.
	"continue",
	"load",
	"quickstart",
	"auto-connect",
	"auto-advance-n-turns",
	"auto-quit",
	# Edited on their own screens: galaxy setup (and its game rules), the
	# multiplayer connect screen, the map's menu.
	"setup.",
	"ui.map.",
]
## The options players change, on the Gameplay page, in groups: the
## group's caption key, then [option, key]: the key names it and key +
## "_DESC" says what it does. Everything else is under Advanced.
const GAMEPLAY := [
	["OPTIONS_GROUP_TURNS", [["ui.turn.readiness.check", "OPTIONS_GAME_READINESS"]]],
	[
		"OPTIONS_GROUP_FLEETS",
		[
			["ui.fleet.explore.scouts", "OPTIONS_GAME_SCOUTS"],
			["ui.fleet.new.aggression", "OPTIONS_GAME_NEW_FLEET_STANCE"],
		]
	],
	[
		"OPTIONS_GROUP_NEW_GAMES",
		[
			["resource.shipdesign.saved.enabled", "OPTIONS_GAME_SAVED_DESIGNS"],
			["resource.shipdesign.default.enabled", "OPTIONS_GAME_PREMADE_DESIGNS"],
		]
	],
	[
		"OPTIONS_GROUP_AUTOSAVE",
		[
			["save.auto.turn.start.enabled", "OPTIONS_GAME_AUTOSAVE_TURN"],
			["save.auto.turn.interval", "OPTIONS_GAME_AUTOSAVE_EVERY"],
			["save.auto.file.limit", "OPTIONS_GAME_AUTOSAVE_KEEP"],
			["save.auto.exit.enabled", "OPTIONS_GAME_AUTOSAVE_EXIT"],
		]
	],
]
## Look switches under Interface: option, label key.
const LOOK := [["ui.glass", "OPTIONS_GLASS"], ["ui.accent.empire", "OPTIONS_EMPIRE_ACCENT"]]
## Words written in capitals in option titles.
const ACRONYMS := ["ui", "ai", "fps", "id", "xml", "gl", "uri", "ip", "mp"]
## The widest the pages get, centred in wider windows.
const CONTENT_WIDTH := 960.0
## The pages' tab labels, in Page order.
const PAGE_KEYS := [
	"OPTIONS_PAGE_DISPLAY",
	"OPTIONS_INTERFACE",
	"OPTIONS_AUDIO",
	"OPTIONS_PAGE_GAMEPLAY",
	"OPTIONS_PAGE_HOTKEYS",
	"OPTIONS_PAGE_ADVANCED",
]
## Sound controls: on/off option, volume option, label key.
const AUDIO := [
	["audio.music.enabled", "audio.music.volume", "OPTIONS_MUSIC"],
	["audio.effects.enabled", "audio.effects.volume", "OPTIONS_SOUNDS"],
]

var source: Variant = OptionsSource.new()

var _status: Label
var _scale: OptionButton
var _theme: OptionButton
var _motion: CheckButton
var _language: OptionButton
var _fullscreen: CheckButton
var _window_size: OptionButton
var _monitor: OptionButton
var _vsync: CheckButton
var _fps_cap: OptionButton
var _fps_background: CheckButton
var _fps_shown: CheckButton
var _master: HSlider
var _pages: Array[Control] = []
## Per AUDIO row: [switch, volume slider].
var _audio: Array = []
var _search: LineEdit
var _list: VBoxContainer
var _right_tabs: TabBar
var _gameplay: Control
var _gameplay_list: VBoxContainer
var _look: Array[CheckButton] = []
var _all_options: Control
var _hotkeys: Control
var _hotkey_list: VBoxContainer
## The hotkey waiting for a key press, or "".
var _capturing := ""


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


# While a shortcut waits for its key, the next key press is it (Esc
# cancels), before any shortcut can act on it.
func _input(event: InputEvent) -> void:
	if _capturing.is_empty() or not event is InputEventKey or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		_capturing = ""
		_refresh_hotkeys()
		return
	var text := FOHotkeys.describe(event)
	if text.is_empty():
		return  # a modifier on its own; wait for the key
	set_hotkey(_capturing, text)


## Bind \a hotkey to \a text; other hotkeys on the same key lose it.
func set_hotkey(hotkey: String, text: String) -> void:
	var taken: Array = FOHotkeys.conflicts(hotkey, text)
	for other: String in taken:
		FOHotkeys.bind_key(other, "")
	FOHotkeys.bind_key(hotkey, text)
	_capturing = ""
	_status.text = (
		tr("OPTIONS_HOTKEY_MOVED").replace("%1%", text).replace("%2%", _hotkey_label(taken[0]))
		if not taken.is_empty()
		else ""
	)
	_refresh_hotkeys()


## Show the first-time hints again (HintCoach's options).
func reset_hints() -> void:
	if source.exists(HintCoach.OPTION_SEEN):
		source.set_value(HintCoach.OPTION_SEEN, "")
	if source.exists(HintCoach.OPTION_ENABLED):
		source.set_value(HintCoach.OPTION_ENABLED, true)
	_status.text = tr("HINT_RESET_DONE")


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var scale_setting := str(source.get_value(FOUi.OPTION_SCALE))
	_scale.select(_scale_index(scale_setting))
	_theme.select(maxi(0, THEMES.find(str(source.get_value(FOUi.OPTION_THEME)))))
	_motion.set_pressed_no_signal(bool(source.get_value(FOUi.OPTION_REDUCE_MOTION)))
	_fill_languages()
	_refresh_display()
	for i in AUDIO.size():
		if source.exists(AUDIO[i][0]):
			_audio[i][0].set_pressed_no_signal(bool(source.get_value(AUDIO[i][0])))
			_audio[i][1].set_value_no_signal(float(source.get_value(AUDIO[i][1])))
			_audio[i][1].editable = _audio[i][0].button_pressed
	var master: Variant = (
		source.get_value(FOAudio.OPTION_MASTER_VOLUME)
		if source.exists(FOAudio.OPTION_MASTER_VOLUME)
		else 255
	)
	_master.set_value_no_signal(float(master))
	for slider: HSlider in [_master] + _audio.map(func(pair): return pair[1]):
		slider.changed.emit()  # the percentage follows
	for i in LOOK.size():
		_look[i].get_parent().visible = source.exists(LOOK[i][0])
		if source.exists(LOOK[i][0]):
			_look[i].set_pressed_no_signal(bool(source.get_value(LOOK[i][0])))
	_status.text = ""
	_capturing = ""
	_refresh_gameplay()
	_refresh_list()
	_refresh_hotkeys()


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	# A readable column in wide windows: rows not stretched across the screen.
	resized.connect(
		func():
			var side := maxf(0.0, (size.x - CONTENT_WIDTH) / 2.0)
			margin.add_theme_constant_override("margin_left", int(side))
			margin.add_theme_constant_override("margin_right", int(side))
	)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_status = ScreenKit.header(column, "OPTIONS_TITLE", close_requested.emit)
	_right_tabs = TabBar.new()
	for key in PAGE_KEYS:
		_right_tabs.add_tab(tr(key))
	column.add_child(_right_tabs)
	_build_display(_page(column))
	_build_interface(_page(column))
	_build_sound(_page(column))
	_gameplay_list = _page(column)
	_gameplay = _pages.back()
	_hotkey_list = _page(column)
	_hotkeys = _pages.back()
	var all := VBoxContainer.new()
	all.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(all)
	_all_options = all
	_pages.push_back(all)
	var note := ScreenKit.label(tr("OPTIONS_ADVANCED_NOTE"), "SecondaryLabel")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	all.add_child(note)
	_search = LineEdit.new()
	_search.placeholder_text = tr("OPTIONS_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_list())
	all.add_child(_search)
	_list = ScreenKit.list()
	all.add_child(ScreenKit.scrolling(_list))
	_right_tabs.tab_changed.connect(show_page)
	show_page(Page.DISPLAY)


# The Display page as things are: fullscreen, the window sizes that fit
# the screen (the current one marked), monitors, the UI scale steps that fit
# the window, vsync and frame rate.
func _refresh_display() -> void:
	FOWindow.add_options(source)
	var fullscreen := bool(source.get_value(FOWindow.OPTION_FULLSCREEN))
	_fullscreen.set_pressed_no_signal(fullscreen)
	var screen := DisplayServer.window_get_current_screen()
	var window := get_window().size if is_inside_tree() else Vector2i(1280, 800)
	_window_size.clear()
	var sizes := FOWindow.window_sizes(DisplayServer.screen_get_usable_rect(screen).size)
	if not sizes.has(window):
		sizes.push_back(window)
	for size: Vector2i in sizes:
		_window_size.add_item("%d × %d" % [size.x, size.y])
		_window_size.set_item_metadata(_window_size.item_count - 1, size)
		if size == window:
			_window_size.select(_window_size.item_count - 1)
	_window_size.disabled = fullscreen or not FOWindow.has_window()
	_window_size.tooltip_text = tr("OPTIONS_WINDOW_SIZE_FULLSCREEN") if fullscreen else ""
	_monitor.clear()
	for i in DisplayServer.get_screen_count():
		var area := DisplayServer.screen_get_size(i)
		_monitor.add_item(
			tr("OPTIONS_MONITOR_N").replace("%1%", str(i + 1)) + "  ·  %d × %d" % [area.x, area.y]
		)
	_monitor.select(screen)
	_monitor.get_parent().visible = _monitor.item_count > 1
	var fits := FOUiScale.max_scale_for_window(window)
	for i in SCALE_STEPS.size():
		var too_big: bool = SCALE_STEPS[i] > fits + 0.001
		_scale.set_item_disabled(i + 1, too_big)
		_scale.set_item_tooltip(i + 1, tr("OPTIONS_UI_SCALE_TOO_BIG") if too_big else "")
	_scale.set_item_text(
		0, tr("OPTIONS_UI_SCALE_AUTO_NOW").replace("%1%", str(roundi(FOUi.scale * 100)))
	)
	_vsync.set_pressed_no_signal(bool(source.get_value(FOWindow.OPTION_VSYNC)))
	var cap := int(source.get_value(FOWindow.OPTION_FPS_MAX))
	var limited := bool(source.get_value(FOWindow.OPTION_FPS_LIMITED))
	var at: int = FOWindow.FPS_STEPS.find(cap if limited else 0)
	_fps_cap.select(at if at >= 0 else FOWindow.FPS_STEPS.size() - 1)
	_fps_background.set_pressed_no_signal(bool(source.get_value(FOWindow.OPTION_FPS_BACKGROUND)))
	_fps_shown.set_pressed_no_signal(bool(source.get_value(FOWindow.OPTION_FPS_SHOWN)))


# A page: a scrolling list in the column; returns the list.
func _page(column: VBoxContainer) -> VBoxContainer:
	var list := ScreenKit.list()
	list.add_theme_constant_override("separation", FOUi.tokens.space_3)
	var scroll := ScreenKit.scrolling(list)
	column.add_child(scroll)
	_pages.push_back(scroll)
	return list


# A setting: its name and what it does on the left, \a control on the right.
func _setting(list: Control, title_key: String, description_key: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FOUi.tokens.space_6)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(ScreenKit.label(tr(title_key)))
	if not description_key.is_empty():
		var detail := ScreenKit.label(tr(description_key), "SmallLabel")
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(detail)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if control is OptionButton or control is Button and not control is CheckButton:
		control.custom_minimum_size.x = FOUi.tokens.space_8 * 7
	row.add_child(control)
	list.add_child(row)


func _build_display(list: VBoxContainer) -> void:
	list.add_child(ScreenKit.section(tr("OPTIONS_GROUP_WINDOW")))
	_fullscreen = CheckButton.new()
	_fullscreen.tooltip_text = FOHotkeys.shown("fullscreen")
	_fullscreen.toggled.connect(
		func(on):
			FOWindow.set_fullscreen(on, source)
			_status.text = tr("OPTIONS_SAVED_AUTO")
			_refresh_display()
	)
	_setting(list, "OPTIONS_FULLSCREEN", "OPTIONS_FULLSCREEN_DESC", _fullscreen)
	_window_size = OptionButton.new()
	_window_size.item_selected.connect(
		func(i):
			FOWindow.set_window_size(_window_size.get_item_metadata(i), source)
			_status.text = tr("OPTIONS_SAVED_AUTO")
			_refresh_display.call_deferred()
	)
	_setting(list, "OPTIONS_WINDOW_SIZE", "OPTIONS_WINDOW_SIZE_DESC", _window_size)
	_monitor = OptionButton.new()
	_monitor.item_selected.connect(func(i): FOWindow.set_monitor(i, source))
	_setting(list, "OPTIONS_MONITOR", "", _monitor)
	_scale = OptionButton.new()
	_scale.add_item(tr("OPTIONS_UI_SCALE_AUTO"))
	for step in SCALE_STEPS:
		_scale.add_item("%d%%" % roundi(step * 100.0))
	_scale.item_selected.connect(_on_scale_selected)
	_setting(list, "OPTIONS_UI_SCALE", "OPTIONS_UI_SCALE_DESC", _scale)
	list.add_child(ScreenKit.section(tr("OPTIONS_GROUP_FRAME_RATE")))
	_vsync = CheckButton.new()
	_vsync.toggled.connect(func(on): _apply(FOWindow.OPTION_VSYNC, on))
	_setting(list, "OPTIONS_VSYNC", "OPTIONS_VSYNC_DESC", _vsync)
	_fps_cap = OptionButton.new()
	for cap: int in FOWindow.FPS_STEPS:
		_fps_cap.add_item(str(cap) if cap > 0 else tr("OPTIONS_FPS_UNLIMITED"))
	_fps_cap.item_selected.connect(
		func(i):
			var cap: int = FOWindow.FPS_STEPS[i]
			if cap > 0:
				source.set_value(FOWindow.OPTION_FPS_MAX, cap)
			_apply(FOWindow.OPTION_FPS_LIMITED, cap > 0)
	)
	_setting(list, "OPTIONS_FPS_CAP", "OPTIONS_FPS_CAP_DESC", _fps_cap)
	_fps_background = CheckButton.new()
	_fps_background.toggled.connect(func(on): _apply(FOWindow.OPTION_FPS_BACKGROUND, on))
	_setting(list, "OPTIONS_FPS_BACKGROUND", "OPTIONS_FPS_BACKGROUND_DESC", _fps_background)
	_fps_shown = CheckButton.new()
	_fps_shown.toggled.connect(func(on): _apply(FOWindow.OPTION_FPS_SHOWN, on))
	_setting(list, "OPTIONS_FPS_SHOWN", "", _fps_shown)


func _build_interface(list: VBoxContainer) -> void:
	_theme = OptionButton.new()
	for theme_name in THEMES:
		_theme.add_item(tr("OPTIONS_THEME_" + theme_name.to_upper()))
	_theme.item_selected.connect(func(i): _apply(FOUi.OPTION_THEME, THEMES[i]))
	_setting(list, "OPTIONS_UI_THEME", "", _theme)
	_language = OptionButton.new()
	_language.item_selected.connect(_on_language_selected)
	_setting(list, "OPTIONS_LANGUAGE_NAME", "", _language)
	_motion = CheckButton.new()
	_motion.tooltip_text = tr("OPTIONS_DB_UI_REDUCE_MOTION")
	_motion.toggled.connect(func(on): _apply(FOUi.OPTION_REDUCE_MOTION, on))
	_setting(list, "OPTIONS_REDUCE_MOTION", "OPTIONS_REDUCE_MOTION_DESC", _motion)
	for entry in LOOK:
		var look := CheckButton.new()
		look.toggled.connect(func(on): _apply(entry[0], on))
		_setting(list, entry[1], entry[1] + "_DESC", look)
		_look.push_back(look)
	var hints := Button.new()
	hints.text = tr("HINT_RESET")
	hints.pressed.connect(reset_hints)
	_setting(list, "OPTIONS_HINTS", "", hints)


# Master volume, then music and sounds: a switch and a volume each. Volumes
# change as the slider moves (sounds play a sample as it is let go) and are
# saved when it is let go.
func _build_sound(list: VBoxContainer) -> void:
	_master = _volume_slider(FOAudio.OPTION_MASTER_VOLUME, "")
	_setting(list, "OPTIONS_MASTER_VOLUME", "", _master.get_parent())
	for entry in AUDIO:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", FOUi.tokens.space_3)
		var on := CheckButton.new()
		box.add_child(on)
		var volume := _volume_slider(entry[1], "click" if entry[1].contains("effects") else "")
		box.add_child(volume.get_parent())
		on.toggled.connect(
			func(pressed: bool):
				volume.editable = pressed
				_apply(entry[0], pressed)
		)
		_setting(list, entry[2], entry[2] + "_DESC", box)
		_audio.push_back([on, volume])


# A 0-255 volume slider for \a option with its percentage beside it, in a
# box; \a sample plays as it is let go.
func _volume_slider(option: String, sample: String) -> HSlider:
	var box := HBoxContainer.new()
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 255
	volume.step = 1
	volume.custom_minimum_size.x = FOUi.tokens.space_8 * 6
	volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume.tooltip_text = tr("OPTIONS_VOLUME")
	box.add_child(volume)
	var percent := ScreenKit.label("", "SecondaryLabel")
	percent.custom_minimum_size.x = FOUi.tokens.space_8 + FOUi.tokens.space_4
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(percent)
	var show := func(v: float): percent.text = "%d%%" % roundi(v / 2.55)
	volume.value_changed.connect(show)
	volume.changed.connect(func(): show.call(volume.value))
	volume.value_changed.connect(func(v): source.set_value(option, int(v)))
	volume.drag_ended.connect(
		func(_changed):
			_apply(option, int(volume.value))
			if not sample.is_empty():
				FOAudio.play(sample)
	)
	show.call(volume.value)
	return volume


## Show \a page (a Page).
func show_page(page: int) -> void:
	if _right_tabs.current_tab != page:
		_right_tabs.current_tab = page  # calls back here
		return
	for i in _pages.size():
		_pages[i].visible = i == page
	_capturing = ""
	_refresh_hotkeys()


# The Gameplay page: GAMEPLAY's options that exist (some only in a game),
# under their group captions, in plain words.
func _refresh_gameplay() -> void:
	ScreenKit.clear(_gameplay_list)
	for group: Array in GAMEPLAY:
		var rows: Array = group[1].filter(func(entry): return source.exists(entry[0]))
		if rows.is_empty():
			continue
		_gameplay_list.add_child(ScreenKit.section(tr(group[0])))
		for entry: Array in rows:
			_gameplay_list.add_child(_option_row(entry[0], tr(entry[1] + "_DESC"), tr(entry[1])))


# One row per shortcut: what it does, its key (click to change), reset to
# the default, clear.
func _refresh_hotkeys() -> void:
	ScreenKit.clear(_hotkey_list)
	for entry in FOHotkeys.HOTKEYS:
		var hotkey: String = entry[0]
		var row := HBoxContainer.new()
		var label := ScreenKit.label(tr(entry[1]))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var key := Button.new()
		key.custom_minimum_size.x = 180
		key.set_meta("hotkey", hotkey)
		var binding: String = FOHotkeys.binding(hotkey)
		if hotkey == _capturing:
			key.text = tr("OPTIONS_HOTKEY_PRESS")
			key.theme_type_variation = "PrimaryButton"
		else:
			key.text = (
				FOHotkeys.display(binding) if not binding.is_empty() else tr("OPTIONS_HOTKEY_NONE")
			)
		key.tooltip_text = tr("OPTIONS_HOTKEY_CHANGE")
		key.pressed.connect(
			func():
				_capturing = hotkey
				_refresh_hotkeys()
		)
		row.add_child(key)
		var reset := ScreenKit.small_button(
			"↺", "OPTIONS_RESET", binding != FOHotkeys.default_binding(hotkey)
		)
		reset.pressed.connect(func(): set_hotkey(hotkey, FOHotkeys.default_binding(hotkey)))
		row.add_child(reset)
		var clear := ScreenKit.small_button("✕", "OPTIONS_HOTKEY_CLEAR", not binding.is_empty())
		clear.pressed.connect(func(): set_hotkey(hotkey, ""))
		row.add_child(clear)
		_hotkey_list.add_child(row)


func _hotkey_label(hotkey: String) -> String:
	for entry in FOHotkeys.HOTKEYS:
		if entry[0] == hotkey:
			return tr(entry[1])
	return hotkey


func _refresh_list() -> void:
	ScreenKit.clear(_list)
	var needle := _search.text.strip_edges().to_lower()
	var shown := 0
	var section := ""
	# By section, in their order within each.
	var options := Array(source.find(""))
	var order := {}
	for i in options.size():
		order[options[i]] = i
	options.sort_custom(
		func(a: String, b: String):
			var by_section := option_section(a).naturalnocasecmp_to(option_section(b))
			return by_section < 0 if by_section != 0 else order[a] < order[b]
	)
	for option: String in options:
		if _is_hidden(option):
			continue
		var description := tr(source.get_description(option))
		if not needle.is_empty():
			var haystack: String = option + " " + option_title(option) + " " + description
			if not haystack.to_lower().contains(needle):
				continue
		if shown >= MAX_LISTED:
			_list.add_child(ScreenKit.label(tr("OPTIONS_REFINE_SEARCH"), "SecondaryLabel"))
			break
		# Options under a heading for the first part of their names.
		if option_section(option) != section:
			section = option_section(option)
			_list.add_child(ScreenKit.section(section))
		_list.add_child(_option_row(option, description))
		shown += 1
	if shown == 0:
		_list.add_child(ScreenKit.label(tr("PEDIA_NO_RESULTS"), "SecondaryLabel"))


## A readable title for \a option: its name after the section, without
## a trailing "enabled" or "shown" ("save.auto.hostless.enabled" ->
## "Auto hostless").
static func option_title(option: String) -> String:
	var parts := Array(option.split("."))
	if parts.size() > 1:
		parts.pop_front()
	if parts.size() > 1 and parts.back() in ["enabled", "shown"]:
		parts.pop_back()
	return _readable(" ".join(parts))


## The heading \a option is listed under: the first part of its name;
## names of one part go under "General".
static func option_section(option: String) -> String:
	if not option.contains("."):
		return TranslationServer.translate("OPTIONS_SECTION_GENERAL")
	return _readable(option.get_slice(".", 0))


# \a words with spaces for - and _, the first capitalised, acronyms in
# capitals.
static func _readable(words: String) -> String:
	var result := PackedStringArray()
	for word in words.replace("-", " ").replace("_", " ").split(" ", false):
		result.push_back(word.to_upper() if word in ACRONYMS else word)
	var text := " ".join(result)
	return text.left(1).to_upper() + text.substr(1)


func _option_row(option: String, description: String, title_text := "") -> Control:
	var row := HBoxContainer.new()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var title := ScreenKit.label(title_text if not title_text.is_empty() else option_title(option))
	# The option's own name, as the command line and config file know it.
	title.tooltip_text = option
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	text.add_child(title)
	var detail := ScreenKit.label(description, "SmallLabel")
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(detail)
	var editor := _editor(option)
	editor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(editor)
	var reset := ScreenKit.small_button("↺", "OPTIONS_RESET", not source.is_default(option))
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func(): _reset(option))
	row.add_child(reset)
	return row


# Editor matching the option's type; invalid values revert and show why.
func _editor(option: String) -> Control:
	var value: Variant = source.get_value(option)
	if option == GameShell.OPTION_NEW_FLEET_STANCE:
		return _stance_editor(option, str(value))
	match typeof(value):
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(func(on): _apply(option, on))
			return check
		TYPE_INT, TYPE_FLOAT:
			var spin := SpinBox.new()
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.step = 1.0 if typeof(value) == TYPE_INT else 0.01
			spin.value = value
			spin.custom_minimum_size.x = 120
			spin.value_changed.connect(
				func(v): _apply(option, int(v) if typeof(value) == TYPE_INT else v, spin)
			)
			return spin
		_:
			var edit := LineEdit.new()
			edit.text = str(value)
			edit.custom_minimum_size.x = 200
			edit.text_submitted.connect(func(t): _apply(option, t, edit))
			return edit


# The new fleets' stance, by name (the fleet menu offers the same).
func _stance_editor(option: String, value: String) -> OptionButton:
	var pick := OptionButton.new()
	for stance: String in FleetPanel.NEW_FLEET_STANCES:
		pick.add_item(tr("FW_AUTO") if stance == "auto" else tr("FW_" + stance.to_upper()))
		if stance == value:
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(i): _apply(option, FleetPanel.NEW_FLEET_STANCES[i]))
	return pick


# Set \a option to \a value and save it; an invalid value puts \a editor
# back and says so.
func _apply(option: String, value: Variant, editor: Control = null) -> void:
	if source.set_value(option, value):
		_status.text = tr("OPTIONS_SAVED_AUTO") if source.commit() else tr("OPTIONS_SAVE_FAILED")
		return
	_status.text = tr("OPTIONS_INVALID").replace("%1%", option)
	# Put the editor back to the stored value.
	if editor is SpinBox:
		editor.set_value_no_signal(source.get_value(option))
	elif editor is LineEdit:
		editor.text = str(source.get_value(option))


# Every stringtable's language, by its name in that language's own terms
# where Godot knows it.
func _fill_languages() -> void:
	_language.clear()
	var current: String = source.get_language()
	for code in source.get_languages():
		var name := TranslationServer.get_locale_name(code)
		_language.add_item("%s (%s)" % [name, code] if not name.is_empty() else code)
		_language.set_item_metadata(_language.item_count - 1, code)
		if code == current:
			_language.select(_language.item_count - 1)


func _on_language_selected(index: int) -> void:
	var code: String = _language.get_item_metadata(index)
	if source.set_language(code):
		_status.text = tr("OPTIONS_LANGUAGE_CHANGED")
	else:
		_status.text = tr("OPTIONS_INVALID").replace("%1%", code)


func _reset(option: String) -> void:
	source.reset_to_default(option)
	refresh()


func _on_scale_selected(index: int) -> void:
	var setting := "auto" if index == 0 else str(SCALE_STEPS[index - 1])
	_apply(FOUi.OPTION_SCALE, setting)


func _scale_index(setting: String) -> int:
	if not setting.is_valid_float():
		return 0
	var value := setting.to_float()
	for i in SCALE_STEPS.size():
		if is_equal_approx(SCALE_STEPS[i], value):
			return i + 1
	return 0


# Not under Advanced: internal, edited elsewhere, or on another page.
static func _is_hidden(option: String) -> bool:
	for prefix in HIDDEN_PREFIXES:
		if option.begins_with(prefix):
			return true
	for entry: Array in LOOK:
		if entry[0] == option:
			return true
	for group: Array in GAMEPLAY:
		for entry: Array in group[1]:
			if entry[0] == option:
				return true
	return false
