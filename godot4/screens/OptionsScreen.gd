class_name OptionsScreen
extends PanelContainer
## Options: the client's interface settings (UI scale, theme, reduced
## motion) as proper controls that apply at once, and every other option as
## a searchable list with a typed editor, validation feedback and reset.
## Save writes them to config.xml; changes apply immediately either way.

signal close_requested

const SCALE_STEPS := [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
const THEMES := ["default", "high_contrast"]
const MAX_LISTED := 120
## Internal or launch-only options that make no sense to edit in game.
## The interface options have their own controls on the left.
const HIDDEN_PREFIXES := [
	"version",
	"misc.server-local-binary",
	"resource.path",
	"setup.seed",
	"ui.scale",
	"ui.theme",
	"ui.reduce-motion",
	"audio.music.enabled",
	"audio.music.volume",
	"audio.effects.enabled",
	"audio.effects.volume",
	"ui.hotkey.godot.",
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
## Per AUDIO row: [switch, volume slider].
var _audio: Array = []
var _search: LineEdit
var _list: VBoxContainer
var _right_tabs: TabBar
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


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var scale_setting := str(source.get_value(FOUi.OPTION_SCALE))
	_scale.select(_scale_index(scale_setting))
	_theme.select(maxi(0, THEMES.find(str(source.get_value(FOUi.OPTION_THEME)))))
	_motion.set_pressed_no_signal(bool(source.get_value(FOUi.OPTION_REDUCE_MOTION)))
	for i in AUDIO.size():
		if source.exists(AUDIO[i][0]):
			_audio[i][0].set_pressed_no_signal(bool(source.get_value(AUDIO[i][0])))
			_audio[i][1].set_value_no_signal(float(source.get_value(AUDIO[i][1])))
			_audio[i][1].editable = _audio[i][0].button_pressed
	_status.text = ""
	_capturing = ""
	_refresh_list()
	_refresh_hotkeys()


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_8)
	margin.add_child(columns)

	var interface := VBoxContainer.new()
	interface.custom_minimum_size.x = 360
	columns.add_child(interface)
	_status = ScreenKit.header(interface, "OPTIONS_TITLE", close_requested.emit)
	interface.add_child(ScreenKit.label(tr("OPTIONS_INTERFACE"), "TitleLabel"))
	var grid := GridContainer.new()
	grid.columns = 2
	interface.add_child(grid)

	grid.add_child(ScreenKit.label(tr("OPTIONS_UI_SCALE"), "SecondaryLabel"))
	_scale = OptionButton.new()
	_scale.add_item(tr("OPTIONS_UI_SCALE_AUTO"))
	for step in SCALE_STEPS:
		_scale.add_item("%d%%" % roundi(step * 100.0))
	_scale.item_selected.connect(_on_scale_selected)
	grid.add_child(_scale)

	grid.add_child(ScreenKit.label(tr("OPTIONS_UI_THEME"), "SecondaryLabel"))
	_theme = OptionButton.new()
	for theme_name in THEMES:
		_theme.add_item(tr("OPTIONS_THEME_" + theme_name.to_upper()))
	_theme.item_selected.connect(func(i): _apply(FOUi.OPTION_THEME, THEMES[i]))
	grid.add_child(_theme)

	grid.add_child(ScreenKit.label(tr("OPTIONS_REDUCE_MOTION"), "SecondaryLabel"))
	_motion = CheckButton.new()
	_motion.tooltip_text = tr("OPTIONS_DB_UI_REDUCE_MOTION")
	_motion.toggled.connect(func(on): _apply(FOUi.OPTION_REDUCE_MOTION, on))
	grid.add_child(_motion)

	# Music and sounds: a switch and a volume slider each.
	interface.add_child(ScreenKit.label(tr("OPTIONS_AUDIO"), "TitleLabel"))
	var audio_grid := GridContainer.new()
	audio_grid.columns = 3
	interface.add_child(audio_grid)
	for entry in AUDIO:
		audio_grid.add_child(ScreenKit.label(tr(entry[2]), "SecondaryLabel"))
		var on := CheckButton.new()
		audio_grid.add_child(on)
		var volume := HSlider.new()
		volume.min_value = 0
		volume.max_value = 255
		volume.step = 1
		volume.custom_minimum_size.x = 140
		volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		volume.tooltip_text = tr("OPTIONS_VOLUME")
		audio_grid.add_child(volume)
		on.toggled.connect(
			func(pressed: bool):
				volume.editable = pressed
				_apply(entry[0], pressed)
		)
		volume.drag_ended.connect(func(_changed): _apply(entry[1], int(volume.value)))
		_audio.push_back([on, volume])

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	interface.add_child(spacer)
	var save := Button.new()
	save.text = tr("SAVE")
	save.theme_type_variation = "PrimaryButton"
	save.tooltip_text = tr("OPTIONS_SAVE_DESC")
	save.pressed.connect(_on_save_pressed)
	interface.add_child(save)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_right_tabs = TabBar.new()
	_right_tabs.add_tab(tr("OPTIONS_ALL"))
	_right_tabs.add_tab(tr("OPTIONS_PAGE_HOTKEYS"))
	right.add_child(_right_tabs)
	var all := VBoxContainer.new()
	all.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(all)
	_all_options = all
	_hotkey_list = ScreenKit.list()
	_hotkeys = ScreenKit.scrolling(_hotkey_list)
	_hotkeys.visible = false
	right.add_child(_hotkeys)
	_right_tabs.tab_changed.connect(
		func(tab: int):
			_all_options.visible = tab == 0
			_hotkeys.visible = tab == 1
			_capturing = ""
			_refresh_hotkeys()
	)
	_search = LineEdit.new()
	_search.placeholder_text = tr("OPTIONS_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_list())
	all.add_child(_search)
	_list = ScreenKit.list()
	all.add_child(ScreenKit.scrolling(_list))


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
			key.text = binding if not binding.is_empty() else tr("OPTIONS_HOTKEY_NONE")
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
	for option: String in source.find(""):
		if _is_hidden(option):
			continue
		var description := tr(source.get_description(option))
		if not needle.is_empty():
			var haystack: String = (option + " " + description).to_lower()
			if not haystack.contains(needle):
				continue
		if shown >= MAX_LISTED:
			_list.add_child(ScreenKit.label(tr("OPTIONS_REFINE_SEARCH"), "SecondaryLabel"))
			break
		_list.add_child(_option_row(option, description))
		shown += 1
	if shown == 0:
		_list.add_child(ScreenKit.label(tr("PEDIA_NO_RESULTS"), "SecondaryLabel"))


func _option_row(option: String, description: String) -> Control:
	var row := HBoxContainer.new()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(ScreenKit.label(option))
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


func _apply(option: String, value: Variant, editor: Control = null) -> void:
	if source.set_value(option, value):
		_status.text = tr("OPTIONS_APPLIED").replace("%1%", option)
		return
	_status.text = tr("OPTIONS_INVALID").replace("%1%", option)
	# Put the editor back to the stored value.
	if editor is SpinBox:
		editor.set_value_no_signal(source.get_value(option))
	elif editor is LineEdit:
		editor.text = str(source.get_value(option))


func _reset(option: String) -> void:
	source.reset_to_default(option)
	refresh()


func _on_scale_selected(index: int) -> void:
	var setting := "auto" if index == 0 else str(SCALE_STEPS[index - 1])
	_apply(FOUi.OPTION_SCALE, setting)


func _on_save_pressed() -> void:
	_status.text = tr("OPTIONS_SAVED") if source.commit() else tr("OPTIONS_SAVE_FAILED")


func _scale_index(setting: String) -> int:
	if not setting.is_valid_float():
		return 0
	var value := setting.to_float()
	for i in SCALE_STEPS.size():
		if is_equal_approx(SCALE_STEPS[i], value):
			return i + 1
	return 0


static func _is_hidden(option: String) -> bool:
	for prefix in HIDDEN_PREFIXES:
		if option.begins_with(prefix):
			return true
	return false
