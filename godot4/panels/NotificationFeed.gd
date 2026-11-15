class_name NotificationFeed
extends PanelContainer
## A turn's situation reports as a collapsible list of rich-text entries;
## ‹ and › step back through earlier turns. Links (planets, systems, fleets,
## techs, ...) emit link_activated.
## Follows the running game unless follow_game is false; show_entries() then
## drives it directly (tests, previews).
##
## As in the GG sitrep panel, whole types of report can be hidden (☰, kept
## in option ui.map.sitrep.hidden.stringlist), and right-clicking a report
## hides that one for some turns or for the rest of the session;
## double-clicking dismisses it. Reports come in GG's order of importance;
## ‹ › skip turns with nothing to show, and ⇥ goes back to the latest turn.

signal link_activated(kind: String, arg: String)

## Right-click menu ids.
enum { MENU_SNOOZE_5, MENU_SNOOZE_10, MENU_SNOOZE_FOREVER, MENU_HIDE_TYPE, MENU_COPY }

const WIDTH := 380
const MAX_HEIGHT := 320
## The GG client's option for hidden report types (labels, space-separated).
const OPTION_HIDDEN := "ui.map.sitrep.hidden.stringlist"
## Snoozed "for good": until this turn.
const FOREVER := 1 << 30

var follow_game := true
## turn -> its entries, for stepping through history; the game by default.
var entries_provider := func(turn: int) -> Array: return FOUniverse.get_sitreps(turn)
## Hidden report types: label -> true.
var hidden_labels := {}

var _header: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _entries: Array = []
var _turn := 0
var _latest_turn := 0
var _prev: Button
var _next: Button
var _filter: Button
var _latest: Button
## Report types seen on any turn: label -> true.
var _seen_labels := {}
## Snoozed reports: text -> [first turn, last turn].
var _snoozed := {}
var _all_entries: Array = []
var _menu: PopupMenu


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "OverlayPanel"
	custom_minimum_size.x = WIDTH
	visible = false
	_build()


func _ready() -> void:
	_load_hidden_labels()
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		return
	GlobalFreeOrionNode.start_game.connect(_refresh_from_game.unbind(1))
	GlobalFreeOrionNode.turn_update.connect(_refresh_from_game)
	if GlobalFreeOrionNode.get_current_turn() >= 1:
		_refresh_from_game()


## Show \a entries ({text, icon, label}) for the latest turn \a turn;
## hidden when empty.
func show_entries(entries: Array, turn: int) -> void:
	_latest_turn = turn
	_show(entries, turn)


## Show the reports of earlier turn \a turn (clamped to 1..latest).
func show_turn(turn: int) -> void:
	turn = clampi(turn, 1, maxi(1, _latest_turn))
	_show(entries_provider.call(turn), turn)


func _show(entries: Array, turn: int) -> void:
	var was_visible := visible
	entries = sorted_by_importance(entries)
	for entry: Dictionary in entries:
		if not str(entry.get("label", "")).is_empty():
			_seen_labels[entry["label"]] = true
	_all_entries = entries
	_entries = entries.filter(func(e): return not is_hidden(e, turn))
	entries = _entries
	_turn = turn
	# Browsing history keeps the feed even on a quiet turn.
	visible = not entries.is_empty() or turn != _latest_turn
	for child in _list.get_children():
		child.queue_free()
	for entry: Dictionary in entries:
		_list.add_child(_entry_row(entry))
	_update_header()
	if visible and not was_visible:
		FOUi.fade_in(self)


## \a entries in GG's order of importance (FUNCTIONAL_SITREP_PRIORITY_ORDER),
## types it doesn't name last; the order within a type is kept.
static func sorted_by_importance(entries: Array) -> Array:
	var order := {}
	var names := (
		TranslationServer
		. translate("FUNCTIONAL_SITREP_PRIORITY_ORDER")
		. replace("\n", " ")
		. replace("\t", " ")
		. split(" ", false)
	)
	for i in names.size():
		order[names[i].strip_edges()] = i
	var indexed := []
	for i in entries.size():
		indexed.push_back([order.get(entries[i].get("label", ""), names.size()), i, entries[i]])
	indexed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return indexed.map(func(e): return e[2])


## The nearest turn from the shown one in \a direction (1 or -1) with a
## report to show, or the last one tried at the ends.
func step_turn(direction: int) -> void:
	var turn := _turn + direction
	while turn > 1 and turn < _latest_turn:
		var shown: Array = entries_provider.call(turn).filter(
			func(e): return not is_hidden(e, turn)
		)
		if not shown.is_empty():
			break
		turn += direction
	show_turn(turn)


