class_name SaveLoadScreen
extends PanelContainer
## Saved games as cards (empire, turn, time), newest first. In "load" mode
## the chosen save is loaded; in "save" mode a name is entered (picking a
## save means overwriting it) and the save is requested from the server.

signal close_requested
## Load mode: the game in \a path is being loaded (or, with defer_load, was
## chosen to be loaded).
signal load_started(path: String)

## Sort orders: key, label key.
const SORTS := [
	["newest", "SAVES_SORT_NEWEST"],
	["oldest", "SAVES_SORT_OLDEST"],
	["turn", "SAVES_SORT_TURN"],
	["empire", "SAVES_SORT_EMPIRE"],
	["file", "SAVES_SORT_FILE"],
	["systems", "SAVES_SORT_SYSTEMS"],
]

var source: Variant = SavesSource.new()
var mode := "load"
## Suggested name in save mode (e.g. empire and turn).
var suggested_name := ""
## Load mode: only emit load_started and let the owner load, e.g. in game,
## where the running game has to end first.
var defer_load := false

var _title: Label
var _status: Label
var _list: VBoxContainer
var _name: LineEdit
var _action: Button
var _delete: Button
var _selected_path := ""
var _saves: Array = []
var _sort: OptionButton


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	# Saving picks a save to overwrite; autosaves are the game's own.
	if mode == "save":
		_saves = _saves.filter(func(save): return not save.get("auto", false))
	sort_saves(_saves, SORTS[maxi(_sort.selected, 0)][0])
	ScreenKit.clear(_list)
	for save: Dictionary in _saves:
		_list.add_child(_save_card(save))
	if _saves.is_empty():
		_list.add_child(ScreenKit.label(tr("SAVES_EMPTY"), "SecondaryLabel"))
	_update_action()


## Sort \a saves by \a key (a SORTS key), as the GG save list's columns.
static func sort_saves(saves: Array, key: String) -> void:
	saves.sort_custom(
		func(a, b):
			match key:
				"oldest":
					return str(a.get("time", "")) < str(b.get("time", ""))
				"turn":
					return a.get("turn", 0) > b.get("turn", 0)
				"empire":
					return (
						str(a.get("empire", "")).naturalnocasecmp_to(str(b.get("empire", ""))) < 0
					)
				"file":
					return str(a.get("file", "")).naturalnocasecmp_to(str(b.get("file", ""))) < 0
				"systems":
					return a.get("systems", 0) > b.get("systems", 0)
			return str(a.get("time", "")) > str(b.get("time", ""))
	)


## The galaxy a save is in, in one line: systems, shape, empires, seed.
static func galaxy_summary(save: Dictionary) -> String:
	if not save.has("systems"):
		return ""
	return (
		TranslationServer
		. translate("SAVES_GALAXY")
		. replace("%1%", str(save.get("systems", 0)))
		. replace("%2%", str(save.get("shape", "")))
		. replace("%3%", str(save.get("empires", 0)))
		. replace("%4%", str(save.get("humans", 0)))
	)


## Every detail of a save's galaxy (GG's columns), for its tooltip.
static func galaxy_details(save: Dictionary) -> String:
	var t := TranslationServer.translate
	var lines: PackedStringArray = [
		"%s: %s" % [t.call("SAVES_PLAYER"), save.get("player", "")],
		"%s: %s" % [t.call("SAVES_VERSION"), save.get("version", "")],
	]
	for entry in [
		["seed", "GSETUP_SEED"],
		["age", "GSETUP_AGE"],
		["starlanes", "GSETUP_STARLANE_FREQ"],
		["planets", "GSETUP_PLANET_DENSITY"],
		["specials", "GSETUP_SPECIALS_FREQ"],
		["monsters", "GSETUP_MONSTER_FREQ"],
		["natives", "GSETUP_NATIVE_FREQ"],
		["ai_aggression", "GSETUP_AI_AGGR"],
	]:
		if save.has(entry[0]):
			lines.push_back("%s: %s" % [t.call(entry[1]), save[entry[0]]])
	return "\n".join(lines)


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
	_sort = OptionButton.new()
	for entry in SORTS:
		_sort.add_item(tr(entry[1]))
	_sort.tooltip_text = tr("SAVES_SORT")
	_sort.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sort.item_selected.connect(func(_i): refresh())
	header.add_child(_sort)
	header.move_child(_sort, 1)
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
	_delete = Button.new()
	_delete.text = tr("SAVES_DELETE")
	_delete.theme_type_variation = "GhostButton"
	_delete.pressed.connect(_on_delete)
	footer.add_child(_delete)
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
	var details := "%s · %s" % [save.get("file", ""), format_time(save.get("time", ""))]
	if save.get("auto", false):
		details = tr("SAVES_AUTOSAVE") + " · " + details
	text.add_child(ScreenKit.label(details, "SmallLabel"))
	var galaxy := galaxy_summary(save)
	if not galaxy.is_empty():
		text.add_child(ScreenKit.label(galaxy, "SmallLabel"))
		card.custom_minimum_size.y += FOUi.tokens.font_size_small + 4
	card.tooltip_text = galaxy_details(save)
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


# Deleting asks first: a save can't be got back.
func _on_delete() -> void:
	if _selected_path.is_empty():
		return
	var path := _selected_path
	(
		FODialog
		. open_on(
			self,
			tr("SAVES_DELETE"),
			tr("SAVES_DELETE_CONFIRM").replace("%1%", path.get_file()),
			[
				[tr("SAVES_DELETE"), "DangerButton", _delete_save.bind(path)],
				[tr("CANCEL"), "GhostButton"],
			]
		)
	)


func _delete_save(path: String) -> void:
	var deleted: bool = source.delete_save(path)
	refresh()
	_status.text = tr("SAVES_DELETED" if deleted else "SAVES_DELETE_FAILED").replace(
		"%1%", path.get_file()
	)


func _update_action() -> void:
	if mode == "save":
		_action.disabled = _name.text.strip_edges().is_empty()
	else:
		_action.disabled = _selected_path.is_empty()
	_delete.disabled = _selected_path.is_empty()


func _on_action() -> void:
	if _action.disabled:
		return
	if mode == "save":
		var path: String = source.save_game(_name.text.strip_edges())
		_status.text = tr("SAVES_SAVING") if not path.is_empty() else tr("SAVES_FAILED")
	elif defer_load or source.load_game(_selected_path):
		load_started.emit(_selected_path)
	else:
		_status.text = tr("SAVES_LOAD_FAILED")


## "2026-11-15T10:42:07Z" -> "2026-11-15 10:42".
static func format_time(iso: String) -> String:
	if iso.length() < 16:
		return iso
	return iso.substr(0, 10) + " " + iso.substr(11, 5)
