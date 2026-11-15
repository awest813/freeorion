class_name SaveLoadScreen
extends PanelContainer
## Saved games as cards (empire, turn, time), newest first. In "load" mode
## the chosen save is loaded; in "save" mode a name is entered (picking a
## save means overwriting it) and the save is requested from the server.

signal close_requested
## Load mode: the game in \a path is being loaded.
signal load_started(path: String)

var source: Variant = SavesSource.new()
var mode := "load"
## Suggested name in save mode (e.g. empire and turn).
var suggested_name := ""

var _title: Label
var _status: Label
var _list: VBoxContainer
var _name: LineEdit
var _action: Button
var _selected_path := ""
var _saves: Array = []


func _init() -> void:
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	_title.text = tr("GAME_MENU_SAVE" if mode == "save" else "GAME_MENU_LOAD")
	_action.text = tr("SAVES_SAVE" if mode == "save" else "SAVES_LOAD")
	_name.visible = mode == "save"
	_name.text = suggested_name
	_selected_path = ""
	_status.text = ""
	_saves = source.list_saves()
	ScreenKit.clear(_list)
	for save: Dictionary in _saves:
		_list.add_child(_save_card(save))
	if _saves.is_empty():
		_list.add_child(ScreenKit.label(tr("SAVES_EMPTY"), "SecondaryLabel"))
	_update_action()


## Report that the server wrote \a filename (FreeOrionNode.save_completed).
func on_save_completed(filename: String) -> void:
	_status.text = tr("SAVES_SAVED").replace("%1%", filename.get_file())
	if visible:
		var status := _status.text
		refresh()
		_status.text = status


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 720
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = ScreenKit.label("", "HeadingLabel")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := ScreenKit.small_button("✕", "PANEL_CLOSE")
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	_list = ScreenKit.list()
	box.add_child(ScreenKit.scrolling(_list))
	_status = ScreenKit.label("", "SecondaryLabel")
	box.add_child(_status)
	var footer := HBoxContainer.new()
	box.add_child(footer)
	_name = LineEdit.new()
	_name.placeholder_text = tr("SAVES_NAME")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(_t): _update_action())
	_name.text_submitted.connect(func(_t): _on_action())
	footer.add_child(_name)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_action = Button.new()
	_action.theme_type_variation = "PrimaryButton"
	_action.pressed.connect(_on_action)
	footer.add_child(_action)
	_name.visibility_changed.connect(func(): spacer.visible = not _name.visible)


func _save_card(save: Dictionary) -> Control:
	var card := Button.new()
	card.toggle_mode = true
	card.custom_minimum_size.y = FOUi.tokens.icon_large + FOUi.tokens.space_3
	card.set_meta("path", save.get("path", ""))
	card.pressed.connect(_select.bind(save))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var swatch := ColorRect.new()
	swatch.color = save.get("color", Color.WHITE)
	swatch.custom_minimum_size = Vector2(FOUi.tokens.space_2, 0)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(
		ScreenKit.label(
			(
				"%s · %s"
				% [
					save.get("empire", ""),
					tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(save.get("turn", 0)))
				]
			)
		)
	)
	text.add_child(
		ScreenKit.label(
			"%s · %s" % [save.get("file", ""), format_time(save.get("time", ""))], "SmallLabel"
		)
	)
	return card


func _select(save: Dictionary) -> void:
	_selected_path = save.get("path", "")
	for card: Button in _list.get_children().filter(func(c): return c is Button):
		card.set_pressed_no_signal(card.get_meta("path") == _selected_path)
	if mode == "save":
		_name.text = str(save.get("file", "")).get_basename()
		_status.text = tr("SAVES_OVERWRITE")
	_update_action()
	if mode == "load":
		_action.grab_focus()


func _update_action() -> void:
	if mode == "save":
		_action.disabled = _name.text.strip_edges().is_empty()
	else:
		_action.disabled = _selected_path.is_empty()


func _on_action() -> void:
	if _action.disabled:
		return
	if mode == "save":
		var path: String = source.save_game(_name.text.strip_edges())
		_status.text = tr("SAVES_SAVING") if not path.is_empty() else tr("SAVES_FAILED")
	elif source.load_game(_selected_path):
		load_started.emit(_selected_path)
	else:
		_status.text = tr("SAVES_LOAD_FAILED")


## "2026-11-15T10:42:07Z" -> "2026-11-15 10:42".
static func format_time(iso: String) -> String:
	if iso.length() < 16:
		return iso
	return iso.substr(0, 10) + " " + iso.substr(11, 5)