## Whether \a entry is left out on \a turn: its type hidden, or snoozed.
func is_hidden(entry: Dictionary, turn: int) -> bool:
	if hidden_labels.has(entry.get("label", "")):
		return true
	var span: Array = _snoozed.get(entry.get("text", ""), [])
	return not span.is_empty() and turn >= span[0] and turn <= span[1]


## Hide report type \a label (true) or show it again; saved in the options.
func set_label_hidden(label: String, hidden: bool) -> void:
	if label.is_empty():
		return
	if hidden:
		hidden_labels[label] = true
	else:
		hidden_labels.erase(label)
	_save_hidden_labels()
	_show(_all_entries, _turn)


## Hide reports with \a entry's text for \a turns turns from this one.
func snooze(entry: Dictionary, turns: int) -> void:
	var last := FOREVER if turns <= 0 else _turn + turns - 1
	_snoozed[entry.get("text", "")] = [_turn, last]
	_show(_all_entries, _turn)


## Show every snoozed report again.
func clear_snoozed() -> void:
	_snoozed.clear()
	_show(_all_entries, _turn)


func _load_hidden_labels() -> void:
	hidden_labels.clear()
	if not Engine.has_singleton("FOOptions"):
		return
	var options := Engine.get_singleton("FOOptions")
	options.add_option(OPTION_HIDDEN, "OPTIONS_DB_HIDDEN_SITREP_TEMPLATES_DESC", "")
	for label in str(options.get_value(OPTION_HIDDEN)).split(" ", false):
		hidden_labels[label] = true


func _save_hidden_labels() -> void:
	if not follow_game or not Engine.has_singleton("FOOptions"):
		return
	var options := Engine.get_singleton("FOOptions")
	options.set_value(OPTION_HIDDEN, " ".join(PackedStringArray(hidden_labels.keys())))
	options.commit()


# The ☰ menu: every report type seen this turn or hidden, ticked when shown.
func open_filter_menu() -> PopupMenu:
	var menu := _new_menu()
	# Every type seen on any turn (as GG's filter), and the hidden ones.
	if _seen_labels.size() < 2:
		for turn in range(1, _latest_turn + 1):
			for entry: Dictionary in entries_provider.call(turn):
				if not str(entry.get("label", "")).is_empty():
					_seen_labels[entry["label"]] = true
	var labels := _seen_labels.duplicate()
	labels.merge(hidden_labels)
	var sorted: Array = labels.keys()
	sorted.sort_custom(func(a, b): return _label_text(a) < _label_text(b))
	for label: String in sorted:
		menu.add_check_item(_label_text(label))
		var index := menu.item_count - 1
		menu.set_item_checked(index, not hidden_labels.has(label))
		menu.set_item_metadata(index, label)
	if not sorted.is_empty():
		menu.add_separator()
	menu.add_item(tr("NOTIFICATIONS_HIDE_ALL"))
	menu.set_item_metadata(menu.item_count - 1, "__hide_all")
	menu.add_item(tr("SITREP_SHOWALL_TEMPLATES"))
	menu.set_item_metadata(menu.item_count - 1, "__show_all")
	menu.set_item_disabled(menu.item_count - 1, hidden_labels.is_empty())
	menu.add_item(tr("SITREP_SNOOZE_CLEAR_ALL"))
	menu.set_item_metadata(menu.item_count - 1, "__unsnooze")
	menu.set_item_disabled(menu.item_count - 1, _snoozed.is_empty())
	menu.index_pressed.connect(
		func(index: int):
			var meta: String = menu.get_item_metadata(index)
			match meta:
				"__show_all":
					hidden_labels.clear()
					_save_hidden_labels()
					_show(_all_entries, _turn)
				"__unsnooze":
					clear_snoozed()
				"__hide_all":
					for label: String in labels:
						hidden_labels[label] = true
					_save_hidden_labels()
					_show(_all_entries, _turn)
				_:
					set_label_hidden(meta, not hidden_labels.has(meta))
	)
	_popup(menu, _filter.get_screen_position() + Vector2(0, _filter.size.y))
	return menu


# Right-click on a report: snooze it, hide its type, copy its text.
func open_entry_menu(entry: Dictionary, at: Vector2) -> PopupMenu:
	var menu := _new_menu()
	menu.add_item(tr("SITREP_SNOOZE_5_TURNS"), MENU_SNOOZE_5)
	menu.add_item(tr("SITREP_SNOOZE_10_TURNS"), MENU_SNOOZE_10)
	menu.add_item(tr("SITREP_SNOOZE_INDEFINITE"), MENU_SNOOZE_FOREVER)
	var label: String = entry.get("label", "")
	if not label.is_empty():
		menu.add_separator()
		menu.add_item(tr("SITREP_HIDE_TEMPLATE").replace("%1%", _label_text(label)), MENU_HIDE_TYPE)
	menu.add_separator()
	menu.add_item(tr("NOTIFICATIONS_COPY"), MENU_COPY)
	menu.id_pressed.connect(
		func(id: int):
			match id:
				MENU_SNOOZE_5:
					snooze(entry, 5)
				MENU_SNOOZE_10:
					snooze(entry, 10)
				MENU_SNOOZE_FOREVER:
					snooze(entry, 0)
				MENU_HIDE_TYPE:
					set_label_hidden(label, true)
				MENU_COPY:
					DisplayServer.clipboard_set(FORichText.plain_text(entry.get("text", "")))
	)
	_popup(menu, at)
	return menu


func _new_menu() -> PopupMenu:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu = PopupMenu.new()
	_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_menu)
	return _menu


func _popup(menu: PopupMenu, at: Vector2) -> void:
	menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


static func _label_text(label: String) -> String:
	return ScreenKit.tr_or_name(label)


func is_expanded() -> bool:
	return _scroll.visible


func set_expanded(expanded: bool) -> void:
	_scroll.visible = expanded
	_update_header()


func _refresh_from_game() -> void:
	show_entries(FOUniverse.get_sitreps(), GlobalFreeOrionNode.get_current_turn())


func _build() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var header_row := HBoxContainer.new()
	box.add_child(header_row)
	_header = Button.new()
	_header.theme_type_variation = "GhostButton"
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.pressed.connect(func(): set_expanded(not is_expanded()))
	header_row.add_child(_header)
	_prev = ScreenKit.small_button("‹", "NOTIFICATIONS_PREVIOUS_TURN")
	_prev.pressed.connect(step_turn.bind(-1))
	header_row.add_child(_prev)
	_next = ScreenKit.small_button("›", "NOTIFICATIONS_NEXT_TURN")
	_next.pressed.connect(step_turn.bind(1))
	header_row.add_child(_next)
	_latest = ScreenKit.small_button("⇥", "NOTIFICATIONS_LATEST")
	_latest.pressed.connect(func(): show_turn(_latest_turn))
	header_row.add_child(_latest)
	_filter = ScreenKit.small_button("☰", "NOTIFICATIONS_FILTER")
	_filter.pressed.connect(open_filter_menu)
	header_row.add_child(_filter)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = 0
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_list.resized.connect(_fit_height)


func _entry_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = FOArt.icon(entry.get("icon", ""))
	icon.custom_minimum_size = Vector2(FOUi.tokens.icon, FOUi.tokens.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = FORichText.to_bbcode(entry.get("text", ""), FOUi.tokens.icon_small)
	text.meta_clicked.connect(_on_meta_clicked)
	row.add_child(text)
	for target: Control in [row, text]:
		target.gui_input.connect(
			func(event: InputEvent):
				if not event is InputEventMouseButton or not event.pressed:
					return
				if event.button_index == MOUSE_BUTTON_RIGHT:
					open_entry_menu(entry, event.global_position)
					target.accept_event()
				elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
					# Double-click dismisses the report (this turn).
					snooze(entry, 1)
					target.accept_event()
		)
	return row


func _on_meta_clicked(meta: Variant) -> void:
	var link := FORichText.parse_link(str(meta))
	if link["kind"] == "url":
		OS.shell_open(link["arg"])
		return
	link_activated.emit(link["kind"], link["arg"])


# Grow with the content up to MAX_HEIGHT, then scroll.
func _fit_height() -> void:
	_scroll.custom_minimum_size.y = minf(_list.size.y, MAX_HEIGHT)


func _update_header() -> void:
	var arrow := "▾" if is_expanded() else "▸"
	var key := "NOTIFICATIONS_HEADER_ONE" if _entries.size() == 1 else "NOTIFICATIONS_HEADER"
	var title := tr(key).replace("%1%", str(_turn)).replace("%2%", str(_entries.size()))
	var hidden := _all_entries.size() - _entries.size()
	if hidden > 0:
		title += "  " + tr("NOTIFICATIONS_HIDDEN").replace("%1%", str(hidden))
	_header.text = "%s  %s" % [arrow, title]
	_prev.disabled = _turn <= 1
	_next.disabled = _turn >= _latest_turn
	_latest.disabled = _turn >= _latest_turn
